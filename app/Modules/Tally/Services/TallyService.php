<?php

declare(strict_types=1);

namespace App\Modules\Tally\Services;

use App\Modules\Audit\Services\AuditService;
use App\Shared\Database\Connection;
use PDO;

final class TallyService
{
    private PDO $db;
    private AuditService $auditService;

    public function __construct()
    {
        $this->db = Connection::get();
        $this->auditService = new AuditService();
    }

    public function importRows(int $tenantId, int $userId, string $filename, array $rows): array
    {
        $inserted = 0;
        $upserted = 0;
        $skipped = 0;

        foreach ($rows as $row) {
            $serial = strtoupper(trim((string) ($row['serial'] ?? '')));
            if (!preg_match('/^[A-Z0-9]{14,15}$/', $serial)) {
                $skipped++;
                continue;
            }

            $stmt = $this->db->prepare('SELECT id, status FROM batteries WHERE tenant_id = :tenant_id AND serial_number = :serial LIMIT 1');
            $stmt->execute(['tenant_id' => $tenantId, 'serial' => $serial]);
            $battery = $stmt->fetch();

            if (!$battery) {
                $insert = $this->db->prepare(
                    "INSERT INTO batteries (tenant_id, serial_number, is_in_tally, status)
                     VALUES (:tenant_id, :serial_number, 1, 'IN_STOCK')"
                );
                $insert->execute(['tenant_id' => $tenantId, 'serial_number' => $serial]);
                $inserted++;
                continue;
            }

            if (in_array($battery['status'], ['CLAIMED', 'AT_SERVICE'], true)) {
                $skipped++;
                continue;
            }

            $update = $this->db->prepare('UPDATE batteries SET is_in_tally = 1 WHERE id = :id');
            $update->execute(['id' => $battery['id']]);
            $upserted++;
        }

        $import = $this->db->prepare(
            'INSERT INTO tally_imports (tenant_id, filename, imported_by, total_rows, inserted_rows, upserted_rows, skipped_rows)
             VALUES (:tenant_id, :filename, :imported_by, :total_rows, :inserted_rows, :upserted_rows, :skipped_rows)'
        );
        $import->execute([
            'tenant_id' => $tenantId,
            'filename' => $filename,
            'imported_by' => $userId,
            'total_rows' => count($rows),
            'inserted_rows' => $inserted,
            'upserted_rows' => $upserted,
            'skipped_rows' => $skipped,
        ]);

        $this->auditService->log($tenantId, $userId, 'tally.import', 'tally_imports', (int) $this->db->lastInsertId(), [], [
            'filename' => $filename,
            'rows' => count($rows),
            'inserted' => $inserted,
            'upserted' => $upserted,
            'skipped' => $skipped,
        ], 'MEDIUM');

        return [
            'inserted_rows' => $inserted,
            'upserted_rows' => $upserted,
            'skipped_rows' => $skipped,
            'total_rows' => count($rows),
        ];
    }

    public function exportBatteries(int $tenantId, int $userId): array
    {
        $stmt = $this->db->prepare('SELECT serial_number, status, is_in_tally FROM batteries WHERE tenant_id = :tenant_id ORDER BY serial_number ASC');
        $stmt->execute(['tenant_id' => $tenantId]);
        $rows = $stmt->fetchAll() ?: [];

        $lines = ['serial_number;status;is_in_tally'];
        foreach ($rows as $row) {
            $serial = $this->safeCsv((string) $row['serial_number']);
            $status = $this->safeCsv((string) $row['status']);
            $inTally = $this->safeCsv((string) $row['is_in_tally']);
            $lines[] = implode(';', [$serial, $status, $inTally]);
        }

        $export = $this->db->prepare(
            'INSERT INTO tally_exports (tenant_id, exported_by, export_type, row_count)
             VALUES (:tenant_id, :exported_by, :export_type, :row_count)'
        );
        $export->execute([
            'tenant_id' => $tenantId,
            'exported_by' => $userId,
            'export_type' => 'BATTERIES',
            'row_count' => count($rows),
        ]);

        $this->auditService->log($tenantId, $userId, 'tally.export', 'tally_exports', (int) $this->db->lastInsertId(), [], [
            'row_count' => count($rows),
        ], 'LOW');

        return [
            'row_count' => count($rows),
            'csv' => implode("\n", $lines),
        ];
    }

    private function safeCsv(string $value): string
    {
        if ($value !== '' && in_array($value[0], ['=', '+', '-', '@'], true)) {
            return "\t" . $value;
        }

        return $value;
    }
}
