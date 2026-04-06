<?php

declare(strict_types=1);

namespace App\Modules\Tracking\Services;

use App\Shared\Config\Env;
use App\Shared\Database\Connection;
use PDO;

final class TrackingService
{
    private PDO $db;

    public function __construct()
    {
        Env::load(dirname(__DIR__, 4) . '/.env');
        $this->db = Connection::get();
    }

    public function getOrCreateTokenUrl(int $tenantId, int $claimId): string
    {
        $stmt = $this->db->prepare(
            'SELECT token FROM claim_tracking_tokens
             WHERE tenant_id = :tenant_id
               AND claim_id = :claim_id
               AND expires_at > NOW()
             LIMIT 1'
        );
        $stmt->execute([
            'tenant_id' => $tenantId,
            'claim_id' => $claimId,
        ]);
        $row = $stmt->fetch();

        if ($row) {
            return rtrim((string) Env::get('TRACKING_URL_BASE', 'http://localhost:8000/track'), '/') . '/' . $row['token'];
        }

        $token = bin2hex(random_bytes(32));
        $ttlDays = (int) Env::get('TRACKING_TOKEN_TTL_DAYS', '90');

        $upsert = $this->db->prepare(
            'INSERT INTO claim_tracking_tokens (tenant_id, claim_id, token, expires_at, view_count, last_viewed_at)
             VALUES (:tenant_id, :claim_id, :token, DATE_ADD(NOW(), INTERVAL :ttl DAY), 0, NULL)
             ON DUPLICATE KEY UPDATE token = VALUES(token), expires_at = VALUES(expires_at), view_count = 0, last_viewed_at = NULL'
        );
        $upsert->bindValue(':tenant_id', $tenantId, PDO::PARAM_INT);
        $upsert->bindValue(':claim_id', $claimId, PDO::PARAM_INT);
        $upsert->bindValue(':token', $token);
        $upsert->bindValue(':ttl', $ttlDays, PDO::PARAM_INT);
        $upsert->execute();

        return rtrim((string) Env::get('TRACKING_URL_BASE', 'http://localhost:8000/track'), '/') . '/' . $token;
    }

    public function resolve(string $token): ?array
    {
        if (!preg_match('/^[a-f0-9]{64}$/', $token)) {
            return null;
        }

        $stmt = $this->db->prepare(
            'SELECT t.tenant_id, t.claim_id, t.expires_at, c.claim_number, c.status, c.created_at, c.updated_at,
                    b.serial_number, u.name AS dealer_name
             FROM claim_tracking_tokens t
             JOIN claims c ON c.id = t.claim_id
             JOIN batteries b ON b.id = c.battery_id
             JOIN users u ON u.id = c.dealer_id
             WHERE t.token = :token
             LIMIT 1'
        );
        $stmt->execute(['token' => $token]);
        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }

        if (strtotime((string) $row['expires_at']) < time()) {
            return ['expired' => true];
        }

        $touch = $this->db->prepare('UPDATE claim_tracking_tokens SET view_count = view_count + 1, last_viewed_at = NOW() WHERE token = :token');
        $touch->execute(['token' => $token]);

        $maskedSerial = str_repeat('*', max(0, strlen((string) $row['serial_number']) - 4)) . substr((string) $row['serial_number'], -4);

        return [
            'expired' => false,
            'claim_number' => $row['claim_number'],
            'status' => $row['status'],
            'created_at' => $row['created_at'],
            'updated_at' => $row['updated_at'],
            'battery_serial_masked' => $maskedSerial,
            'dealer_name' => $row['dealer_name'],
        ];
    }

    public function lookupByTicket(string $tenantSlug, string $ticketNumber, string $ip): array
    {
        $tenantStmt = $this->db->prepare('SELECT id FROM tenants WHERE slug = :slug AND is_active = 1 LIMIT 1');
        $tenantStmt->execute(['slug' => $tenantSlug]);
        $tenant = $tenantStmt->fetch();
        if (!$tenant) {
            return ['ok' => false, 'status' => 404, 'code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found'];
        }

        $rate = $this->db->prepare(
            'SELECT COUNT(*) AS c FROM ticket_lookup_attempts
             WHERE ip_address = :ip AND attempted_at > DATE_SUB(NOW(), INTERVAL 15 MINUTE)'
        );
        $rate->execute(['ip' => $ip]);
        $count = (int) ($rate->fetch()['c'] ?? 0);
        if ($count >= 10) {
            return ['ok' => false, 'status' => 429, 'code' => 'RATE_LIMITED', 'message' => 'Too many lookup attempts'];
        }

        $log = $this->db->prepare('INSERT INTO ticket_lookup_attempts (ip_address, ticket_number) VALUES (:ip, :ticket_number)');
        $log->execute([
            'ip' => $ip,
            'ticket_number' => $ticketNumber,
        ]);

        $stmt = $this->db->prepare(
            'SELECT t.token
             FROM claim_tracking_tokens t
             JOIN claims c ON c.id = t.claim_id
             WHERE c.tenant_id = :tenant_id
               AND c.claim_number = :claim_number
               AND t.expires_at > NOW()
             LIMIT 1'
        );
        $stmt->execute([
            'tenant_id' => $tenant['id'],
            'claim_number' => $ticketNumber,
        ]);
        $row = $stmt->fetch();

        if (!$row) {
            return ['ok' => false, 'status' => 422, 'code' => 'TICKET_NOT_FOUND', 'message' => 'Ticket not found or expired'];
        }

        return [
            'ok' => true,
            'status' => 200,
            'token' => $row['token'],
            'tracking_url' => rtrim((string) Env::get('TRACKING_URL_BASE', 'http://localhost:8000/track'), '/') . '/' . $row['token'],
        ];
    }
}
