-- ============================================================
-- Migration: إضافة نظام المراحل
-- شغّل هذا الملف لو عندك قاعدة بيانات موجودة بالفعل
-- ============================================================

-- إضافة عمود المرحلة لجدول بنود العقد
ALTER TABLE contract_items
  ADD COLUMN IF NOT EXISTS phase ENUM('design','study','execution') DEFAULT NULL;

-- إنشاء جدول مراحل العملاء
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
