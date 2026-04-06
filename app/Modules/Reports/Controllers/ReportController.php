<?php

declare(strict_types=1);

namespace App\Modules\Reports\Controllers;

use App\Modules\Reports\Services\ReportService;
use App\Shared\Database\Connection;
use App\Shared\Http\Request;
use App\Shared\Http\Response;

final class ReportController
{
    private ReportService $service;

    public function __construct()
    {
        $this->service = new ReportService();
    }

    public function lemon(Request $request): Response
    {
        $tenantId = $this->tenantId((string) $request->input('tenant_slug', 'default'));
        if ($tenantId === null) {
            return Response::json(['success' => false, 'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found']], 404);
        }

        return Response::json(['success' => true, 'data' => $this->service->lemonReport($tenantId)]);
    }

    public function finance(Request $request): Response
    {
        $tenantId = $this->tenantId((string) $request->input('tenant_slug', 'default'));
        if ($tenantId === null) {
            return Response::json(['success' => false, 'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found']], 404);
        }

        return Response::json(['success' => true, 'data' => $this->service->financeReport($tenantId, (string) $request->input('month', date('Y-m')))]);
    }

    public function auditSummary(Request $request): Response
    {
        $tenantId = $this->tenantId((string) $request->input('tenant_slug', 'default'));
        if ($tenantId === null) {
            return Response::json(['success' => false, 'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found']], 404);
        }

        return Response::json(['success' => true, 'data' => $this->service->auditSummary($tenantId)]);
    }

    private function tenantId(string $slug): ?int
    {
        $db = Connection::get();
        $stmt = $db->prepare('SELECT id FROM tenants WHERE slug = :slug LIMIT 1');
        $stmt->execute(['slug' => $slug]);
        $row = $stmt->fetch();
        return $row ? (int) $row['id'] : null;
    }
}
