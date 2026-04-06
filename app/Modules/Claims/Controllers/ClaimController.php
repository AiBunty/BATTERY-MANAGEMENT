<?php

declare(strict_types=1);

namespace App\Modules\Claims\Controllers;

use App\Modules\Batteries\Services\BatteryService;
use App\Modules\Claims\Services\ClaimService;
use App\Shared\Database\Connection;
use App\Shared\Http\Request;
use App\Shared\Http\Response;

final class ClaimController
{
    private BatteryService $batteryService;
    private ClaimService $claimService;

    public function __construct()
    {
        $this->batteryService = new BatteryService();
        $this->claimService = new ClaimService();
    }

    public function checkSerial(Request $request): Response
    {
        $tenantSlug = (string) $request->input('tenant_slug', 'default');
        $serial = (string) $request->input('serial', '');

        $tenantId = $this->resolveTenantId($tenantSlug);
        if ($tenantId === null) {
            return Response::json([
                'success' => false,
                'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found'],
            ], 404);
        }

        $result = $this->batteryService->checkSerial($tenantId, $serial);

        if (!$result['ok']) {
            return Response::json([
                'success' => false,
                'error' => ['code' => $result['code'], 'message' => $result['message']],
            ], $result['status']);
        }

        return Response::json([
            'success' => true,
            'data' => [
                'battery_id' => $result['battery_id'],
                'serial' => $result['serial'],
                'is_orange_tick' => $result['is_orange_tick'],
            ],
        ]);
    }

    public function create(Request $request): Response
    {
        $tenantSlug = (string) $request->input('tenant_slug', 'default');
        $serial = (string) $request->input('serial', '');
        $dealerEmail = strtolower((string) $request->input('dealer_email', 'dealer1@example.com'));
        $complaint = (string) $request->input('complaint', '');

        $tenantId = $this->resolveTenantId($tenantSlug);
        if ($tenantId === null) {
            return Response::json([
                'success' => false,
                'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found'],
            ], 404);
        }

        $dealerId = $this->resolveDealerId($tenantId, $dealerEmail);
        if ($dealerId === null) {
            return Response::json([
                'success' => false,
                'error' => ['code' => 'DEALER_NOT_FOUND', 'message' => 'Dealer not found'],
            ], 404);
        }

        $idempotencyKey = (string) ($request->header('Idempotency-Key', '') ?? '');
        $idempotency = $this->acquireIdempotencyLock($tenantId, $dealerId, $idempotencyKey, $request->body);
        if (!$idempotency['ok']) {
            return Response::json([
                'success' => false,
                'error' => ['code' => $idempotency['code'], 'message' => $idempotency['message']],
            ], $idempotency['status']);
        }

        if (($idempotency['replay'] ?? false) === true) {
            return Response::json($idempotency['payload'], $idempotency['response_code']);
        }

        $serialCheck = $this->batteryService->checkSerial($tenantId, $serial);
        if (!$serialCheck['ok']) {
            return Response::json([
                'success' => false,
                'error' => ['code' => $serialCheck['code'], 'message' => $serialCheck['message']],
            ], $serialCheck['status']);
        }

        $created = $this->claimService->createClaim(
            tenantId: $tenantId,
            dealerId: $dealerId,
            batteryId: (int) $serialCheck['battery_id'],
            isOrangeTick: (bool) $serialCheck['is_orange_tick'],
            complaint: $complaint !== '' ? $complaint : null,
        );

        if (!$created['ok']) {
            $this->releaseIdempotencyLock($tenantId, $dealerId, $idempotencyKey);
            return Response::json([
                'success' => false,
                'error' => ['code' => $created['code'], 'message' => $created['message']],
            ], $created['status']);
        }

        $payload = [
            'success' => true,
            'data' => [
                'claim_id' => $created['claim_id'],
                'claim_number' => $created['claim_number'],
                'is_orange_tick' => $serialCheck['is_orange_tick'],
                'tracking_url' => $created['tracking_url'] ?? null,
            ],
        ];

        $this->completeIdempotencyLock($tenantId, $dealerId, $idempotencyKey, 201, $payload);

        return Response::json($payload, 201);
    }

    public function list(Request $request): Response
    {
        $tenantSlug   = (string) $request->input('tenant_slug', 'default');
        $dealerEmail  = strtolower((string) $request->input('dealer_email', ''));
        $rawStatus    = $request->input('status');
        $status       = ($rawStatus !== '' && $rawStatus !== null) ? strtoupper((string) $rawStatus) : null;
        $limit        = min((int) $request->input('limit', 20), 100);

        $tenantId = $this->resolveTenantId($tenantSlug);
        if ($tenantId === null) {
            return Response::json([
                'success' => false,
                'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found'],
            ], 404);
        }

        $dealerId = $this->lookupDealerId($tenantId, $dealerEmail);
        if ($dealerId === null) {
            return Response::json(['success' => true, 'data' => ['claims' => []]]);
        }

        $claims = $this->claimService->listByDealer($tenantId, $dealerId, $status, $limit);

        return Response::json(['success' => true, 'data' => ['claims' => $claims]]);
    }

    private function lookupDealerId(int $tenantId, string $email): ?int
    {
        if ($email === '') {
            return null;
        }

        $db = Connection::get();
        $stmt = $db->prepare('SELECT id FROM users WHERE tenant_id = :tenant_id AND email = :email LIMIT 1');
        $stmt->execute(['tenant_id' => $tenantId, 'email' => $email]);
        $row = $stmt->fetch();

        return $row ? (int) $row['id'] : null;
    }

    private function resolveTenantId(string $tenantSlug): ?int
    {
        $db = Connection::get();
        $stmt = $db->prepare('SELECT id FROM tenants WHERE slug = :slug AND is_active = 1 LIMIT 1');
        $stmt->execute(['slug' => $tenantSlug]);
        $row = $stmt->fetch();

        return $row ? (int) $row['id'] : null;
    }

    private function resolveDealerId(int $tenantId, string $email): ?int
    {
        $db = Connection::get();

        $stmt = $db->prepare('SELECT id FROM users WHERE tenant_id = :tenant_id AND email = :email LIMIT 1');
        $stmt->execute([
            'tenant_id' => $tenantId,
            'email' => $email,
        ]);
        $row = $stmt->fetch();
        if ($row) {
            return (int) $row['id'];
        }

        $insert = $db->prepare(
            "INSERT INTO users (tenant_id, name, email, legacy_role, is_active) VALUES (:tenant_id, :name, :email, 'DEALER', 1)"
        );
        $insert->execute([
            'tenant_id' => $tenantId,
            'name' => 'Dealer',
            'email' => $email,
        ]);

        return (int) $db->lastInsertId();
    }

    private function acquireIdempotencyLock(int $tenantId, int $userId, string $key, array $body): array
    {
        if ($key === '') {
            return ['ok' => true];
        }

        $db = Connection::get();
        $requestHash = $this->requestHash($body);

        $stmt = $db->prepare(
            'SELECT id, request_hash, status, response_code, response_body
             FROM api_idempotency_keys
             WHERE tenant_id = :tenant_id
               AND user_id = :user_id
               AND idempotency_key = :idempotency_key
               AND expires_at > NOW()
             LIMIT 1'
        );
        $stmt->execute([
            'tenant_id' => $tenantId,
            'user_id' => $userId,
            'idempotency_key' => $key,
        ]);
        $row = $stmt->fetch();

        if ($row) {
            if (!hash_equals((string) $row['request_hash'], $requestHash)) {
                return ['ok' => false, 'status' => 409, 'code' => 'IDEMPOTENCY_KEY_MISMATCH', 'message' => 'Idempotency key reused with different payload'];
            }

            if ($row['status'] === 'COMPLETE' && $row['response_body']) {
                return [
                    'ok' => true,
                    'replay' => true,
                    'response_code' => (int) ($row['response_code'] ?? 200),
                    'payload' => json_decode((string) $row['response_body'], true) ?: ['success' => false],
                ];
            }

            return ['ok' => false, 'status' => 409, 'code' => 'REQUEST_IN_PROGRESS', 'message' => 'Duplicate request is in progress'];
        }

        $insert = $db->prepare(
            "INSERT INTO api_idempotency_keys
             (tenant_id, user_id, idempotency_key, request_hash, status, expires_at)
             VALUES (:tenant_id, :user_id, :idempotency_key, :request_hash, 'PROCESSING', DATE_ADD(NOW(), INTERVAL 1 DAY))"
        );
        $insert->execute([
            'tenant_id' => $tenantId,
            'user_id' => $userId,
            'idempotency_key' => $key,
            'request_hash' => $requestHash,
        ]);

        return ['ok' => true];
    }

    private function completeIdempotencyLock(int $tenantId, int $userId, string $key, int $statusCode, array $payload): void
    {
        if ($key === '') {
            return;
        }

        $db = Connection::get();
        $stmt = $db->prepare(
            "UPDATE api_idempotency_keys
             SET status = 'COMPLETE', response_code = :response_code, response_body = :response_body
             WHERE tenant_id = :tenant_id AND user_id = :user_id AND idempotency_key = :idempotency_key"
        );
        $stmt->execute([
            'response_code' => $statusCode,
            'response_body' => json_encode($payload, JSON_UNESCAPED_SLASHES),
            'tenant_id' => $tenantId,
            'user_id' => $userId,
            'idempotency_key' => $key,
        ]);
    }

    private function releaseIdempotencyLock(int $tenantId, int $userId, string $key): void
    {
        if ($key === '') {
            return;
        }

        $db = Connection::get();
        $stmt = $db->prepare('DELETE FROM api_idempotency_keys WHERE tenant_id = :tenant_id AND user_id = :user_id AND idempotency_key = :idempotency_key AND status = :status');
        $stmt->execute([
            'tenant_id' => $tenantId,
            'user_id' => $userId,
            'idempotency_key' => $key,
            'status' => 'PROCESSING',
        ]);
    }

    private function requestHash(array $payload): string
    {
        $sorted = $this->sortRecursive($payload);
        return hash('sha256', json_encode($sorted, JSON_UNESCAPED_SLASHES) ?: '{}');
    }

    private function sortRecursive(array $input): array
    {
        foreach ($input as $k => $v) {
            if (is_array($v)) {
                $input[$k] = $this->sortRecursive($v);
            }
        }

        ksort($input);
        return $input;
    }
}
