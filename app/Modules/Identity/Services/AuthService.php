<?php

declare(strict_types=1);

namespace App\Modules\Identity\Services;

use App\Shared\Config\Env;
use App\Shared\Database\Connection;
use PDO;

final class AuthService
{
    private PDO $db;
    private TokenService $tokenService;

    public function __construct()
    {
        Env::load(dirname(__DIR__, 4) . '/.env');
        $this->db = Connection::get();
        $this->tokenService = new TokenService();
    }

    public function sendOtp(string $tenantSlug, string $email, string $ip): array
    {
        $tenant = $this->findTenantBySlug($tenantSlug);
        if ($tenant === null) {
            return ['ok' => false, 'status' => 404, 'code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found'];
        }

        if ($this->isRateLimited($tenant['id'], $email, $ip, 'SEND_OTP', 3, 10)) {
            return ['ok' => false, 'status' => 429, 'code' => 'RATE_LIMITED', 'message' => 'Too many OTP requests'];
        }

        $user = $this->findOrCreateUser((int) $tenant['id'], $email);

        $otp = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        $hash = hash('sha256', $otp);

        $stmt = $this->db->prepare(
            'INSERT INTO otp_tokens (tenant_id, user_id, token_hash, expires_at) VALUES (:tenant_id, :user_id, :token_hash, DATE_ADD(NOW(), INTERVAL 10 MINUTE))'
        );
        $stmt->execute([
            'tenant_id' => $tenant['id'],
            'user_id' => $user['id'],
            'token_hash' => $hash,
        ]);

        $body = 'Your OTP is ' . $otp . '. It is valid for 10 minutes.';

        $mailStmt = $this->db->prepare(
            'INSERT INTO email_queue (tenant_id, recipient, subject, body, status, attempts) VALUES (:tenant_id, :recipient, :subject, :body, :status, 0)'
        );
        $mailStmt->execute([
            'tenant_id' => $tenant['id'],
            'recipient' => $email,
            'subject' => 'Login OTP',
            'body' => $body,
            'status' => 'PENDING',
        ]);

        return [
            'ok' => true,
            'status' => 200,
            'tenant_id' => (int) $tenant['id'],
            'user_id' => (int) $user['id'],
            'debug_otp' => Env::get('APP_ENV', 'local') === 'local' ? $otp : null,
        ];
    }

    public function verifyOtp(string $tenantSlug, string $email, string $otp, string $ip): array
    {
        $tenant = $this->findTenantBySlug($tenantSlug);
        if ($tenant === null) {
            return ['ok' => false, 'status' => 404, 'code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found'];
        }

        if ($this->isRateLimited($tenant['id'], $email, $ip, 'VERIFY_OTP', 5, 10)) {
            return ['ok' => false, 'status' => 429, 'code' => 'RATE_LIMITED', 'message' => 'Too many verification attempts'];
        }

        $stmt = $this->db->prepare(
            'SELECT u.id AS user_id, t.id AS otp_id, t.token_hash
             FROM users u
             JOIN otp_tokens t ON t.user_id = u.id AND t.tenant_id = u.tenant_id
             WHERE u.tenant_id = :tenant_id
               AND u.email = :email
               AND t.used = 0
               AND t.expires_at > NOW()
             ORDER BY t.id DESC
             LIMIT 1'
        );
        $stmt->execute([
            'tenant_id' => $tenant['id'],
            'email' => $email,
        ]);

        $row = $stmt->fetch();
        if (!$row || !hash_equals($row['token_hash'], hash('sha256', $otp))) {
            $this->recordAttempt((int) $tenant['id'], null, $email, $ip, 'VERIFY_OTP', 0);
            return ['ok' => false, 'status' => 401, 'code' => 'INVALID_OTP', 'message' => 'Invalid OTP'];
        }

        $this->db->beginTransaction();
        try {
            $upd = $this->db->prepare('UPDATE otp_tokens SET used = 1 WHERE id = :id');
            $upd->execute(['id' => $row['otp_id']]);

            $this->recordAttempt((int) $tenant['id'], (int) $row['user_id'], $email, $ip, 'VERIFY_OTP', 1);

            $accessToken = $this->tokenService->issueAccessToken((int) $tenant['id'], (int) $row['user_id'], (string) $tenant['slug']);
            $refreshToken = bin2hex(random_bytes(32));

            $tokenStmt = $this->db->prepare(
                'INSERT INTO auth_refresh_tokens (tenant_id, user_id, token_hash, ip_address, expires_at)
                 VALUES (:tenant_id, :user_id, :token_hash, :ip_address, DATE_ADD(NOW(), INTERVAL 30 DAY))'
            );
            $tokenStmt->execute([
                'tenant_id' => $tenant['id'],
                'user_id' => $row['user_id'],
                'token_hash' => hash('sha256', $refreshToken),
                'ip_address' => $ip,
            ]);

            $this->db->commit();

            return [
                'ok' => true,
                'status' => 200,
                'access_token' => $accessToken,
                'refresh_token' => $refreshToken,
                'expires_in' => 900,
            ];
        } catch (\Throwable $e) {
            if ($this->db->inTransaction()) {
                $this->db->rollBack();
            }
            return ['ok' => false, 'status' => 500, 'code' => 'VERIFY_FAILED', 'message' => 'Verification failed'];
        }
    }

    private function findTenantBySlug(string $slug): ?array
    {
        $stmt = $this->db->prepare('SELECT id, slug FROM tenants WHERE slug = :slug AND is_active = 1 LIMIT 1');
        $stmt->execute(['slug' => $slug]);
        $row = $stmt->fetch();

        return $row ?: null;
    }

    public function refresh(string $tenantSlug, string $refreshToken, string $ip): array
    {
        $tenant = $this->findTenantBySlug($tenantSlug);
        if ($tenant === null) {
            return ['ok' => false, 'status' => 404, 'code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found'];
        }

        if ($this->isRateLimited((int) $tenant['id'], 'refresh:' . substr($refreshToken, 0, 12), $ip, 'REFRESH_TOKEN', 10, 10)) {
            return ['ok' => false, 'status' => 429, 'code' => 'RATE_LIMITED', 'message' => 'Too many refresh attempts'];
        }

        $stmt = $this->db->prepare(
            'SELECT id, user_id
             FROM auth_refresh_tokens
             WHERE tenant_id = :tenant_id
               AND token_hash = :token_hash
               AND revoked_at IS NULL
               AND expires_at > NOW()
             LIMIT 1'
        );
        $stmt->execute([
            'tenant_id' => $tenant['id'],
            'token_hash' => hash('sha256', $refreshToken),
        ]);
        $row = $stmt->fetch();

        if (!$row) {
            $this->recordAttempt((int) $tenant['id'], null, 'refresh:' . substr($refreshToken, 0, 12), $ip, 'REFRESH_TOKEN', 0);
            return ['ok' => false, 'status' => 401, 'code' => 'INVALID_REFRESH_TOKEN', 'message' => 'Refresh token is invalid'];
        }

        $this->db->beginTransaction();
        try {
            $revoke = $this->db->prepare('UPDATE auth_refresh_tokens SET revoked_at = NOW(), last_used_at = NOW() WHERE id = :id');
            $revoke->execute(['id' => $row['id']]);

            $newRefresh = bin2hex(random_bytes(32));
            $insert = $this->db->prepare(
                'INSERT INTO auth_refresh_tokens (tenant_id, user_id, token_hash, ip_address, expires_at)
                 VALUES (:tenant_id, :user_id, :token_hash, :ip_address, DATE_ADD(NOW(), INTERVAL 30 DAY))'
            );
            $insert->execute([
                'tenant_id' => $tenant['id'],
                'user_id' => $row['user_id'],
                'token_hash' => hash('sha256', $newRefresh),
                'ip_address' => $ip,
            ]);

            $this->recordAttempt((int) $tenant['id'], (int) $row['user_id'], 'refresh:' . substr($refreshToken, 0, 12), $ip, 'REFRESH_TOKEN', 1);
            $this->db->commit();

            return [
                'ok' => true,
                'status' => 200,
                'access_token' => $this->tokenService->issueAccessToken((int) $tenant['id'], (int) $row['user_id'], (string) $tenant['slug']),
                'refresh_token' => $newRefresh,
                'expires_in' => 900,
            ];
        } catch (\Throwable $e) {
            if ($this->db->inTransaction()) {
                $this->db->rollBack();
            }
            return ['ok' => false, 'status' => 500, 'code' => 'REFRESH_FAILED', 'message' => 'Refresh failed'];
        }
    }

    public function logout(string $tenantSlug, string $refreshToken): array
    {
        $tenant = $this->findTenantBySlug($tenantSlug);
        if ($tenant === null) {
            return ['ok' => false, 'status' => 404, 'code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found'];
        }

        $stmt = $this->db->prepare(
            'UPDATE auth_refresh_tokens
             SET revoked_at = NOW()
             WHERE tenant_id = :tenant_id
               AND token_hash = :token_hash
               AND revoked_at IS NULL'
        );
        $stmt->execute([
            'tenant_id' => $tenant['id'],
            'token_hash' => hash('sha256', $refreshToken),
        ]);

        if ($stmt->rowCount() === 0) {
            return ['ok' => false, 'status' => 401, 'code' => 'INVALID_REFRESH_TOKEN', 'message' => 'Refresh token is invalid'];
        }

        return ['ok' => true, 'status' => 200];
    }

    private function findOrCreateUser(int $tenantId, string $email): array
    {
        $stmt = $this->db->prepare('SELECT id, email FROM users WHERE tenant_id = :tenant_id AND email = :email LIMIT 1');
        $stmt->execute([
            'tenant_id' => $tenantId,
            'email' => $email,
        ]);

        $row = $stmt->fetch();
        if ($row) {
            return $row;
        }

        $insert = $this->db->prepare(
            'INSERT INTO users (tenant_id, name, email, legacy_role, is_active) VALUES (:tenant_id, :name, :email, :legacy_role, 1)'
        );
        $insert->execute([
            'tenant_id' => $tenantId,
            'name' => 'User ' . strstr($email, '@', true),
            'email' => $email,
            'legacy_role' => 'DEALER',
        ]);

        return [
            'id' => (int) $this->db->lastInsertId(),
            'email' => $email,
        ];
    }

    private function isRateLimited(int $tenantId, string $identifier, string $ip, string $attemptType, int $maxAttempts, int $windowMinutes): bool
    {
        $stmt = $this->db->prepare(
            'SELECT COUNT(*) AS c
             FROM login_attempts
             WHERE tenant_id = :tenant_id
               AND identifier = :identifier
               AND ip_address = :ip
               AND attempt_type = :attempt_type
               AND success = 0
               AND attempted_at > DATE_SUB(NOW(), INTERVAL :window MINUTE)'
        );
        $stmt->bindValue(':tenant_id', $tenantId, PDO::PARAM_INT);
        $stmt->bindValue(':identifier', $identifier);
        $stmt->bindValue(':ip', $ip);
        $stmt->bindValue(':attempt_type', $attemptType);
        $stmt->bindValue(':window', $windowMinutes, PDO::PARAM_INT);
        $stmt->execute();

        $count = (int) ($stmt->fetch()['c'] ?? 0);

        return $count >= $maxAttempts;
    }

    private function recordAttempt(int $tenantId, ?int $userId, string $identifier, string $ip, string $attemptType, int $success): void
    {
        $stmt = $this->db->prepare(
            'INSERT INTO login_attempts (tenant_id, user_id, identifier, ip_address, attempt_type, success)
             VALUES (:tenant_id, :user_id, :identifier, :ip_address, :attempt_type, :success)'
        );
        $stmt->bindValue(':tenant_id', $tenantId, PDO::PARAM_INT);
        $stmt->bindValue(':user_id', $userId, $userId === null ? PDO::PARAM_NULL : PDO::PARAM_INT);
        $stmt->bindValue(':identifier', $identifier);
        $stmt->bindValue(':ip_address', $ip);
        $stmt->bindValue(':attempt_type', $attemptType);
        $stmt->bindValue(':success', $success, PDO::PARAM_INT);
        $stmt->execute();
    }
}
