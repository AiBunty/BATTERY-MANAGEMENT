<?php

declare(strict_types=1);

namespace App\Modules\Audit\Services;

use App\Shared\Database\Connection;
use PDO;

final class AuditService
{
    private PDO $db;

    public function __construct()
    {
        $this->db = Connection::get();
    }

    public function log(
        int $tenantId,
        ?int $userId,
        string $action,
        string $entityType,
        ?int $entityId,
        array $oldValues = [],
        array $newValues = [],
        string $severity = 'LOW',
        string $ipAddress = '0.0.0.0'
    ): void {
        $stmt = $this->db->prepare(
            'INSERT INTO audit_logs (tenant_id, user_id, action, entity_type, entity_id, old_values, new_values, severity, ip_address)
             VALUES (:tenant_id, :user_id, :action, :entity_type, :entity_id, :old_values, :new_values, :severity, :ip_address)'
        );
        $stmt->bindValue(':tenant_id', $tenantId, PDO::PARAM_INT);
        $stmt->bindValue(':user_id', $userId, $userId === null ? PDO::PARAM_NULL : PDO::PARAM_INT);
        $stmt->bindValue(':action', $action);
        $stmt->bindValue(':entity_type', $entityType);
        $stmt->bindValue(':entity_id', $entityId, $entityId === null ? PDO::PARAM_NULL : PDO::PARAM_INT);
        $stmt->bindValue(':old_values', $oldValues ? json_encode($oldValues, JSON_UNESCAPED_SLASHES) : null, $oldValues ? PDO::PARAM_STR : PDO::PARAM_NULL);
        $stmt->bindValue(':new_values', $newValues ? json_encode($newValues, JSON_UNESCAPED_SLASHES) : null, $newValues ? PDO::PARAM_STR : PDO::PARAM_NULL);
        $stmt->bindValue(':severity', $severity);
        $stmt->bindValue(':ip_address', $ipAddress);
        $stmt->execute();
    }
}
