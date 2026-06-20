-- ============================================================
-- إضافة نظام المراحل لـ Supabase (PostgreSQL)
-- شغّل هذا الملف في Supabase → SQL Editor
-- ============================================================

-- 1. إضافة عمود phase لجدول contract_items
ALTER TABLE contract_items
  ADD COLUMN IF NOT EXISTS phase TEXT
  CHECK (phase IN ('design', 'study', 'execution'));

-- 2. إنشاء جدول مراحل العملاء
CREATE TABLE IF NOT EXISTS client_phases (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       UUID        NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  organization_id UUID        NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  phase           TEXT        NOT NULL CHECK (phase IN ('design', 'study', 'execution')),
  status          TEXT        NOT NULL DEFAULT 'not_started'
                              CHECK (status IN ('not_started', 'active', 'completed', 'skipped')),
  started_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  notes           TEXT        DEFAULT '',
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(client_id, phase)
);

-- 3. فهرس للأداء
CREATE INDEX IF NOT EXISTS idx_client_phases_client_id ON client_phases(client_id);
CREATE INDEX IF NOT EXISTS idx_client_phases_org_id    ON client_phases(organization_id);
CREATE INDEX IF NOT EXISTS idx_contract_items_phase    ON contract_items(phase);
