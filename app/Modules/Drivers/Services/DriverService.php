<?php

declare(strict_types=1);

namespace App\Modules\Drivers\Services;

use App\Modules\Audit\Services\AuditService;
use App\Modules\Finance\Services\IncentiveService;
use App\Shared\Database\Connection;
use PDO;

final class DriverService
{
    private PDO $db;
    private AuditService $auditService;
    private IncentiveService $incentiveService;

    public function __construct()
    {
        $this->db = Connection::get();
        $this->auditService = new AuditService();
        $this->incentiveService = new IncentiveService();
    }

    public function activeRouteForDriver(int $tenantId, int $driverId, string $date): array
    {
        $stmt = $this->db->prepare(
            'SELECT id, route_date, status
             FROM driver_routes
             WHERE tenant_id = :tenant_id AND driver_id = :driver_id AND route_date = :route_date
             LIMIT 1'
        );
        $stmt->execute([
            'tenant_id' => $tenantId,
            'driver_id'  => $driverId,
            'route_date' => $date,
        ]);
        $route = $stmt->fetch(\PDO::FETCH_ASSOC);

        if (!$route) {
            return ['route' => null, 'tasks' => []];
        }

        $tasksStmt = $this->db->prepare(
            'SELECT t.id, t.task_type, t.status, t.completed_at,
                    c.claim_number, c.status AS claim_status
             FROM driver_tasks t
             LEFT JOIN claims c ON c.id = t.claim_id
             WHERE t.route_id = :route_id
             ORDER BY t.id ASC'
        );
        $tasksStmt->execute(['route_id' => $route['id']]);
        $tasks = $tasksStmt->fetchAll(\PDO::FETCH_ASSOC) ?: [];

        return ['route' => $route, 'tasks' => $tasks];
    }

    public function createRoute(int $tenantId, int $driverId, int $createdBy, string $routeDate): array
    {
        $stmt = $this->db->prepare(
            "INSERT INTO driver_routes (tenant_id, driver_id, route_date, status, created_by)
             VALUES (:tenant_id, :driver_id, :route_date, 'PLANNED', :created_by)"
        );

        try {
            $stmt->execute([
                'tenant_id' => $tenantId,
                'driver_id' => $driverId,
                'route_date' => $routeDate,
                'created_by' => $createdBy,
            ]);
        } catch (\Throwable $e) {
            return ['ok' => false, 'status' => 422, 'code' => 'ROUTE_CREATE_FAILED', 'message' => 'Route could not be created'];
        }

        $routeId = (int) $this->db->lastInsertId();
        $this->auditService->log($tenantId, $createdBy, 'driver.route_created', 'driver_routes', $routeId, [], [
            'driver_id' => $driverId,
            'route_date' => $routeDate,
        ], 'LOW');

        return ['ok' => true, 'status' => 201, 'route_id' => $routeId];
    }

    public function assignTask(int $tenantId, int $routeId, int $claimId, string $taskType): array
    {
        $stmt = $this->db->prepare(
            'INSERT INTO driver_tasks (tenant_id, route_id, claim_id, task_type, status) VALUES (:tenant_id, :route_id, :claim_id, :task_type, :status)'
        );
        $stmt->execute([
            'tenant_id' => $tenantId,
            'route_id' => $routeId,
            'claim_id' => $claimId,
            'task_type' => $taskType,
            'status' => 'PENDING',
        ]);

        return ['ok' => true, 'status' => 201, 'task_id' => (int) $this->db->lastInsertId()];
    }

    public function completeTaskWithHandshake(int $tenantId, int $taskId, string $batchPhoto, string $dealerSignature): array
    {
        $taskStmt = $this->db->prepare(
            'SELECT t.id, t.tenant_id, t.route_id, t.claim_id, t.task_type, t.status, c.dealer_id, r.driver_id
             FROM driver_tasks t
             JOIN claims c ON c.id = t.claim_id
             JOIN driver_routes r ON r.id = t.route_id
             WHERE t.tenant_id = :tenant_id AND t.id = :task_id LIMIT 1'
        );
        $taskStmt->execute([
            'tenant_id' => $tenantId,
            'task_id' => $taskId,
        ]);
        $task = $taskStmt->fetch();

        if (!$task) {
            return ['ok' => false, 'status' => 404, 'code' => 'TASK_NOT_FOUND', 'message' => 'Task not found'];
        }

        if ($task['status'] === 'DONE') {
            return ['ok' => false, 'status' => 409, 'code' => 'TASK_ALREADY_DONE', 'message' => 'Task already completed'];
        }

        $sigHash = hash('sha256', $dealerSignature);

        $this->db->beginTransaction();
        try {
            $handshakeStmt = $this->db->prepare(
                'INSERT INTO driver_handshakes (tenant_id, route_id, driver_id, dealer_id, batch_photo, dealer_signature, sig_hash)
                 VALUES (:tenant_id, :route_id, :driver_id, :dealer_id, :batch_photo, :dealer_signature, :sig_hash)'
            );
            $handshakeStmt->execute([
                'tenant_id' => $tenantId,
                'route_id' => $task['route_id'],
                'driver_id' => $task['driver_id'],
                'dealer_id' => $task['dealer_id'],
                'batch_photo' => $batchPhoto,
                'dealer_signature' => $dealerSignature,
                'sig_hash' => $sigHash,
            ]);
            $handshakeId = (int) $this->db->lastInsertId();

            $pivot = $this->db->prepare('INSERT INTO handshake_tasks (handshake_id, task_id) VALUES (:handshake_id, :task_id)');
            $pivot->execute([
                'handshake_id' => $handshakeId,
                'task_id' => $taskId,
            ]);

            $taskUpdate = $this->db->prepare("UPDATE driver_tasks SET status = 'DONE', completed_at = NOW() WHERE id = :id");
            $taskUpdate->execute(['id' => $taskId]);

            $claimUpdate = $this->db->prepare("UPDATE claims SET status = 'DRIVER_RECEIVED' WHERE id = :claim_id");
            $claimUpdate->execute(['claim_id' => $task['claim_id']]);

            $history = $this->db->prepare(
                'INSERT INTO claim_status_history (claim_id, from_status, to_status, changed_by) VALUES (:claim_id, :from_status, :to_status, :changed_by)'
            );
            $history->execute([
                'claim_id' => $task['claim_id'],
                'from_status' => 'DRAFT',
                'to_status' => 'DRIVER_RECEIVED',
                'changed_by' => $task['driver_id'],
            ]);

            $this->incentiveService->recordIfEligible($task, $handshakeId);

            $this->auditService->log($tenantId, (int) $task['driver_id'], 'driver.task_completed', 'driver_tasks', $taskId, [], [
                'handshake_id' => $handshakeId,
                'task_type' => $task['task_type'],
            ], 'MEDIUM');

            $this->db->commit();

            return ['ok' => true, 'status' => 200, 'handshake_id' => $handshakeId];
        } catch (\Throwable $e) {
            if ($this->db->inTransaction()) {
                $this->db->rollBack();
            }
            return ['ok' => false, 'status' => 500, 'code' => 'TASK_COMPLETE_FAILED', 'message' => 'Task completion failed'];
        }
    }
}
