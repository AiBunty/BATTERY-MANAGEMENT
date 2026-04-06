<?php

declare(strict_types=1);

namespace App\Modules\Reports\Services;

use App\Shared\Database\Connection;
use PDO;

final class ReportService
{
    private PDO $db;

    public function __construct()
    {
        $this->db = Connection::get();
    }

    public function lemonReport(int $tenantId): array
    {
        $stmt = $this->db->prepare(
            'SELECT b.serial_number, COUNT(c.id) AS claim_count
             FROM batteries b
             JOIN claims c ON c.battery_id = b.id
             WHERE b.tenant_id = :tenant_id
             GROUP BY b.id, b.serial_number
             HAVING COUNT(c.id) >= 2
             ORDER BY claim_count DESC, b.serial_number ASC'
        );
        $stmt->execute(['tenant_id' => $tenantId]);
        return $stmt->fetchAll() ?: [];
    }

    public function financeReport(int $tenantId, ?string $month = null): array
    {
        $month = $month ?: date('Y-m');
        $stmt = $this->db->prepare(
            "SELECT di.driver_id, u.email AS driver_email, COUNT(di.id) AS deliveries, SUM(di.amount) AS total_amount
             FROM delivery_incentives di
             JOIN users u ON u.id = di.driver_id
             WHERE di.tenant_id = :tenant_id
               AND DATE_FORMAT(di.delivery_date, '%Y-%m') = :report_month
             GROUP BY di.driver_id, u.email
             ORDER BY total_amount DESC, driver_email ASC"
        );
        $stmt->execute([
            'tenant_id' => $tenantId,
            'report_month' => $month,
        ]);
        return $stmt->fetchAll() ?: [];
    }

    public function auditSummary(int $tenantId): array
    {
        $stmt = $this->db->prepare(
            'SELECT severity, COUNT(*) AS total
             FROM audit_logs
             WHERE tenant_id = :tenant_id
             GROUP BY severity
             ORDER BY FIELD(severity, "CRITICAL", "HIGH", "MEDIUM", "LOW")'
        );
        $stmt->execute(['tenant_id' => $tenantId]);
        return $stmt->fetchAll() ?: [];
    }
}
