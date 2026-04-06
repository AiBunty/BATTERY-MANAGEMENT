CREATE TABLE IF NOT EXISTS batteries (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  serial_number VARCHAR(15) NOT NULL,
  is_in_tally TINYINT(1) NOT NULL DEFAULT 0,
  status ENUM('IN_STOCK','CLAIMED','IN_TRANSIT','AT_SERVICE','REPLACED','SCRAPPED') NOT NULL DEFAULT 'IN_STOCK',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tenant_serial (tenant_id, serial_number),
  INDEX idx_tenant_status (tenant_id, status),
  CONSTRAINT fk_battery_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS tenant_sequences (
  tenant_id BIGINT UNSIGNED NOT NULL,
  seq_name VARCHAR(100) NOT NULL,
  current_val BIGINT UNSIGNED NOT NULL DEFAULT 0,
  reset_cycle ENUM('none','yearly') NOT NULL DEFAULT 'yearly',
  PRIMARY KEY (tenant_id, seq_name),
  CONSTRAINT fk_seq_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS claims (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  claim_number VARCHAR(30) NOT NULL,
  battery_id BIGINT UNSIGNED NOT NULL,
  dealer_id INT UNSIGNED NOT NULL,
  is_orange_tick TINYINT(1) NOT NULL DEFAULT 0,
  complaint TEXT NULL,
  status ENUM('DRAFT','SUBMITTED','DRIVER_RECEIVED','IN_TRANSIT','AT_SERVICE','DIAGNOSED','REPLACED','READY_FOR_RETURN','CLOSED') NOT NULL DEFAULT 'DRAFT',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tenant_claim_no (tenant_id, claim_number),
  INDEX idx_tenant_status (tenant_id, status),
  INDEX idx_tenant_dealer (tenant_id, dealer_id),
  CONSTRAINT fk_claim_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_claim_battery FOREIGN KEY (battery_id) REFERENCES batteries(id),
  CONSTRAINT fk_claim_dealer FOREIGN KEY (dealer_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS claim_status_history (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  claim_id BIGINT UNSIGNED NOT NULL,
  from_status VARCHAR(30) NOT NULL,
  to_status VARCHAR(30) NOT NULL,
  changed_by INT UNSIGNED NOT NULL,
  changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_claim_changed (claim_id, changed_at),
  CONSTRAINT fk_history_claim FOREIGN KEY (claim_id) REFERENCES claims(id),
  CONSTRAINT fk_history_user FOREIGN KEY (changed_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
