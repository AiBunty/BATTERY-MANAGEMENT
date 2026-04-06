<?php

declare(strict_types=1);

namespace App\Modules\ServiceCenter\Services;

use App\Modules\Audit\Services\AuditService;
use App\Shared\Database\Connection;
use PDO;

final class ServiceJobService
{
    private PDO $db;
    private AuditService $auditService;

    public function __construct()
    {
        $this->db = Connection::get();
        $this->auditService = new AuditService();
    }

    public function inward(int $tenantId, int $claimId, int $inwardBy): array
    {
        $stmt = $this->db->prepare(
            'INSERT INTO service_jobs (tenant_id, claim_id, inward_by, diagnosis) VALUES (:tenant_id, :claim_id, :inward_by, :diagnosis)'
        );
        $stmt->execute([
            'tenant_id' => $tenantId,
            'claim_id' => $claimId,
            'inward_by' => $inwardBy,
            'diagnosis' => 'PENDING',
        ]);

        $jobId = (int) $this->db->lastInsertId();

        $updateClaim = $this->db->prepare("UPDATE claims SET status = 'AT_SERVICE' WHERE id = :claim_id");
        $updateClaim->execute(['claim_id' => $claimId]);

        $history = $this->db->prepare(
            'INSERT INTO claim_status_history (claim_id, from_status, to_status, changed_by) VALUES (:claim_id, :from_status, :to_status, :changed_by)'
        );
        $history->execute([
            'claim_id' => $claimId,
            'from_status' => 'DRIVER_RECEIVED',
            'to_status' => 'AT_SERVICE',
            'changed_by' => $inwardBy,
        ]);

        $this->auditService->log($tenantId, $inwardBy, 'service.inward', 'service_jobs', $jobId, [], [
            'claim_id' => $claimId,
        ], 'LOW');

        return ['ok' => true, 'status' => 201, 'service_job_id' => $jobId];
    }

    public function diagnose(int $tenantId, int $serviceJobId, string $diagnosis, ?string $notes): array
    {
        $jobStmt = $this->db->prepare('SELECT id, claim_id, inward_by FROM service_jobs WHERE tenant_id = :tenant_id AND id = :id LIMIT 1');
        $jobStmt->execute([
            'tenant_id' => $tenantId,
            'id' => $serviceJobId,
        ]);
        $job = $jobStmt->fetch();

        if (!$job) {
            return ['ok' => false, 'status' => 404, 'code' => 'SERVICE_JOB_NOT_FOUND', 'message' => 'Service job not found'];
        }

        $claimStatus = $diagnosis === 'OK' ? 'READY_FOR_RETURN' : 'DIAGNOSED';

        $this->db->beginTransaction();
        try {
            $updateJob = $this->db->prepare(
                'UPDATE service_jobs SET diagnosis = :diagnosis, diagnosis_notes = :diagnosis_notes, diagnosed_at = NOW() WHERE id = :id'
            );
            $updateJob->execute([
                'diagnosis' => $diagnosis,
                'diagnosis_notes' => $notes,
                'id' => $serviceJobId,
            ]);

            $updateClaim = $this->db->prepare('UPDATE claims SET status = :status WHERE id = :claim_id');
            $updateClaim->execute([
                'status' => $claimStatus,
                'claim_id' => $job['claim_id'],
            ]);

            $history = $this->db->prepare(
                'INSERT INTO claim_status_history (claim_id, from_status, to_status, changed_by) VALUES (:claim_id, :from_status, :to_status, :changed_by)'
            );
            $history->execute([
                'claim_id' => $job['claim_id'],
                'from_status' => 'AT_SERVICE',
                'to_status' => $claimStatus,
                'changed_by' => $job['inward_by'],
            ]);

            $this->auditService->log($tenantId, (int) $job['inward_by'], 'service.diagnosed', 'service_jobs', $serviceJobId, [], [
                'diagnosis' => $diagnosis,
                'claim_status' => $claimStatus,
            ], 'MEDIUM');

            $this->db->commit();

            return ['ok' => true, 'status' => 200, 'claim_status' => $claimStatus];
        } catch (\Throwable $e) {
            if ($this->db->inTransaction()) {
                $this->db->rollBack();
            }
            return ['ok' => false, 'status' => 500, 'code' => 'DIAGNOSIS_FAILED', 'message' => 'Diagnosis update failed'];
        }
    }
}
