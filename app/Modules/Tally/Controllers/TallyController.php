<?php

declare(strict_types=1);

namespace App\Modules\Tally\Controllers;

use App\Modules\Tally\Services\TallyService;
use App\Shared\Database\Connection;
use App\Shared\Http\Request;
use App\Shared\Http\Response;

final class TallyController
{
    private TallyService $service;

    public function __construct()
    {
        $this->service = new TallyService();
    }

    public function import(Request $request): Response
    {
        $tenantId = $this->tenantId((string) $request->input('tenant_slug', 'default'));
        if ($tenantId === null) {
            return Response::json(['success' => false, 'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found']], 404);
        }

        $userId = $this->resolveUserId($tenantId, strtolower((string) $request->input('imported_by_email', 'admin-tally@example.com')), 'ADMIN');
        $rows = $request->input('rows', []);
        if (!is_array($rows)) {
            return Response::json(['success' => false, 'error' => ['code' => 'VALIDATION_ERROR', 'message' => 'rows must be an array']], 422);
        }

        $result = $this->service->importRows($tenantId, $userId, (string) $request->input('filename', 'import.json'), $rows);
        return Response::json(['success' => true, 'data' => $result], 202);
    }

    public function export(Request $request): Response
    {
        $tenantId = $this->tenantId((string) $request->input('tenant_slug', 'default'));
        if ($tenantId === null) {
            return Response::json(['success' => false, 'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found']], 404);
        }

        $userId = $this->resolveUserId($tenantId, strtolower((string) $request->input('exported_by_email', 'admin-tally@example.com')), 'ADMIN');
        $result = $this->service->exportBatteries($tenantId, $userId);
        return Response::json(['success' => true, 'data' => $result]);
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
