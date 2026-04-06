SET @last_used_at_exists := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'auth_refresh_tokens'
    AND COLUMN_NAME = 'last_used_at'
);

SET @last_used_at_sql := IF(
  @last_used_at_exists = 0,
  'ALTER TABLE auth_refresh_tokens ADD COLUMN last_used_at TIMESTAMP NULL AFTER revoked_at',
  'SELECT 1'
);

PREPARE last_used_at_stmt FROM @last_used_at_sql;
EXECUTE last_used_at_stmt;
DEALLOCATE PREPARE last_used_at_stmt;

CREATE TABLE IF NOT EXISTS delivery_incentives (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  driver_id INT UNSIGNED NOT NULL,
  task_id BIGINT UNSIGNED NOT NULL,
  claim_id BIGINT UNSIGNED NOT NULL,
  handshake_id BIGINT UNSIGNED NOT NULL,
  task_type ENUM('DELIVERY_NEW','DELIVERY_REPLACEMENT') NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  delivery_date DATE NOT NULL,
  is_paid TINYINT(1) NOT NULL DEFAULT 0,
  paid_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_task_incentive (task_id),
  INDEX idx_driver_month (driver_id, delivery_date),
  INDEX idx_tenant_driver_paid (tenant_id, driver_id, is_paid),
  CONSTRAINT fk_incentive_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_incentive_driver FOREIGN KEY (driver_id) REFERENCES users(id),
  CONSTRAINT fk_incentive_task FOREIGN KEY (task_id) REFERENCES driver_tasks(id),
  CONSTRAINT fk_incentive_claim FOREIGN KEY (claim_id) REFERENCES claims(id),
  CONSTRAINT fk_incentive_handshake FOREIGN KEY (handshake_id) REFERENCES driver_handshakes(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
