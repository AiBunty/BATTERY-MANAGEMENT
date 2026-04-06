<?php

declare(strict_types=1);

namespace App\Modules\Claims\Services;

use App\Modules\Audit\Services\AuditService;
use App\Modules\Tracking\Services\TrackingService;
use App\Shared\Database\Connection;
use PDO;

final class ClaimService
{
    private PDO $db;
    private AuditService $auditService;
    private TrackingService $trackingService;

    public function __construct()
    {
        $this->db = Connection::get();
        $this->auditService = new AuditService();
        $this->trackingService = new TrackingService();
    }

    public function createClaim(int $tenantId, int $dealerId, int $batteryId, bool $isOrangeTick, ?string $complaint): array
    {
        $quota = $this->checkPlanQuota($tenantId);
        if (!$quota['ok']) {
            return $quota;
        }

        $this->db->beginTransaction();

        try {
            $claimNumber = $this->generateClaimNumber($tenantId);

            $stmt = $this->db->prepare(
                "INSERT INTO claims (
                    tenant_id,
                    claim_number,
                    battery_id,
                    dealer_id,
                    is_orange_tick,
                    complaint,
                    status
                ) VALUES (
                    :tenant_id,
                    :claim_number,
                    :battery_id,
                    :dealer_id,
                    :is_orange_tick,
                    :complaint,
                    'DRAFT'
                )"
            );

            $stmt->execute([
                'tenant_id' => $tenantId,
                'claim_number' => $claimNumber,
                'battery_id' => $batteryId,
                'dealer_id' => $dealerId,
                'is_orange_tick' => $isOrangeTick ? 1 : 0,
                'complaint' => $complaint,
            ]);

            $claimId = (int) $this->db->lastInsertId();

            $history = $this->db->prepare(
                'INSERT INTO claim_status_history (claim_id, from_status, to_status, changed_by) VALUES (:claim_id, :from_status, :to_status, :changed_by)'
            );
            $history->execute([
                'claim_id' => $claimId,
                'from_status' => 'DRAFT',
                'to_status' => 'DRAFT',
                'changed_by' => $dealerId,
            ]);

            $this->auditService->log($tenantId, $dealerId, 'claim.created', 'claims', $claimId, [], [
                'claim_number' => $claimNumber,
                'battery_id' => $batteryId,
                'is_orange_tick' => $isOrangeTick,
            ], 'LOW');

            $trackingUrl = $this->trackingService->getOrCreateTokenUrl($tenantId, $claimId);

            $this->db->commit();

            return [
                'ok' => true,
                'status' => 201,
                'claim_id' => $claimId,
                'claim_number' => $claimNumber,
                'tracking_url' => $trackingUrl,
            ];
        } catch (\Throwable $e) {
            if ($this->db->inTransaction()) {
                $this->db->rollBack();
            }

            return [
                'ok' => false,
                'status' => 500,
                'code' => 'CLAIM_CREATE_FAILED',
                'message' => 'Failed to create claim',
            ];
        }
    }

    private function checkPlanQuota(int $tenantId): array
    {
        $stmt = $this->db->prepare(
            "SELECT p.max_monthly_claims AS max_claims,
                    (SELECT COUNT(*) FROM claims c
                     WHERE c.tenant_id = t.id
                       AND DATE_FORMAT(c.created_at, '%Y-%m') = DATE_FORMAT(NOW(), '%Y-%m')) AS claim_count
             FROM tenants t
             JOIN plans p ON p.id = t.plan_id
             WHERE t.id = :tenant_id
             LIMIT 1"
        );
        $stmt->execute(['tenant_id' => $tenantId]);
        $row = $stmt->fetch();

        if (!$row) {
            return ['ok' => false, 'status' => 404, 'code' => 'TENANT_NOT_FOUND', 'message' => 'Tenant not found'];
        }

        if ((int) $row['claim_count'] >= (int) $row['max_claims']) {
            return ['ok' => false, 'status' => 429, 'code' => 'PLAN_QUOTA_EXCEEDED', 'message' => 'Monthly claim quota exceeded'];
        }

        return ['ok' => true];
    }

    public function listByDealer(int $tenantId, int $dealerId, ?string $status, int $limit): array
    {
        $sql = 'SELECT c.id, c.claim_number, c.status, c.is_orange_tick, c.created_at,
                       b.serial_number
                FROM claims c
                JOIN batteries b ON b.id = c.battery_id
                WHERE c.tenant_id = :tenant_id AND c.dealer_id = :dealer_id';
        $params = ['tenant_id' => $tenantId, 'dealer_id' => $dealerId];

        if ($status !== null) {
            $sql .= ' AND c.status = :status';
            $params['status'] = $status;
        }

        $sql .= ' ORDER BY c.created_at DESC LIMIT ' . $limit;
        $stmt = $this->db->prepare($sql);
        $stmt->execute($params);

        return $stmt->fetchAll(\PDO::FETCH_ASSOC) ?: [];
    }

    private function generateClaimNumber(int $tenantId): string
    {
        $year = (string) date('Y');
        $seqName = 'CLM-' . $year;

        $tenantStmt = $this->db->prepare('SELECT slug FROM tenants WHERE id = :id LIMIT 1');
        $tenantStmt->execute(['id' => $tenantId]);
        $tenant = $tenantStmt->fetch();
        $slug = strtoupper((string) ($tenant['slug'] ?? 'TENANT'));

        $seqStmt = $this->db->prepare(
            'SELECT current_val FROM tenant_sequences WHERE tenant_id = :tenant_id AND seq_name = :seq_name FOR UPDATE'
        );
        $seqStmt->execute([
            'tenant_id' => $tenantId,
            'seq_name' => $seqName,
        ]);

        $row = $seqStmt->fetch();
        if (!$row) {
            $next = 1;
            $insert = $this->db->prepare(
                "INSERT INTO tenant_sequences (tenant_id, seq_name, current_val, reset_cycle)
                 VALUES (:tenant_id, :seq_name, :current_val, 'yearly')"
            );
            $insert->execute([
                'tenant_id' => $tenantId,
                'seq_name' => $seqName,
                'current_val' => $next,
            ]);
        } else {
            $next = (int) $row['current_val'] + 1;
            $update = $this->db->prepare(
                'UPDATE tenant_sequences SET current_val = :current_val WHERE tenant_id = :tenant_id AND seq_name = :seq_name'
            );
            $update->execute([
                'current_val' => $next,
                'tenant_id' => $tenantId,
                'seq_name' => $seqName,
            ]);
        }

        return sprintf('%s-CLM-%s-%05d', $slug, $year, $next);
    }
}
