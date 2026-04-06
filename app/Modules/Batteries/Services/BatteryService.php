<?php

declare(strict_types=1);

namespace App\Modules\Batteries\Services;

use App\Shared\Database\Connection;
use PDO;

final class BatteryService
{
    private PDO $db;

    public function __construct()
    {
        $this->db = Connection::get();
    }

    public function checkSerial(int $tenantId, string $serial): array
    {
        $serial = strtoupper(trim($serial));

        if (!preg_match('/^[A-Z0-9]{14,15}$/', $serial)) {
            return ['ok' => false, 'status' => 422, 'code' => 'INVALID_SERIAL', 'message' => 'Serial format is invalid'];
        }

        $stmt = $this->db->prepare('SELECT id, is_in_tally FROM batteries WHERE tenant_id = :tenant_id AND serial_number = :serial LIMIT 1');
        $stmt->execute([
            'tenant_id' => $tenantId,
            'serial' => $serial,
        ]);

        $row = $stmt->fetch();
        if (!$row) {
            $insert = $this->db->prepare(
                "INSERT INTO batteries (tenant_id, serial_number, is_in_tally, status) VALUES (:tenant_id, :serial, 0, 'IN_STOCK')"
            );
            $insert->execute([
                'tenant_id' => $tenantId,
                'serial' => $serial,
            ]);

            return [
                'ok' => true,
                'status' => 200,
                'battery_id' => (int) $this->db->lastInsertId(),
                'is_orange_tick' => true,
                'serial' => $serial,
            ];
        }

        return [
            'ok' => true,
            'status' => 200,
            'battery_id' => (int) $row['id'],
            'is_orange_tick' => (int) $row['is_in_tally'] === 0,
            'serial' => $serial,
        ];
    }
}
