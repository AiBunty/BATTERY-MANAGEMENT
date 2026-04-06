CREATE TABLE IF NOT EXISTS driver_routes (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  driver_id INT UNSIGNED NOT NULL,
  route_date DATE NOT NULL,
  status ENUM('PLANNED','ACTIVE','COMPLETED') NOT NULL DEFAULT 'PLANNED',
  created_by INT UNSIGNED NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tenant_driver_date (tenant_id, driver_id, route_date),
  INDEX idx_tenant_date (tenant_id, route_date),
  CONSTRAINT fk_routes_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_routes_driver FOREIGN KEY (driver_id) REFERENCES users(id),
  CONSTRAINT fk_routes_creator FOREIGN KEY (created_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS driver_tasks (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  route_id BIGINT UNSIGNED NOT NULL,
  claim_id BIGINT UNSIGNED NOT NULL,
  task_type ENUM('DELIVERY_NEW','DELIVERY_REPLACEMENT','PICKUP_SERVICE','PICKUP_RETURN') NOT NULL,
  status ENUM('PENDING','ACTIVE','DONE','SKIPPED') NOT NULL DEFAULT 'PENDING',
  completed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_route_status (route_id, status),
  CONSTRAINT fk_tasks_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_tasks_route FOREIGN KEY (route_id) REFERENCES driver_routes(id) ON DELETE CASCADE,
  CONSTRAINT fk_tasks_claim FOREIGN KEY (claim_id) REFERENCES claims(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS driver_handshakes (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  route_id BIGINT UNSIGNED NOT NULL,
  driver_id INT UNSIGNED NOT NULL,
  dealer_id INT UNSIGNED NOT NULL,
  batch_photo VARCHAR(255) NOT NULL,
  dealer_signature VARCHAR(255) NOT NULL,
  sig_hash CHAR(64) NOT NULL,
  handshake_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_sig_hash (sig_hash),
  INDEX idx_tenant_driver (tenant_id, driver_id, handshake_at),
  CONSTRAINT fk_handshake_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_handshake_route FOREIGN KEY (route_id) REFERENCES driver_routes(id),
  CONSTRAINT fk_handshake_driver FOREIGN KEY (driver_id) REFERENCES users(id),
  CONSTRAINT fk_handshake_dealer FOREIGN KEY (dealer_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS handshake_tasks (
  handshake_id BIGINT UNSIGNED NOT NULL,
  task_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (handshake_id, task_id),
  UNIQUE KEY uq_task_once (task_id),
  CONSTRAINT fk_handshake_tasks_handshake FOREIGN KEY (handshake_id) REFERENCES driver_handshakes(id) ON DELETE CASCADE,
  CONSTRAINT fk_handshake_tasks_task FOREIGN KEY (task_id) REFERENCES driver_tasks(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS service_jobs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  claim_id BIGINT UNSIGNED NOT NULL,
  inward_by INT UNSIGNED NOT NULL,
  diagnosis ENUM('PENDING','OK','REPLACE') NOT NULL DEFAULT 'PENDING',
  diagnosis_notes TEXT NULL,
  inward_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  diagnosed_at TIMESTAMP NULL,
  INDEX idx_tenant_diagnosis (tenant_id, diagnosis),
  CONSTRAINT fk_service_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_service_claim FOREIGN KEY (claim_id) REFERENCES claims(id),
  CONSTRAINT fk_service_user FOREIGN KEY (inward_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
