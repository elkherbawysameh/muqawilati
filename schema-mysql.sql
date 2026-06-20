-- ============================================================
-- مقاولاتي - MySQL Schema
-- متوافق مع Hostinger MySQL
-- ============================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ─── PLANS ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS plans (
  id            CHAR(36)        NOT NULL PRIMARY KEY,
  name          VARCHAR(50)     NOT NULL UNIQUE,
  price         DECIMAL(10,2)   NOT NULL DEFAULT 0,
  max_clients   INT             DEFAULT 10,
  max_workers   INT             DEFAULT 5,
  max_users     INT             DEFAULT 1,
  features      JSON,
  is_active     TINYINT(1)      DEFAULT 1,
  created_at    DATETIME        DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── ORGANIZATIONS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS organizations (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  name            VARCHAR(255)  NOT NULL,
  phone           VARCHAR(50),
  address         TEXT,
  email           VARCHAR(255),
  logo_url        TEXT,
  invoice_prefix  VARCHAR(20)   DEFAULT 'INV',
  tax_rate        DECIMAL(5,2)  DEFAULT 14.00,
  is_active       TINYINT(1)    DEFAULT 1,
  created_at      DATETIME      DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── USERS ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  organization_id CHAR(36)      NOT NULL,
  email           VARCHAR(255)  NOT NULL UNIQUE,
  password_hash   VARCHAR(255)  NOT NULL,
  full_name       VARCHAR(255),
  role            ENUM('owner','admin','member') DEFAULT 'member',
  is_owner        TINYINT(1)    DEFAULT 0,
  is_active       TINYINT(1)    DEFAULT 1,
  last_login_at   DATETIME,
  created_at      DATETIME      DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── SUBSCRIPTIONS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS subscriptions (
  id                    CHAR(36)  NOT NULL PRIMARY KEY,
  organization_id       CHAR(36)  NOT NULL,
  plan_id               CHAR(36),
  account_type          ENUM('trial','paid','free') DEFAULT 'trial',
  status                ENUM('active','cancelled','expired','past_due') DEFAULT 'active',
  current_period_start  DATETIME,
  current_period_end    DATETIME,
  created_at            DATETIME  DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME  DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  FOREIGN KEY (plan_id) REFERENCES plans(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── CLIENTS ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS clients (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  organization_id CHAR(36)      NOT NULL,
  name            VARCHAR(255)  NOT NULL,
  phone           VARCHAR(50),
  email           VARCHAR(255),
  location        TEXT,
  notes           TEXT,
  is_active       TINYINT(1)    DEFAULT 1,
  created_at      DATETIME      DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── CONTRACTS ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS contracts (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  organization_id CHAR(36)      NOT NULL,
  client_id       CHAR(36)      NOT NULL,
  title           VARCHAR(500),
  description     TEXT,
  status          ENUM('draft','active','completed','cancelled') DEFAULT 'active',
  start_date      DATE,
  end_date        DATE,
  created_at      DATETIME      DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── CONTRACT ITEMS ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS contract_items (
  id              CHAR(36)        NOT NULL PRIMARY KEY,
  contract_id     CHAR(36)        NOT NULL,
  organization_id CHAR(36)        NOT NULL,
  description     TEXT            NOT NULL,
  unit            VARCHAR(50)     DEFAULT 'بند',
  quantity        DECIMAL(10,2)   DEFAULT 1,
  unit_price      DECIMAL(15,2)   DEFAULT 0,
  status          ENUM('pending','in_progress','done') DEFAULT 'pending',
  phase           ENUM('design','study','execution')   DEFAULT NULL,
  sort_order      INT             DEFAULT 0,
  completed_at    DATETIME,
  created_at      DATETIME        DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (contract_id) REFERENCES contracts(id) ON DELETE CASCADE,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── CLIENT PHASES ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS client_phases (
  id              CHAR(36)    NOT NULL PRIMARY KEY,
  client_id       CHAR(36)    NOT NULL,
  organization_id CHAR(36)    NOT NULL,
  phase           ENUM('design','study','execution') NOT NULL,
  status          ENUM('not_started','active','completed','skipped') DEFAULT 'not_started',
  started_at      DATETIME,
  completed_at    DATETIME,
  notes           TEXT,
  created_at      DATETIME    DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_client_phase (client_id, phase),
  FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── CONTRACT PAYMENTS ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS contract_payments (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  contract_id     CHAR(36)      NOT NULL,
  organization_id CHAR(36)      NOT NULL,
  amount          DECIMAL(15,2) NOT NULL,
  type            ENUM('received','refund') DEFAULT 'received',
  payment_date    DATE,
  notes           TEXT,
  created_at      DATETIME      DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (contract_id) REFERENCES contracts(id) ON DELETE CASCADE,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── CONTRACT ATTACHMENTS ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS contract_attachments (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  contract_id     CHAR(36)      NOT NULL,
  organization_id CHAR(36)      NOT NULL,
  filename        VARCHAR(500),
  file_url        TEXT,
  file_type       VARCHAR(50)   DEFAULT 'photo',
  caption         TEXT,
  uploaded_by     CHAR(36),
  created_at      DATETIME      DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (contract_id) REFERENCES contracts(id) ON DELETE CASCADE,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── WORKER CATEGORIES ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS worker_categories (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  organization_id CHAR(36)      NOT NULL,
  name            VARCHAR(255)  NOT NULL,
  name_en         VARCHAR(255),
  icon            VARCHAR(50)   DEFAULT '🔧',
  sort_order      INT           DEFAULT 0,
  created_at      DATETIME      DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── WORKERS ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS workers (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  organization_id CHAR(36)      NOT NULL,
  category_id     CHAR(36),
  name            VARCHAR(255)  NOT NULL,
  phone           VARCHAR(50),
  address         TEXT,
  notes           TEXT,
  is_active       TINYINT(1)    DEFAULT 1,
  created_at      DATETIME      DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  FOREIGN KEY (category_id) REFERENCES worker_categories(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── WORKER PHOTOS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS worker_photos (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  worker_id       CHAR(36)      NOT NULL,
  organization_id CHAR(36)      NOT NULL,
  filename        VARCHAR(500),
  caption         TEXT,
  uploaded_at     DATETIME      DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (worker_id) REFERENCES workers(id) ON DELETE CASCADE,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── INVOICES ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS invoices (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  organization_id CHAR(36)      NOT NULL,
  client_id       CHAR(36),
  invoice_number  VARCHAR(100)  NOT NULL,
  issue_date      DATE,
  due_date        DATE,
  subtotal        DECIMAL(15,2) DEFAULT 0,
  tax_rate        DECIMAL(5,2)  DEFAULT 0,
  tax_amount      DECIMAL(15,2) DEFAULT 0,
  total           DECIMAL(15,2) DEFAULT 0,
  status          ENUM('draft','issued','paid','cancelled') DEFAULT 'issued',
  notes           TEXT,
  created_at      DATETIME      DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── INVOICE ITEMS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS invoice_items (
  id            CHAR(36)        NOT NULL PRIMARY KEY,
  invoice_id    CHAR(36)        NOT NULL,
  description   TEXT,
  quantity      DECIMAL(10,2)   DEFAULT 1,
  unit_price    DECIMAL(15,2)   DEFAULT 0,
  total         DECIMAL(15,2)   DEFAULT 0,
  FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── ACTIVITY LOGS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS activity_logs (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  organization_id CHAR(36)      NOT NULL,
  user_id         CHAR(36),
  entity_type     VARCHAR(50),
  entity_id       CHAR(36),
  action          VARCHAR(50),
  details         JSON,
  created_at      DATETIME      DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── SEED: PLANS ──────────────────────────────────────────────
INSERT INTO plans(id, name, price, max_clients, max_workers, max_users) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Free',          0,   10,  5,  1),
  ('00000000-0000-0000-0000-000000000002', 'Basic Monthly', 200, 50,  20, 3),
  ('00000000-0000-0000-0000-000000000003', 'Pro Monthly',   400, -1,  -1, 10)
ON DUPLICATE KEY UPDATE name=name;

SET FOREIGN_KEY_CHECKS = 1;
