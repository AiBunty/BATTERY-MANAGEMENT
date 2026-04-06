<?php

declare(strict_types=1);

namespace App\Modules\ServiceCenter\Controllers;

use App\Modules\ServiceCenter\Services\ServiceJobService;
use App\Shared\Database\Connection;
use App\Shared\Http\Request;
use App\Shared\Http\Response;

final class ServiceController
{
    private ServiceJobService $service;

    public function __construct()
    {
        $this->service = new ServiceJobService();
    }

    public function inward(Request $request): Response
    {
        $tenantId = $this->tenantId((string) $request->input('tenant_slug', 'default'));
        if ($tenantId === null) {
            return Response::json(['success' => false, 'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found']], 404);
        }

        $testerId = $this->resolveUserId($tenantId, strtolower((string) $request->input('tester_email', 'tester1@example.com')), 'TESTER');
        $result = $this->service->inward($tenantId, (int) $request->input('claim_id', 0), $testerId);

        return Response::json(['success' => $result['ok'], 'data' => ['service_job_id' => $result['service_job_id'] ?? null]], $result['status']);
    }

    public function diagnose(Request $request): Response
    {
        $tenantId = $this->tenantId((string) $request->input('tenant_slug', 'default'));
        if ($tenantId === null) {
            return Response::json(['success' => false, 'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found']], 404);
        }

        $result = $this->service->diagnose(
            $tenantId,
            (int) $request->input('service_job_id', 0),
            (string) $request->input('diagnosis', 'OK'),
            (string) $request->input('diagnosis_notes', '')
        );

        if (!$result['ok']) {
            return Response::json(['success' => false, 'error' => ['code' => $result['code'], 'message' => $result['message']]], $result['status']);
        }

        return Response::json(['success' => true, 'data' => ['claim_status' => $result['claim_status']]], 200);
    }

    private function tenantId(string $slug): ?int
    {
        $db = Connection::get();
        $stmt = $db->prepare('SELECT id FROM tenants WHERE slug = :slug LIMIT 1');
        $stmt->execute(['slug' => $slug]);
        $row = $stmt->fetch();
        return $row ? (int) $row['id'] : null;
    }

    private function resolveUserId(int $tenantId, string $email, string $role): int
    {
        $db = Connection::get();
        $stmt = $db->prepare('SELECT id FROM users WHERE tenant_id = :tenant_id AND email = :email LIMIT 1');
        $stmt->execute(['tenant_id' => $tenantId, 'email' => $email]);
        $row = $stmt->fetch();
        if ($row) {
            return (int) $row['id'];
        }

        $insert = $db->prepare('INSERT INTO users (tenant_id, name, email, legacy_role, is_active) VALUES (:tenant_id, :name, :email, :legacy_role, 1)');
        $insert->execute([
            'tenant_id' => $tenantId,
            'name' => ucfirst(strtolower($role)),
            'email' => $email,
            'legacy_role' => $role,
        ]);

        return (int) $db->lastInsertId();
    }
}
