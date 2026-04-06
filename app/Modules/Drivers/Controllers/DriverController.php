<?php

declare(strict_types=1);

namespace App\Modules\Drivers\Controllers;

use App\Modules\Drivers\Services\DriverService;
use App\Shared\Database\Connection;
use App\Shared\Http\Request;
use App\Shared\Http\Response;

final class DriverController
{
    private DriverService $service;

    public function __construct()
    {
        $this->service = new DriverService();
    }

    public function activeRoute(Request $request): Response
    {
        $tenantId = $this->tenantId((string) $request->input('tenant_slug', 'default'));
        if ($tenantId === null) {
            return Response::json(['success' => false, 'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found']], 404);
        }

        $driverEmail = strtolower((string) $request->input('driver_email', ''));
        if ($driverEmail === '') {
            return Response::json(['success' => true, 'data' => ['route' => null, 'tasks' => []]]);
        }

        $driverId = $this->resolveUserId($tenantId, $driverEmail, 'DRIVER');
        $today = date('Y-m-d');
        $result = $this->service->activeRouteForDriver($tenantId, $driverId, $today);

        return Response::json(['success' => true, 'data' => $result]);
    }

    public function createRoute(Request $request): Response
    {
        $tenantId = $this->tenantId((string) $request->input('tenant_slug', 'default'));
        if ($tenantId === null) {
            return Response::json(['success' => false, 'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found']], 404);
        }

        $driverId = $this->resolveUserId($tenantId, strtolower((string) $request->input('driver_email', 'driver1@example.com')), 'DRIVER');
        $createdBy = $this->resolveUserId($tenantId, strtolower((string) $request->input('created_by_email', 'admin1@example.com')), 'ADMIN');
        $routeDate = (string) $request->input('route_date', date('Y-m-d'));

        $result = $this->service->createRoute($tenantId, $driverId, $createdBy, $routeDate);
        if (!$result['ok']) {
            return Response::json(['success' => false, 'error' => ['code' => $result['code'], 'message' => $result['message']]], $result['status']);
        }

        return Response::json(['success' => true, 'data' => ['route_id' => $result['route_id']]], 201);
    }

    public function assignTask(Request $request): Response
    {
        $tenantId = $this->tenantId((string) $request->input('tenant_slug', 'default'));
        if ($tenantId === null) {
            return Response::json(['success' => false, 'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found']], 404);
        }

        $result = $this->service->assignTask(
            $tenantId,
            (int) $request->input('route_id', 0),
            (int) $request->input('claim_id', 0),
            (string) $request->input('task_type', 'PICKUP_SERVICE')
        );

        return Response::json(['success' => $result['ok'], 'data' => ['task_id' => $result['task_id'] ?? null]], $result['status']);
    }

    public function completeTask(Request $request): Response
    {
        $tenantId = $this->tenantId((string) $request->input('tenant_slug', 'default'));
        if ($tenantId === null) {
            return Response::json(['success' => false, 'error' => ['code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found']], 404);
        }

        $result = $this->service->completeTaskWithHandshake(
            $tenantId,
            (int) $request->input('task_id', 0),
            (string) $request->input('batch_photo', 'batch.webp'),
            (string) $request->input('dealer_signature', 'signed-payload')
        );

        if (!$result['ok']) {
            return Response::json(['success' => false, 'error' => ['code' => $result['code'], 'message' => $result['message']]], $result['status']);
        }

        return Response::json(['success' => true, 'data' => ['handshake_id' => $result['handshake_id']]], 200);
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
