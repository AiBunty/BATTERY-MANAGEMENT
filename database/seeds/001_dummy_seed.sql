-- ============================================================
-- BATTERY MANAGEMENT — DUMMY SEED DATA  v1.0
-- 313+ records covering every module
--
-- Prerequisites : All migrations 001–007 must be run first.
-- Assumption    : tenant_id=1 (slug='default') from migration 001.
-- Idempotent    : uses INSERT IGNORE — safe to re-run.
-- Context date  : 2026-04-04
-- ============================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ─── 1. USERS (10) ──────────────────────────────────────────
-- Roles : 1 ADMIN · 4 DEALER · 2 DRIVER · 1 TESTER(service)
--         1 DISPATCH_MANAGER · 1 SUPER_MANAGER(CRM)
INSERT IGNORE INTO users (id, tenant_id, name, email, legacy_role, is_active) VALUES
(1,  1, 'System Admin',      'admin@demo.com',    'ADMIN',            1),
(2,  1, 'Raj Motors',        'dealer1@demo.com',  'DEALER',           1),
(3,  1, 'Priya Auto Works',  'dealer2@demo.com',  'DEALER',           1),
(4,  1, 'Speed Batteries',   'dealer3@demo.com',  'DEALER',           1),
(5,  1, 'City Power House',  'dealer4@demo.com',  'DEALER',           1),
(6,  1, 'Arjun Kumar',       'driver1@demo.com',  'DRIVER',           1),
(7,  1, 'Suresh Nair',       'driver2@demo.com',  'DRIVER',           1),
(8,  1, 'Anand Technician',  'service@demo.com',  'TESTER',           1),
(9,  1, 'Dispatch Manager',  'dispatch@demo.com', 'DISPATCH_MANAGER', 1),
(10, 1, 'CRM Manager',       'crm@demo.com',      'SUPER_MANAGER',    1);

-- ─── 2. TENANT SETTINGS (5) ─────────────────────────────────
INSERT IGNORE INTO tenant_settings (tenant_id, setting_key, setting_value) VALUES
(1, 'company_name',                   'Demo Battery Co.'),
(1, 'support_email',                  'support@demo.com'),
(1, 'default_currency',               'INR'),
(1, 'incentive_delivery_new',         '150.00'),
(1, 'incentive_delivery_replacement', '200.00');

-- ─── 3. BATTERIES (100) ─────────────────────────────────────
-- Status map:
--   IN_STOCK   : 1–5 (fresh), 46–100 (warehouse)
--   CLAIMED    : 6–20  → backs claims 1–15
--   IN_TRANSIT : 21–25 → backs claims 16–20
--   AT_SERVICE : 26–35 → backs claims 21–30
--   REPLACED   : 36–42 → backs claims 31–37
--   SCRAPPED   : 43–45 → backs claims 38–40
INSERT IGNORE INTO batteries (id, tenant_id, serial_number, is_in_tally, status, created_at) VALUES
-- IN_STOCK (fresh)
(1,  1,'BAT-2025-00001',1,'IN_STOCK',  '2025-10-01 08:00:00'),
(2,  1,'BAT-2025-00002',1,'IN_STOCK',  '2025-10-01 08:00:00'),
(3,  1,'BAT-2025-00003',1,'IN_STOCK',  '2025-10-01 08:00:00'),
(4,  1,'BAT-2025-00004',1,'IN_STOCK',  '2025-10-01 08:00:00'),
(5,  1,'BAT-2025-00005',1,'IN_STOCK',  '2025-10-01 08:00:00'),
-- CLAIMED
(6,  1,'BAT-2025-00006',1,'CLAIMED',   '2025-10-01 08:00:00'),
(7,  1,'BAT-2025-00007',1,'CLAIMED',   '2025-10-02 08:00:00'),
(8,  1,'BAT-2025-00008',1,'CLAIMED',   '2025-10-03 08:00:00'),
(9,  1,'BAT-2025-00009',1,'CLAIMED',   '2025-10-04 08:00:00'),
(10, 1,'BAT-2025-00010',1,'CLAIMED',   '2025-10-05 08:00:00'),
(11, 1,'BAT-2025-00011',1,'CLAIMED',   '2025-10-06 08:00:00'),
(12, 1,'BAT-2025-00012',1,'CLAIMED',   '2025-10-07 08:00:00'),
(13, 1,'BAT-2025-00013',1,'CLAIMED',   '2025-10-08 08:00:00'),
(14, 1,'BAT-2025-00014',1,'CLAIMED',   '2025-10-09 08:00:00'),
(15, 1,'BAT-2025-00015',1,'CLAIMED',   '2025-10-10 08:00:00'),
(16, 1,'BAT-2025-00016',1,'CLAIMED',   '2025-10-11 08:00:00'),
(17, 1,'BAT-2025-00017',1,'CLAIMED',   '2025-10-12 08:00:00'),
(18, 1,'BAT-2025-00018',1,'CLAIMED',   '2025-10-13 08:00:00'),
(19, 1,'BAT-2025-00019',1,'CLAIMED',   '2025-10-14 08:00:00'),
(20, 1,'BAT-2025-00020',1,'CLAIMED',   '2025-10-15 08:00:00'),
-- IN_TRANSIT
(21, 1,'BAT-2025-00021',1,'IN_TRANSIT','2025-10-16 08:00:00'),
(22, 1,'BAT-2025-00022',1,'IN_TRANSIT','2025-10-17 08:00:00'),
(23, 1,'BAT-2025-00023',1,'IN_TRANSIT','2025-10-18 08:00:00'),
(24, 1,'BAT-2025-00024',1,'IN_TRANSIT','2025-10-19 08:00:00'),
(25, 1,'BAT-2025-00025',1,'IN_TRANSIT','2025-10-20 08:00:00'),
-- AT_SERVICE
(26, 1,'BAT-2025-00026',1,'AT_SERVICE','2025-11-01 08:00:00'),
(27, 1,'BAT-2025-00027',1,'AT_SERVICE','2025-11-02 08:00:00'),
(28, 1,'BAT-2025-00028',1,'AT_SERVICE','2025-11-03 08:00:00'),
(29, 1,'BAT-2025-00029',1,'AT_SERVICE','2025-11-04 08:00:00'),
(30, 1,'BAT-2025-00030',1,'AT_SERVICE','2025-11-05 08:00:00'),
(31, 1,'BAT-2025-00031',1,'AT_SERVICE','2025-11-06 08:00:00'),
(32, 1,'BAT-2025-00032',1,'AT_SERVICE','2025-11-07 08:00:00'),
(33, 1,'BAT-2025-00033',1,'AT_SERVICE','2025-11-08 08:00:00'),
(34, 1,'BAT-2025-00034',1,'AT_SERVICE','2025-11-09 08:00:00'),
(35, 1,'BAT-2025-00035',1,'AT_SERVICE','2025-11-10 08:00:00'),
-- REPLACED
(36, 1,'BAT-2025-00036',1,'REPLACED',  '2025-11-11 08:00:00'),
(37, 1,'BAT-2025-00037',1,'REPLACED',  '2025-11-12 08:00:00'),
(38, 1,'BAT-2025-00038',1,'REPLACED',  '2025-11-13 08:00:00'),
(39, 1,'BAT-2025-00039',1,'REPLACED',  '2025-11-14 08:00:00'),
(40, 1,'BAT-2025-00040',1,'REPLACED',  '2025-11-15 08:00:00'),
(41, 1,'BAT-2025-00041',1,'REPLACED',  '2025-11-16 08:00:00'),
(42, 1,'BAT-2025-00042',1,'REPLACED',  '2025-11-17 08:00:00'),
-- SCRAPPED
(43, 1,'BAT-2025-00043',1,'SCRAPPED',  '2025-12-01 08:00:00'),
(44, 1,'BAT-2025-00044',1,'SCRAPPED',  '2025-12-02 08:00:00'),
(45, 1,'BAT-2025-00045',1,'SCRAPPED',  '2025-12-03 08:00:00'),
-- IN_STOCK warehouse (tally imported): 46–75
(46, 1,'BAT-2025-00046',1,'IN_STOCK',  '2025-12-10 08:00:00'),
(47, 1,'BAT-2025-00047',1,'IN_STOCK',  '2025-12-10 08:00:00'),
(48, 1,'BAT-2025-00048',1,'IN_STOCK',  '2025-12-10 08:00:00'),
(49, 1,'BAT-2025-00049',1,'IN_STOCK',  '2025-12-10 08:00:00'),
(50, 1,'BAT-2025-00050',1,'IN_STOCK',  '2025-12-10 08:00:00'),
(51, 1,'BAT-2025-00051',1,'IN_STOCK',  '2025-12-10 08:00:00'),
(52, 1,'BAT-2025-00052',1,'IN_STOCK',  '2025-12-10 08:00:00'),
(53, 1,'BAT-2025-00053',1,'IN_STOCK',  '2025-12-11 08:00:00'),
(54, 1,'BAT-2025-00054',1,'IN_STOCK',  '2025-12-11 08:00:00'),
(55, 1,'BAT-2025-00055',1,'IN_STOCK',  '2025-12-11 08:00:00'),
(56, 1,'BAT-2025-00056',1,'IN_STOCK',  '2025-12-11 08:00:00'),
(57, 1,'BAT-2025-00057',1,'IN_STOCK',  '2025-12-11 08:00:00'),
(58, 1,'BAT-2025-00058',1,'IN_STOCK',  '2025-12-12 08:00:00'),
(59, 1,'BAT-2025-00059',1,'IN_STOCK',  '2025-12-12 08:00:00'),
(60, 1,'BAT-2025-00060',1,'IN_STOCK',  '2025-12-12 08:00:00'),
(61, 1,'BAT-2025-00061',1,'IN_STOCK',  '2025-12-12 08:00:00'),
(62, 1,'BAT-2025-00062',1,'IN_STOCK',  '2025-12-12 08:00:00'),
(63, 1,'BAT-2025-00063',1,'IN_STOCK',  '2025-12-13 08:00:00'),
(64, 1,'BAT-2025-00064',1,'IN_STOCK',  '2025-12-13 08:00:00'),
(65, 1,'BAT-2025-00065',1,'IN_STOCK',  '2025-12-13 08:00:00'),
(66, 1,'BAT-2025-00066',1,'IN_STOCK',  '2025-12-13 08:00:00'),
(67, 1,'BAT-2025-00067',1,'IN_STOCK',  '2025-12-14 08:00:00'),
(68, 1,'BAT-2025-00068',1,'IN_STOCK',  '2025-12-14 08:00:00'),
(69, 1,'BAT-2025-00069',1,'IN_STOCK',  '2025-12-14 08:00:00'),
(70, 1,'BAT-2025-00070',1,'IN_STOCK',  '2025-12-14 08:00:00'),
(71, 1,'BAT-2025-00071',1,'IN_STOCK',  '2025-12-15 08:00:00'),
(72, 1,'BAT-2025-00072',1,'IN_STOCK',  '2025-12-15 08:00:00'),
(73, 1,'BAT-2025-00073',1,'IN_STOCK',  '2025-12-15 08:00:00'),
(74, 1,'BAT-2025-00074',1,'IN_STOCK',  '2025-12-15 08:00:00'),
(75, 1,'BAT-2025-00075',1,'IN_STOCK',  '2025-12-15 08:00:00'),
-- IN_STOCK new arrivals (NOT yet in tally): 76–100
(76, 1,'BAT-2026-00001',0,'IN_STOCK',  '2026-01-15 08:00:00'),
(77, 1,'BAT-2026-00002',0,'IN_STOCK',  '2026-01-15 08:00:00'),
(78, 1,'BAT-2026-00003',0,'IN_STOCK',  '2026-01-20 08:00:00'),
(79, 1,'BAT-2026-00004',0,'IN_STOCK',  '2026-01-20 08:00:00'),
(80, 1,'BAT-2026-00005',0,'IN_STOCK',  '2026-01-25 08:00:00'),
(81, 1,'BAT-2026-00006',0,'IN_STOCK',  '2026-02-01 08:00:00'),
(82, 1,'BAT-2026-00007',0,'IN_STOCK',  '2026-02-01 08:00:00'),
(83, 1,'BAT-2026-00008',0,'IN_STOCK',  '2026-02-05 08:00:00'),
(84, 1,'BAT-2026-00009',0,'IN_STOCK',  '2026-02-05 08:00:00'),
(85, 1,'BAT-2026-00010',0,'IN_STOCK',  '2026-02-10 08:00:00'),
(86, 1,'BAT-2026-00011',0,'IN_STOCK',  '2026-02-15 08:00:00'),
(87, 1,'BAT-2026-00012',0,'IN_STOCK',  '2026-02-15 08:00:00'),
(88, 1,'BAT-2026-00013',0,'IN_STOCK',  '2026-02-20 08:00:00'),
(89, 1,'BAT-2026-00014',0,'IN_STOCK',  '2026-02-20 08:00:00'),
(90, 1,'BAT-2026-00015',0,'IN_STOCK',  '2026-03-01 08:00:00'),
(91, 1,'BAT-2026-00016',0,'IN_STOCK',  '2026-03-05 08:00:00'),
(92, 1,'BAT-2026-00017',0,'IN_STOCK',  '2026-03-05 08:00:00'),
(93, 1,'BAT-2026-00018',0,'IN_STOCK',  '2026-03-10 08:00:00'),
(94, 1,'BAT-2026-00019',0,'IN_STOCK',  '2026-03-10 08:00:00'),
(95, 1,'BAT-2026-00020',0,'IN_STOCK',  '2026-03-15 08:00:00'),
(96, 1,'BAT-2026-00021',0,'IN_STOCK',  '2026-03-20 08:00:00'),
(97, 1,'BAT-2026-00022',0,'IN_STOCK',  '2026-03-25 08:00:00'),
(98, 1,'BAT-2026-00023',0,'IN_STOCK',  '2026-04-01 08:00:00'),
(99, 1,'BAT-2026-00024',0,'IN_STOCK',  '2026-04-02 08:00:00'),
(100,1,'BAT-2026-00025',0,'IN_STOCK',  '2026-04-04 08:00:00');

-- ─── 4. TENANT SEQUENCES ────────────────────────────────────
INSERT IGNORE INTO tenant_sequences (tenant_id, seq_name, current_val, reset_cycle)
VALUES (1, 'claim_2026', 40, 'yearly');

-- ─── 5. CLAIMS (40) ─────────────────────────────────────────
-- DRAFT(5) · SUBMITTED(5) · DRIVER_RECEIVED(5) · IN_TRANSIT(5)
-- AT_SERVICE(5) · DIAGNOSED(5) · REPLACED(4) · READY_FOR_RETURN(3) · CLOSED(3)
INSERT IGNORE INTO claims
  (id, tenant_id, claim_number, battery_id, dealer_id, is_orange_tick, complaint, status, created_at)
VALUES
-- DRAFT (1–5)  dealer=2  batteries 6–10
(1,  1,'CLM-2026-00001', 6, 2,0,'Battery not charging after 3 months of use',     'DRAFT',            '2026-04-03 10:00:00'),
(2,  1,'CLM-2026-00002', 7, 2,0,'Terminal corrosion observed',                     'DRAFT',            '2026-04-03 11:00:00'),
(3,  1,'CLM-2026-00003', 8, 2,1,'Capacity drop below 60% under load',              'DRAFT',            '2026-04-04 09:00:00'),
(4,  1,'CLM-2026-00004', 9, 2,0,'Physical damage on outer casing',                 'DRAFT',            '2026-04-04 10:00:00'),
(5,  1,'CLM-2026-00005',10, 2,0,'Does not hold charge overnight',                  'DRAFT',            '2026-04-04 11:00:00'),
-- SUBMITTED (6–10)  dealer=3  batteries 11–15
(6,  1,'CLM-2026-00006',11, 3,0,'Bulging detected on side panel',                  'SUBMITTED',        '2026-04-01 09:00:00'),
(7,  1,'CLM-2026-00007',12, 3,1,'Voltage fluctuations measured at terminals',      'SUBMITTED',        '2026-04-01 10:00:00'),
(8,  1,'CLM-2026-00008',13, 3,0,'No start after rain exposure',                    'SUBMITTED',        '2026-04-02 09:00:00'),
(9,  1,'CLM-2026-00009',14, 3,0,'Internal short suspected',                        'SUBMITTED',        '2026-04-02 10:00:00'),
(10, 1,'CLM-2026-00010',15, 3,0,'Warranty verification required',                  'SUBMITTED',        '2026-04-02 11:00:00'),
-- DRIVER_RECEIVED (11–15)  dealer=2  batteries 16–20
(11, 1,'CLM-2026-00011',16, 2,1,'Electrolyte leakage confirmed by dealer',         'DRIVER_RECEIVED',  '2026-03-30 09:00:00'),
(12, 1,'CLM-2026-00012',17, 2,0,'Battery dead on arrival at dealer',               'DRIVER_RECEIVED',  '2026-03-30 10:00:00'),
(13, 1,'CLM-2026-00013',18, 2,0,'Overheating under high discharge load',           'DRIVER_RECEIVED',  '2026-03-31 09:00:00'),
(14, 1,'CLM-2026-00014',19, 2,0,'Charging takes over 12 hours to complete',        'DRIVER_RECEIVED',  '2026-03-31 10:00:00'),
(15, 1,'CLM-2026-00015',20, 2,1,'Plate deterioration visible in cell inspection',  'DRIVER_RECEIVED',  '2026-04-01 08:00:00'),
-- IN_TRANSIT (16–20)  dealer=4  batteries 21–25
(16, 1,'CLM-2026-00016',21, 4,0,'Cell imbalance in 48V pack',                      'IN_TRANSIT',       '2026-03-28 09:00:00'),
(17, 1,'CLM-2026-00017',22, 4,1,'Acid smell from vents during charging',           'IN_TRANSIT',       '2026-03-28 10:00:00'),
(18, 1,'CLM-2026-00018',23, 4,0,'Swollen cells observed during discharge test',    'IN_TRANSIT',       '2026-03-29 09:00:00'),
(19, 1,'CLM-2026-00019',24, 4,0,'Manufacturer defect suspected',                   'IN_TRANSIT',       '2026-03-29 10:00:00'),
(20, 1,'CLM-2026-00020',25, 4,0,'Premature capacity degradation under warranty',   'IN_TRANSIT',       '2026-03-30 08:00:00'),
-- AT_SERVICE (21–25)  dealer=3  batteries 26–30
(21, 1,'CLM-2026-00021',26, 3,0,'Complete discharge within 1 hour of full charge', 'AT_SERVICE',       '2026-03-10 09:00:00'),
(22, 1,'CLM-2026-00022',27, 3,0,'Battery gets very hot during charging',           'AT_SERVICE',       '2026-03-11 09:00:00'),
(23, 1,'CLM-2026-00023',28, 3,1,'No output voltage detected on multimeter',        'AT_SERVICE',       '2026-03-12 09:00:00'),
(24, 1,'CLM-2026-00024',29, 3,0,'BMS fault code C04 displayed',                   'AT_SERVICE',       '2026-03-13 09:00:00'),
(25, 1,'CLM-2026-00025',30, 3,0,'Grid corrosion under 2-year warranty',            'AT_SERVICE',       '2026-03-14 09:00:00'),
-- DIAGNOSED (26–30)  dealer=5  batteries 31–35
(26, 1,'CLM-2026-00026',31, 5,1,'Confirmed cell reversal in cells 3 and 4',        'DIAGNOSED',        '2026-02-15 09:00:00'),
(27, 1,'CLM-2026-00027',32, 5,0,'Separator damage confirmed on teardown',          'DIAGNOSED',        '2026-02-16 09:00:00'),
(28, 1,'CLM-2026-00028',33, 5,0,'Active material shedding from positive plate',    'DIAGNOSED',        '2026-02-17 09:00:00'),
(29, 1,'CLM-2026-00029',34, 5,1,'Overcharge damage confirmed, plates warped',      'DIAGNOSED',        '2026-02-18 09:00:00'),
(30, 1,'CLM-2026-00030',35, 5,0,'Terminal weld failure confirmed',                 'DIAGNOSED',        '2026-02-19 09:00:00'),
-- REPLACED (31–34)  dealer=2  batteries 36–39
(31, 1,'CLM-2026-00031',36, 2,1,'Replacement received and installed by customer',  'REPLACED',         '2026-01-20 09:00:00'),
(32, 1,'CLM-2026-00032',37, 2,0,'New unit dispatched and fitted at dealer site',   'REPLACED',         '2026-01-21 09:00:00'),
(33, 1,'CLM-2026-00033',38, 2,1,'Orange-tick warranty replacement completed',      'REPLACED',         '2026-01-22 09:00:00'),
(34, 1,'CLM-2026-00034',39, 2,0,'Replacement completed, old unit returned',        'REPLACED',         '2026-01-23 09:00:00'),
-- READY_FOR_RETURN (35–37)  dealer=4  batteries 40–42
(35, 1,'CLM-2026-00035',40, 4,0,'Repaired battery passed QC, ready for dispatch',  'READY_FOR_RETURN', '2026-02-01 09:00:00'),
(36, 1,'CLM-2026-00036',41, 4,1,'OK diagnosis — return battery to dealer',         'READY_FOR_RETURN', '2026-02-02 09:00:00'),
(37, 1,'CLM-2026-00037',42, 4,0,'Service complete, awaiting driver pickup',        'READY_FOR_RETURN', '2026-02-03 09:00:00'),
-- CLOSED (38–40)  dealer=5  batteries 43–45
(38, 1,'CLM-2026-00038',43, 5,0,'Replacement delivered and receiver signature obtained', 'CLOSED',     '2025-12-10 09:00:00'),
(39, 1,'CLM-2026-00039',44, 5,1,'Fully resolved — archived after successful delivery',   'CLOSED',     '2025-12-11 09:00:00'),
(40, 1,'CLM-2026-00040',45, 5,0,'Full claim lifecycle complete',                         'CLOSED',     '2025-12-12 09:00:00');

-- ─── 6. CLAIM STATUS HISTORY (15) ───────────────────────────
INSERT IGNORE INTO claim_status_history
  (id, claim_id, from_status, to_status, changed_by, changed_at)
VALUES
(1,  6,  'DRAFT',            'SUBMITTED',        3,  '2026-04-01 09:10:00'),
(2,  7,  'DRAFT',            'SUBMITTED',        3,  '2026-04-01 10:10:00'),
(3,  8,  'DRAFT',            'SUBMITTED',        3,  '2026-04-02 09:10:00'),
(4,  9,  'DRAFT',            'SUBMITTED',        3,  '2026-04-02 10:10:00'),
(5,  10, 'DRAFT',            'SUBMITTED',        3,  '2026-04-02 11:10:00'),
(6,  11, 'SUBMITTED',        'DRIVER_RECEIVED',  1,  '2026-03-30 09:15:00'),
(7,  12, 'SUBMITTED',        'DRIVER_RECEIVED',  1,  '2026-03-30 10:15:00'),
(8,  13, 'SUBMITTED',        'DRIVER_RECEIVED',  1,  '2026-03-31 09:15:00'),
(9,  16, 'DRIVER_RECEIVED',  'IN_TRANSIT',       1,  '2026-03-28 11:30:00'),
(10, 17, 'DRIVER_RECEIVED',  'IN_TRANSIT',       1,  '2026-03-28 12:30:00'),
(11, 21, 'IN_TRANSIT',       'AT_SERVICE',       8,  '2026-03-10 09:30:00'),
(12, 26, 'AT_SERVICE',       'DIAGNOSED',        8,  '2026-02-20 14:00:00'),
(13, 31, 'DIAGNOSED',        'REPLACED',         1,  '2026-01-21 10:00:00'),
(14, 35, 'REPLACED',         'READY_FOR_RETURN', 1,  '2026-02-05 10:00:00'),
(15, 38, 'READY_FOR_RETURN', 'CLOSED',           1,  '2025-12-15 10:00:00');

-- ─── 7. DRIVER ROUTES (5) ───────────────────────────────────
-- Route 1&2: today's routes   Route 3&4: yesterday   Route 5: 2 days ago
INSERT IGNORE INTO driver_routes
  (id, tenant_id, driver_id, route_date, status, created_by, created_at)
VALUES
(1, 1, 6,'2026-04-04','ACTIVE',    9,'2026-04-04 06:00:00'),
(2, 1, 7,'2026-04-04','PLANNED',   9,'2026-04-04 06:30:00'),
(3, 1, 6,'2026-04-03','COMPLETED', 9,'2026-04-03 06:00:00'),
(4, 1, 7,'2026-04-03','COMPLETED', 9,'2026-04-03 06:30:00'),
(5, 1, 6,'2026-04-02','COMPLETED', 9,'2026-04-02 06:00:00');

-- ─── 8. DRIVER TASKS (13) ───────────────────────────────────
INSERT IGNORE INTO driver_tasks
  (id, tenant_id, route_id, claim_id, task_type, status, completed_at, created_at)
VALUES
-- Route 1 (today · ACTIVE · driver=6)
(1,  1,1,11,'DELIVERY_NEW',          'PENDING',NULL,                   '2026-04-04 06:05:00'),
(2,  1,1,12,'PICKUP_SERVICE',        'PENDING',NULL,                   '2026-04-04 06:05:00'),
(3,  1,1,13,'DELIVERY_NEW',          'ACTIVE', NULL,                   '2026-04-04 06:05:00'),
-- Route 2 (today · PLANNED · driver=7)
(4,  1,2,14,'PICKUP_SERVICE',        'PENDING',NULL,                   '2026-04-04 06:35:00'),
(5,  1,2,15,'DELIVERY_NEW',          'PENDING',NULL,                   '2026-04-04 06:35:00'),
-- Route 3 (yesterday · COMPLETED · driver=6)
(6,  1,3,16,'DELIVERY_NEW',          'DONE',   '2026-04-03 16:00:00', '2026-04-03 06:05:00'),
(7,  1,3,17,'DELIVERY_NEW',          'DONE',   '2026-04-03 17:00:00', '2026-04-03 06:05:00'),
(8,  1,3,18,'PICKUP_SERVICE',        'DONE',   '2026-04-03 18:00:00', '2026-04-03 06:05:00'),
-- Route 4 (yesterday · COMPLETED · driver=7)
(9,  1,4,19,'DELIVERY_NEW',          'DONE',   '2026-04-03 15:00:00', '2026-04-03 06:35:00'),
(10, 1,4,20,'PICKUP_SERVICE',        'DONE',   '2026-04-03 16:30:00', '2026-04-03 06:35:00'),
-- Route 5 (2 days ago · COMPLETED · driver=6)
(11, 1,5,38,'DELIVERY_REPLACEMENT',  'DONE',   '2026-04-02 15:00:00', '2026-04-02 06:05:00'),
(12, 1,5,39,'DELIVERY_REPLACEMENT',  'DONE',   '2026-04-02 16:00:00', '2026-04-02 06:05:00'),
(13, 1,5,40,'DELIVERY_REPLACEMENT',  'DONE',   '2026-04-02 17:00:00', '2026-04-02 06:05:00');

-- ─── 9. DRIVER HANDSHAKES (2) ───────────────────────────────
-- sig_hash values are 64-char hex strings
INSERT IGNORE INTO driver_handshakes
  (id, tenant_id, route_id, driver_id, dealer_id, batch_photo, dealer_signature, sig_hash, handshake_at)
VALUES
(1, 1,3,6,4,
 'batch_route3_20260403.webp',
 'SPEED-BATTERIES-SIGN-03APR2026',
 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
 '2026-04-03 18:30:00'),
(2, 1,5,6,5,
 'batch_route5_20260402.webp',
 'CITY-POWER-HOUSE-SIGN-02APR2026',
 'b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3',
 '2026-04-02 17:30:00');

-- ─── 10. HANDSHAKE TASKS (6) ────────────────────────────────
INSERT IGNORE INTO handshake_tasks (handshake_id, task_id) VALUES
(1,6),(1,7),(1,8),
(2,11),(2,12),(2,13);

-- ─── 11. SERVICE JOBS (10) · claims 21–30 ───────────────────
INSERT IGNORE INTO service_jobs
  (id, tenant_id, claim_id, inward_by, diagnosis, diagnosis_notes, inward_at, diagnosed_at)
VALUES
(1,  1,21,8,'PENDING', NULL,
 '2026-03-10 09:30:00', NULL),
(2,  1,22,8,'PENDING', NULL,
 '2026-03-11 09:30:00', NULL),
(3,  1,23,8,'OK',
 'Visual inspection passed; load test OK; minor sulphation cleaned.',
 '2026-03-12 09:30:00','2026-03-15 14:00:00'),
(4,  1,24,8,'REPLACE',
 'BMS fault C04 — unrecoverable cell imbalance; replacement recommended.',
 '2026-03-13 09:30:00','2026-03-16 10:00:00'),
(5,  1,25,8,'PENDING', NULL,
 '2026-03-14 09:30:00', NULL),
(6,  1,26,8,'OK',
 'Cell reversal corrected via reconditioning; capacity restored to 92%.',
 '2026-02-16 09:30:00','2026-02-20 14:00:00'),
(7,  1,27,8,'REPLACE',
 'Separator damage confirmed on teardown; replacement required.',
 '2026-02-17 09:30:00','2026-02-22 11:00:00'),
(8,  1,28,8,'OK',
 'Active material intact; electrolyte replenished; passed load test.',
 '2026-02-18 09:30:00','2026-02-24 12:00:00'),
(9,  1,29,8,'REPLACE',
 'Overcharge damage — plates warped; beyond economical repair.',
 '2026-02-19 09:30:00','2026-02-25 13:00:00'),
(10, 1,30,8,'PENDING', NULL,
 '2026-02-20 09:30:00', NULL);

-- ─── 12. DELIVERY INCENTIVES (5) ────────────────────────────
INSERT IGNORE INTO delivery_incentives
  (id, tenant_id, driver_id, task_id, claim_id, handshake_id,
   task_type, amount, delivery_date, is_paid, paid_at, created_at)
VALUES
(1, 1,6, 6,16,1,'DELIVERY_NEW',        150.00,'2026-04-03',1,'2026-04-03 23:00:00','2026-04-03 18:30:00'),
(2, 1,6, 7,17,1,'DELIVERY_NEW',        150.00,'2026-04-03',1,'2026-04-03 23:00:00','2026-04-03 18:30:00'),
(3, 1,6,11,38,2,'DELIVERY_REPLACEMENT',200.00,'2026-04-02',0, NULL,                '2026-04-02 17:30:00'),
(4, 1,6,12,39,2,'DELIVERY_REPLACEMENT',200.00,'2026-04-02',0, NULL,                '2026-04-02 17:30:00'),
(5, 1,6,13,40,2,'DELIVERY_REPLACEMENT',200.00,'2026-04-02',0, NULL,                '2026-04-02 17:30:00');

-- ─── 13. CLAIM TRACKING TOKENS (3) ──────────────────────────
INSERT IGNORE INTO claim_tracking_tokens
  (id, tenant_id, claim_id, token, expires_at, view_count, created_at)
VALUES
(1, 1, 6, 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2','2026-06-01 00:00:00',2,'2026-04-01 09:15:00'),
(2, 1,11, 'b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3','2026-06-01 00:00:00',5,'2026-03-30 09:20:00'),
(3, 1,21, 'c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4','2026-06-01 00:00:00',1,'2026-03-10 09:35:00');

-- ─── 14. TALLY IMPORTS (3) ──────────────────────────────────
INSERT IGNORE INTO tally_imports
  (id, tenant_id, filename, imported_by, total_rows, inserted_rows,
   upserted_rows, skipped_rows, imported_at)
VALUES
(1, 1,'tally_export_oct2025.xml',8,75,70, 5,0,'2025-10-15 11:00:00'),
(2, 1,'tally_export_nov2025.xml',8,45,10,35,0,'2025-11-20 14:00:00'),
(3, 1,'tally_export_dec2025.xml',8,20,15, 5,0,'2025-12-15 16:00:00');

-- ─── 15. CRM CUSTOMERS (30) ─────────────────────────────────
-- dealer_id 2–5 · lifecycle: LEAD(8) PROSPECT(6) ACTIVE(8) REPEAT(5) CHURNED(3)
INSERT IGNORE INTO crm_customers
  (id, tenant_id, dealer_id, name, email, phone, city,
   lifecycle_stage, source, total_batteries_bought, last_purchase_at, created_at)
VALUES
-- Dealer 2 (Raj Motors) → customers 1–8
(1,  1,2,'Ramesh Fleet Services',   'ramesh@fleetco.in',   '+91-9811001234','Mumbai',   'LEAD',    'HANDSHAKE', 0, NULL,                   '2026-03-10 10:00:00'),
(2,  1,2,'Bharat Transport Ltd',    'info@bharat-t.com',   '+91-9822002345','Delhi',    'PROSPECT','MANUAL',    2, '2026-02-15 00:00:00',   '2025-12-01 10:00:00'),
(3,  1,2,'Anand Auto Pvt Ltd',      'anand@anandauto.in',  '+91-9833003456','Pune',     'ACTIVE',  'HANDSHAKE', 5, '2026-03-01 00:00:00',   '2025-09-15 10:00:00'),
(4,  1,2,'Sunrise Logistics',       'ops@sunrise-log.in',  '+91-9844004567','Bangalore','REPEAT',  'HANDSHAKE',12, '2026-03-20 00:00:00',   '2025-06-10 10:00:00'),
(5,  1,2,'Naveen Cab Network',      'naveen@cabnet.in',    '+91-9855005678','Chennai',  'LEAD',    'API',       0, NULL,                   '2026-04-01 10:00:00'),
(6,  1,2,'Apex Battery Shop',       'apex@battery.co.in',  '+91-9866006789','Kolkata',  'PROSPECT','MANUAL',    1, '2026-01-10 00:00:00',   '2025-11-05 10:00:00'),
(7,  1,2,'Prime Power Solutions',   'prime@powersol.in',   '+91-9877007890','Hyderabad','ACTIVE',  'HANDSHAKE', 8, '2026-03-28 00:00:00',   '2025-08-20 10:00:00'),
(8,  1,2,'Excel Motors',            'excel@motors.in',     '+91-9888008901','Ahmedabad','REPEAT',  'IMPORT',   18, '2026-03-15 00:00:00',   '2025-04-01 10:00:00'),
-- Dealer 3 (Priya Auto Works) → customers 9–16
(9,  1,3,'Vikram Auto Works',       'vikram@autoworks.in', '+91-9811009012','Jaipur',   'LEAD',    'MANUAL',    0, NULL,                   '2026-03-25 10:00:00'),
(10, 1,3,'Metro Cab Services',      'metro@cabsvc.in',     '+91-9822010123','Mumbai',   'PROSPECT','API',        3, '2026-02-28 00:00:00',   '2025-10-10 10:00:00'),
(11, 1,3,'Sudhir Electricals',      'sudhir@elec.in',      '+91-9833011234','Delhi',    'ACTIVE',  'HANDSHAKE', 6, '2026-04-01 00:00:00',   '2025-07-15 10:00:00'),
(12, 1,3,'Galaxy Fleet Pvt Ltd',    'galaxy@fleet.in',     '+91-9844012345','Surat',    'REPEAT',  'HANDSHAKE',15, '2026-03-10 00:00:00',   '2025-03-01 10:00:00'),
(13, 1,3,'Green Drive EV',          'green@driveev.in',    '+91-9855013456','Lucknow',  'LEAD',    'IMPORT',    0, NULL,                   '2026-04-02 10:00:00'),
(14, 1,3,'Horizon Batteries',       'horizon@bat.co.in',   '+91-9866014567','Kochi',    'PROSPECT','MANUAL',    2, '2026-01-20 00:00:00',   '2025-12-15 10:00:00'),
(15, 1,3,'TechDrive Solutions',     'techdrive@sol.in',    '+91-9877015678','Pune',     'ACTIVE',  'HANDSHAKE', 9, '2026-04-03 00:00:00',   '2025-05-20 10:00:00'),
(16, 1,3,'North Star Autos',        'northstar@autos.in',  '+91-9888016789','Bangalore','CHURNED', 'MANUAL',    4, '2025-08-01 00:00:00',   '2025-01-10 10:00:00'),
-- Dealer 4 (Speed Batteries) → customers 17–22
(17, 1,4,'SunPower Vehicles',       'sunpower@veh.in',     '+91-9811017890','Chennai',  'LEAD',    'API',       0, NULL,                   '2026-04-03 10:00:00'),
(18, 1,4,'Delta Energy Store',      'delta@energy.co.in',  '+91-9822018901','Kolkata',  'PROSPECT','HANDSHAKE', 1, '2026-03-05 00:00:00',   '2025-11-20 10:00:00'),
(19, 1,4,'Omega Fleet India',       'omega@fleetind.in',   '+91-9833019012','Hyderabad','ACTIVE',  'IMPORT',    7, '2026-03-25 00:00:00',   '2025-06-01 10:00:00'),
(20, 1,4,'Rapid Battery Hub',       'rapid@bathub.in',     '+91-9844020123','Jaipur',   'LEAD',    'MANUAL',    0, NULL,                   '2026-04-04 09:00:00'),
(21, 1,4,'PowerMax Services',       'powermax@svc.in',     '+91-9855021234','Ahmedabad','ACTIVE',  'HANDSHAKE',11, '2026-04-02 00:00:00',   '2025-04-15 10:00:00'),
(22, 1,4,'BlueSky Motors',          'bluesky@motors.in',   '+91-9866022345','Mumbai',   'REPEAT',  'HANDSHAKE',22, '2026-04-01 00:00:00',   '2025-02-10 10:00:00'),
-- Dealer 5 (City Power House) → customers 23–30
(23, 1,5,'Velocity Cargo Pvt Ltd',  'velocity@cargo.in',   '+91-9811023456','Delhi',    'LEAD',    'IMPORT',    0, NULL,                   '2026-04-01 10:00:00'),
(24, 1,5,'Prestige Auto Group',     'prestige@auto.in',    '+91-9822024567','Pune',     'PROSPECT','MANUAL',    2, '2026-02-10 00:00:00',   '2025-10-25 10:00:00'),
(25, 1,5,'Kiran Battery Dealers',   'kiran@batdeal.in',    '+91-9833025678','Bangalore','ACTIVE',  'HANDSHAKE', 4, '2026-03-18 00:00:00',   '2025-08-05 10:00:00'),
(26, 1,5,'Transway Logistics',      'transway@log.in',     '+91-9844026789','Surat',    'LEAD',    'API',       0, NULL,                   '2026-03-28 10:00:00'),
(27, 1,5,'AutoZone India',          'autozone@india.in',   '+91-9855027890','Lucknow',  'ACTIVE',  'HANDSHAKE', 3, '2026-03-22 00:00:00',   '2025-09-10 10:00:00'),
(28, 1,5,'CityRide Solutions',      'cityride@sol.in',     '+91-9866028901','Kochi',    'REPEAT',  'IMPORT',   16, '2026-01-30 00:00:00',   '2025-01-15 10:00:00'),
(29, 1,5,'National EV Fleet',       'national@evfleet.in', '+91-9877029012','Chennai',  'CHURNED', 'MANUAL',    5, '2025-09-15 00:00:00',   '2024-12-01 10:00:00'),
(30, 1,5,'Atlas Motors',            'atlas@motors.in',     '+91-9888030123','Kolkata',  'CHURNED', 'MANUAL',    3, '2025-07-01 00:00:00',   '2024-11-01 10:00:00');

-- ─── 16. CRM LEADS (40) ─────────────────────────────────────
-- Stages: NEW(10) CONTACTED(8) QUALIFIED(8) PROPOSAL(6) WON(5) LOST(3)
INSERT IGNORE INTO crm_leads
  (id, tenant_id, customer_id, assigned_to, title, stage,
   expected_value, source, follow_up_at, closed_at, created_at)
VALUES
-- NEW (1–10)
(1,  1, 1,10,'Initial outreach – 10-unit fleet order',          'NEW',     45000.00,'Cold Call', '2026-04-10 10:00:00',NULL,'2026-03-20 10:00:00'),
(2,  1, 5,10,'Fleet expansion inquiry – 5 units',               'NEW',     22500.00,'Website',   '2026-04-11 10:00:00',NULL,'2026-04-01 10:00:00'),
(3,  1, 9,10,'Annual maintenance contract discussion',           'NEW',     80000.00,'Referral',  '2026-04-12 10:00:00',NULL,'2026-03-25 10:00:00'),
(4,  1,13,10,'Electric 3-wheeler battery bundle',                'NEW',     35000.00,'Import',    '2026-04-13 10:00:00',NULL,'2026-04-02 10:00:00'),
(5,  1,17,10,'First-time purchase enquiry',                      'NEW',     18000.00,'API',       '2026-04-14 10:00:00',NULL,'2026-04-03 10:00:00'),
(6,  1,20,10,'Pilot order – 3 units trial',                      'NEW',     13500.00,'Cold Call', '2026-04-15 10:00:00',NULL,'2026-04-04 09:00:00'),
(7,  1,23,10,'Bulk cargo fleet requirement',                     'NEW',    125000.00,'Import',    '2026-04-16 10:00:00',NULL,'2026-04-01 10:00:00'),
(8,  1,26,10,'Replacement battery shortlist',                    'NEW',     27000.00,'Website',   '2026-04-17 10:00:00',NULL,'2026-03-28 10:00:00'),
(9,  1, 2,10,'Additional 2-unit requirement',                    'NEW',      9000.00,'Referral',  '2026-04-18 10:00:00',NULL,'2026-04-02 10:00:00'),
(10, 1,10,10,'Upgrade from lead-acid to lithium-ion',            'NEW',     56000.00,'Cold Call', '2026-04-20 10:00:00',NULL,'2026-04-03 10:00:00'),
-- CONTACTED (11–18)
(11, 1, 6,10,'Demo scheduled – 4-unit trial',                    'CONTACTED',18000.00,'Manual',   '2026-04-08 10:00:00',NULL,'2026-03-15 10:00:00'),
(12, 1,14,10,'Follow-up call after brochure share',              'CONTACTED',12000.00,'Referral', '2026-04-09 10:00:00',NULL,'2026-03-18 10:00:00'),
(13, 1,18,10,'Technical spec discussion ongoing',                'CONTACTED',30000.00,'Cold Call','2026-04-07 10:00:00',NULL,'2026-03-10 10:00:00'),
(14, 1,24,10,'Pricing quote requested by customer',              'CONTACTED',24000.00,'Website',  '2026-04-06 10:00:00',NULL,'2026-03-12 10:00:00'),
(15, 1, 3,10,'Expansion of existing 5-unit fleet',               'CONTACTED',40000.00,'Referral', '2026-04-05 10:00:00',NULL,'2026-03-05 10:00:00'),
(16, 1,11,10,'Interest in annual service plan',                  'CONTACTED',95000.00,'API',      '2026-05-01 10:00:00',NULL,'2026-03-01 10:00:00'),
(17, 1,19,10,'Replacing aging 6-unit stock',                     'CONTACTED',27000.00,'Import',   '2026-04-25 10:00:00',NULL,'2026-03-20 10:00:00'),
(18, 1,25,10,'One-time battery replacement',                     'CONTACTED',18000.00,'Manual',   '2026-04-30 10:00:00',NULL,'2026-03-22 10:00:00'),
-- QUALIFIED (19–26)
(19, 1, 7,10,'8-unit quarterly supply agreement',                'QUALIFIED',36000.00,'Referral', '2026-04-15 10:00:00',NULL,'2026-02-20 10:00:00'),
(20, 1,15,10,'Full lithium upgrade – entire fleet',              'QUALIFIED',120000.00,'Cold Call','2026-04-20 10:00:00',NULL,'2026-02-25 10:00:00'),
(21, 1,21,10,'Premium model evaluation for 11 units',            'QUALIFIED',55000.00,'API',      '2026-04-18 10:00:00',NULL,'2026-03-01 10:00:00'),
(22, 1,27,10,'3 units + service contract bundle',                'QUALIFIED',31500.00,'Website',  '2026-04-22 10:00:00',NULL,'2026-03-05 10:00:00'),
(23, 1, 4,10,'Annual replenishment discussion',                  'QUALIFIED',60000.00,'Referral', '2026-04-25 10:00:00',NULL,'2026-02-15 10:00:00'),
(24, 1,12,10,'Fleet optimization package',                       'QUALIFIED',75000.00,'Import',   '2026-04-28 10:00:00',NULL,'2026-02-10 10:00:00'),
(25, 1,22,10,'Bulk discount negotiation – 22 units',             'QUALIFIED',110000.00,'Referral','2026-05-05 10:00:00',NULL,'2026-02-05 10:00:00'),
(26, 1,28,10,'Renewal of multi-year supply agreement',           'QUALIFIED',90000.00,'Manual',   '2026-05-10 10:00:00',NULL,'2026-01-20 10:00:00'),
-- PROPOSAL (27–32)
(27, 1, 8,10,'Multi-year supply proposal sent',                  'PROPOSAL',200000.00,'Import',   '2026-04-10 10:00:00',NULL,'2026-01-10 10:00:00'),
(28, 1,16,10,'Win-back proposal for churned account',            'PROPOSAL', 45000.00,'Manual',   '2026-04-05 10:00:00',NULL,'2026-02-01 10:00:00'),
(29, 1,29,10,'Re-engagement proposal submitted',                 'PROPOSAL', 30000.00,'Cold Call','2026-04-08 10:00:00',NULL,'2026-03-15 10:00:00'),
(30, 1,30,10,'Competitive offer for churned client',             'PROPOSAL', 25000.00,'Referral', '2026-04-12 10:00:00',NULL,'2026-03-10 10:00:00'),
(31, 1, 3,10,'20-unit annual supply quote',                      'PROPOSAL',180000.00,'Referral', '2026-04-15 10:00:00',NULL,'2026-01-05 10:00:00'),
(32, 1,11,10,'Enterprise service + supply bundle',               'PROPOSAL',270000.00,'API',      '2026-04-20 10:00:00',NULL,'2026-02-20 10:00:00'),
-- WON (33–37)
(33, 1, 4,10,'Q1 2026 order – 12 units confirmed',               'WON',  54000.00,'Referral',NULL,'2026-02-28 10:00:00','2025-12-01 10:00:00'),
(34, 1,12,10,'Annual contract signed January 2026',              'WON', 180000.00,'Import',  NULL,'2026-01-15 10:00:00','2025-11-01 10:00:00'),
(35, 1,22,10,'30-unit mega order closed',                        'WON', 270000.00,'Referral',NULL,'2026-03-01 10:00:00','2025-10-15 10:00:00'),
(36, 1, 8,10,'2-year exclusive supply deal finalized',           'WON', 480000.00,'Import',  NULL,'2026-01-10 10:00:00','2025-09-01 10:00:00'),
(37, 1,28,10,'Premium service renewal confirmed',                'WON', 115000.00,'Manual',  NULL,'2025-12-20 10:00:00','2025-08-01 10:00:00'),
-- LOST (38–40)
(38, 1,16,10,'Lost to competitor on pricing',                    'LOST', 35000.00,'Manual',  NULL,'2026-02-15 10:00:00','2025-10-01 10:00:00'),
(39, 1,29,10,'Customer ceased operations',                       'LOST', 25000.00,'Cold Call',NULL,'2025-11-01 10:00:00','2025-06-01 10:00:00'),
(40, 1,30,10,'Budget freeze at client side',                     'LOST', 18000.00,'Referral', NULL,'2025-08-01 10:00:00','2025-05-01 10:00:00');

-- ─── 17. CRM LEAD ACTIVITIES (10) ───────────────────────────
INSERT IGNORE INTO crm_lead_activities
  (id, tenant_id, lead_id, user_id, activity_type, body, old_stage, new_stage, created_at)
VALUES
(1,  1, 1,10,'NOTE',        'Initial contact via LinkedIn DM.',                               NULL,        NULL,        '2026-03-21 10:00:00'),
(2,  1, 3,10,'CALL',        'Discussed 48V pack requirements for logistics fleet.',            NULL,        NULL,        '2026-03-26 11:00:00'),
(3,  1,11,10,'STAGE_CHANGE','Demo booked; moving to CONTACTED.',                              'NEW',       'CONTACTED', '2026-03-16 10:00:00'),
(4,  1,19,10,'STAGE_CHANGE','Technical evaluation passed; moved to QUALIFIED.',               'CONTACTED', 'QUALIFIED', '2026-02-21 11:00:00'),
(5,  1,27,10,'EMAIL',       'Proposal document and pricing sheet sent via email.',             NULL,        NULL,        '2026-01-11 09:00:00'),
(6,  1,33,10,'STAGE_CHANGE','PO received from customer; deal WON.',                          'PROPOSAL',  'WON',       '2026-02-28 10:00:00'),
(7,  1,38,10,'NOTE',        'Customer chose Competitor X due to 8% lower unit price.',        NULL,        NULL,        '2026-02-15 14:00:00'),
(8,  1,38,10,'STAGE_CHANGE','Marked LOST after final decision call.',                         'PROPOSAL',  'LOST',      '2026-02-15 15:00:00'),
(9,  1, 7,10,'VISIT',       'On-site visit to Velocity cargo hub — strong buying signals.',   NULL,        NULL,        '2026-04-02 10:00:00'),
(10, 1,32,10,'FOLLOW_UP',   'Enterprise bundle follow-up scheduled with procurement head.',   NULL,        NULL,        '2026-02-21 11:00:00');

-- ─── 18. CRM CAMPAIGNS (5) ──────────────────────────────────
INSERT IGNORE INTO crm_campaigns
  (id, tenant_id, name, channel, segment_id, status,
   total_recipients, sent_count, failed_count, created_by, created_at)
VALUES
(1,1,'Q1 2026 New Battery Launch',    'EMAIL',   NULL,'COMPLETED',  150,147,3,10,'2026-01-10 09:00:00'),
(2,1,'WhatsApp Fleet Promo Mar 2026', 'WHATSAPP',NULL,'COMPLETED',   80, 78,2,10,'2026-03-01 09:00:00'),
(3,1,'April Renewal Reminder',        'EMAIL',   NULL,'SCHEDULED',   60,  0,0,10,'2026-04-01 09:00:00'),
(4,1,'Premium Service Campaign',      'BOTH',    NULL,'DISPATCHING', 45, 22,1,10,'2026-04-03 09:00:00'),
(5,1,'Re-engage Churned Accounts',    'EMAIL',   NULL,'DRAFT',       10,  0,0,10,'2026-04-04 09:00:00');

-- ─── 19. AUDIT LOGS (10) ────────────────────────────────────
INSERT IGNORE INTO audit_logs
  (id, tenant_id, user_id, action, entity_type, entity_id,
   old_values, new_values, severity, ip_address, created_at)
VALUES
(1,  1, 1,'USER_CREATE',      'users',           1,  NULL,
 '{"role":"ADMIN"}',                                                              'LOW',     '192.168.1.1','2026-01-01 09:00:00'),
(2,  1, 1,'CLAIM_STATUS',     'claims',          11, '{"status":"SUBMITTED"}',
 '{"status":"DRIVER_RECEIVED"}',                                                  'MEDIUM',  '192.168.1.2','2026-03-30 09:30:00'),
(3,  1, 1,'CLAIM_STATUS',     'claims',          16, '{"status":"DRIVER_RECEIVED"}',
 '{"status":"IN_TRANSIT"}',                                                       'MEDIUM',  '192.168.1.2','2026-03-28 11:00:00'),
(4,  1, 8,'SERVICE_INWARD',   'claims',          21, NULL,
 '{"diagnosis":"PENDING"}',                                                       'LOW',     '192.168.1.3','2026-03-10 09:15:00'),
(5,  1, 8,'SERVICE_DIAGNOSE', 'claims',          23, '{"diagnosis":"PENDING"}',
 '{"diagnosis":"OK"}',                                                            'MEDIUM',  '192.168.1.3','2026-03-15 14:00:00'),
(6,  1, 8,'SERVICE_DIAGNOSE', 'claims',          24, '{"diagnosis":"PENDING"}',
 '{"diagnosis":"REPLACE"}',                                                       'HIGH',    '192.168.1.3','2026-03-16 10:00:00'),
(7,  1, 9,'ROUTE_CREATE',     'driver_routes',   1,  NULL,
 '{"driver_id":6,"date":"2026-04-04","status":"ACTIVE"}',                         'LOW',     '192.168.1.4','2026-04-04 06:05:00'),
(8,  1, 6,'HANDSHAKE',        'driver_handshakes',1, NULL,
 '{"tasks":[6,7,8],"dealer_id":4}',                                               'MEDIUM',  '192.168.1.5','2026-04-03 18:30:00'),
(9,  1,10,'CRM_LEAD_WON',     'crm_leads',       33, '{"stage":"PROPOSAL"}',
 '{"stage":"WON"}',                                                               'MEDIUM',  '192.168.1.6','2026-02-28 15:00:00'),
(10, 1, 1,'TALLY_IMPORT',     'tally_imports',   1,  NULL,
 '{"filename":"tally_export_oct2025.xml","rows":75}',                             'LOW',     '192.168.1.2','2025-10-15 11:05:00');

-- ─── Done ────────────────────────────────────────────────────
SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- RECORD SUMMARY
-- ─────────────────────────────────────────────────────────────
--  Table                     Rows
--  ------------------------  ----
--  users                      10
--  tenant_settings             5
--  batteries                 100
--  tenant_sequences            1
--  claims                     40
--  claim_status_history       15
--  driver_routes               5
--  driver_tasks               13
--  driver_handshakes           2
--  handshake_tasks             6
--  service_jobs               10
--  delivery_incentives         5
--  claim_tracking_tokens       3
--  tally_imports               3
--  crm_customers              30
--  crm_leads                  40
--  crm_lead_activities        10
--  crm_campaigns               5
--  audit_logs                 10
--  ─────────────────────────────
--  TOTAL                     313
-- ============================================================
