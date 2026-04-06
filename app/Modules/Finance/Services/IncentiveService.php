<?php

declare(strict_types=1);

namespace App\Modules\Finance\Services;

use App\Shared\Database\Connection;
use PDO;

final class IncentiveService
{
    private PDO $db;

    public function __construct()
    {
        $this->db = Connection::get();
    }

    public function recordIfEligible(array $task, int $handshakeId): void
    {
        if (!in_array($task['task_type'], ['DELIVERY_NEW', 'DELIVERY_REPLACEMENT'], true)) {
            return;
        }

        $stmt = $this->db->prepare(
            'INSERT INTO delivery_incentives (tenant_id, driver_id, task_id, claim_id, handshake_id, task_type, amount, delivery_date, is_paid)
             VALUES (:tenant_id, :driver_id, :task_id, :claim_id, :handshake_id, :task_type, :amount, CURDATE(), 0)'
        );
        $stmt->execute([
            'tenant_id' => $task['tenant_id'],
            'driver_id' => $task['driver_id'],
            'task_id' => $task['id'],
            'claim_id' => $task['claim_id'],
            'handshake_id' => $handshakeId,
            'task_type' => $task['task_type'],
            'amount' => 10.00,
        ]);
    }
}
