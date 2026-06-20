-- =====================================================
-- MUQAWILATI - COMPLETE POSTGRESQL SCHEMA
-- SaaS Architecture for Contracting Management
-- =====================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =====================================================
-- 1. PLANS - باقات الاشتراك
-- =====================================================
CREATE TABLE plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    billing_cycle VARCHAR(20) NOT NULL DEFAULT 'monthly', -- monthly / yearly / lifetime
    price NUMERIC(10,2) NOT NULL DEFAULT 0,
    currency VARCHAR(10) NOT NULL DEFAULT 'EGP',
    included_seats INT NOT NULL DEFAULT 2,
    extra_seat_price NUMERIC(10,2) NOT NULL DEFAULT 0,
    max_clients INT DEFAULT NULL,    -- NULL = unlimited
    max_storage_mb INT DEFAULT 1024, -- حجم التخزين بالميجا
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO plans (name, billing_cycle, price, included_seats, extra_seat_price, max_clients, max_storage_mb) VALUES
('مجاني',          'monthly',   0,    1, 0,   10, 500),
('أساسي شهري',     'monthly',   200,  2, 50,  NULL, 5120),
('أساسي سنوي',     'yearly',    2000, 2, 500, NULL, 5120),
('برو شهري',       'monthly',   400,  5, 50,  NULL, 20480),
('برو سنوي',       'yearly',    4000, 5, 500, NULL, 20480);

-- =====================================================
-- 2. ORGANIZATIONS - الشركات / المقاولون
-- =====================================================
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    address TEXT,
    logo_url TEXT,
    invoice_prefix VARCHAR(20) DEFAULT 'INV',
    tax_rate NUMERIC(5,2) DEFAULT 14.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================
-- 3. USERS - المستخدمين
-- =====================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    full_name VARCHAR(255),
    role VARCHAR(50) NOT NULL DEFAULT 'member',   -- owner / admin / member / viewer
    is_owner BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    added_by UUID REFERENCES users(id) ON DELETE SET NULL,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_org ON users(organization_id);

-- =====================================================
-- 4. SUBSCRIPTIONS - الاشتراكات
-- =====================================================
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    plan_id UUID REFERENCES plans(id) ON DELETE SET NULL,
    account_type VARCHAR(20) NOT NULL DEFAULT 'paid', -- paid / test / trial
    status VARCHAR(20) NOT NULL DEFAULT 'active',     -- active / expired / canceled / trial
    extra_seats INT NOT NULL DEFAULT 0,
    provider VARCHAR(50),              -- stripe / paymob / manual
    provider_subscription_id VARCHAR(255),
    current_period_start TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_subscriptions_org ON subscriptions(organization_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(organization_id, status);

-- =====================================================
-- 5. CLIENTS - عملاء الشركة
-- =====================================================
CREATE TABLE clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    email VARCHAR(255),
    location TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_clients_org ON clients(organization_id);
CREATE INDEX idx_clients_name ON clients(organization_id, name);

-- =====================================================
-- 6. CONTRACTS - العقود (مستوى رئيسي)
-- =====================================================
CREATE TABLE contracts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    client_id UUID REFERENCES clients(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    contract_number VARCHAR(100),
    title VARCHAR(255) NOT NULL DEFAULT 'عقد المشروع',
    description TEXT,
    contract_value NUMERIC(15,2) NOT NULL DEFAULT 0,
    currency VARCHAR(10) NOT NULL DEFAULT 'EGP',
    status VARCHAR(30) NOT NULL DEFAULT 'active', -- draft / active / completed / canceled
    start_date DATE,
    end_date DATE,
    file_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_contracts_org ON contracts(organization_id);
CREATE INDEX idx_contracts_client ON contracts(client_id);
CREATE INDEX idx_contracts_status ON contracts(organization_id, status);

-- =====================================================
-- 7. CONTRACT_ITEMS - بنود العقد
-- =====================================================
CREATE TABLE contract_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id UUID NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    description TEXT NOT NULL,
    unit VARCHAR(50) DEFAULT 'بند',
    quantity NUMERIC(10,2) DEFAULT 1,
    unit_price NUMERIC(15,2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending', -- pending / done
    completed_at TIMESTAMPTZ,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_contract_items_contract ON contract_items(contract_id);
CREATE INDEX idx_contract_items_org ON contract_items(organization_id);

-- =====================================================
-- 8. CONTRACT_PAYMENTS - الدفعات المالية
-- =====================================================
CREATE TABLE contract_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id UUID NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    amount NUMERIC(15,2) NOT NULL,
    payment_date DATE DEFAULT CURRENT_DATE,
    type VARCHAR(20) DEFAULT 'received',  -- received / pending / refund
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_payments_contract ON contract_payments(contract_id);
CREATE INDEX idx_payments_org ON contract_payments(organization_id);
CREATE INDEX idx_payments_due_date ON contract_payments(organization_id, payment_date);

-- =====================================================
-- 9. CONTRACT_ATTACHMENTS - صور وملفات المشروع
-- =====================================================
CREATE TABLE contract_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id UUID NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    filename TEXT NOT NULL,
    file_url TEXT NOT NULL,
    file_type VARCHAR(20) DEFAULT 'photo', -- photo / drawing / document
    caption TEXT,
    uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_attachments_contract ON contract_attachments(contract_id);

-- =====================================================
-- 10. WORKER_CATEGORIES - تصنيفات العمال
-- =====================================================
CREATE TABLE worker_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    name_en VARCHAR(100),
    icon VARCHAR(20) DEFAULT '🔧',
    is_default BOOLEAN DEFAULT false,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_worker_cats_org ON worker_categories(organization_id);

-- =====================================================
-- 11. WORKERS - العمال والصناعية
-- =====================================================
CREATE TABLE workers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    category_id UUID REFERENCES worker_categories(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    address TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_workers_org ON workers(organization_id);
CREATE INDEX idx_workers_category ON workers(category_id);

-- =====================================================
-- 12. WORKER_PHOTOS - صور أعمال العمال
-- =====================================================
CREATE TABLE worker_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id UUID NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    filename TEXT NOT NULL,
    caption TEXT,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_worker_photos_worker ON worker_photos(worker_id);

-- =====================================================
-- 13. INVOICES - الفواتير
-- =====================================================
CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    client_id UUID REFERENCES clients(id) ON DELETE SET NULL,
    invoice_number VARCHAR(50) NOT NULL,
    issue_date DATE DEFAULT CURRENT_DATE,
    due_date DATE,
    subtotal NUMERIC(15,2) DEFAULT 0,
    tax_rate NUMERIC(5,2) DEFAULT 0,
    tax_amount NUMERIC(15,2) DEFAULT 0,
    total NUMERIC(15,2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'issued', -- draft / issued / paid / canceled
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(organization_id, invoice_number)
);
CREATE INDEX idx_invoices_org ON invoices(organization_id);
CREATE INDEX idx_invoices_client ON invoices(client_id);

-- =====================================================
-- 14. INVOICE_ITEMS - بنود الفاتورة
-- =====================================================
CREATE TABLE invoice_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    description TEXT NOT NULL,
    quantity NUMERIC(10,2) DEFAULT 1,
    unit_price NUMERIC(15,2) DEFAULT 0,
    total NUMERIC(15,2) DEFAULT 0
);
CREATE INDEX idx_invoice_items_invoice ON invoice_items(invoice_id);

-- =====================================================
-- 15. ACTIVITY_LOGS - سجل التعديلات
-- =====================================================
CREATE TABLE activity_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    entity_type VARCHAR(50) NOT NULL,  -- client / contract / payment / worker / invoice
    entity_id UUID NOT NULL,
    action VARCHAR(50) NOT NULL,       -- created / updated / deleted / completed
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_activity_org_date ON activity_logs(organization_id, created_at DESC);
CREATE INDEX idx_activity_entity ON activity_logs(entity_type, entity_id);

-- =====================================================
-- 16. AUTO-UPDATE updated_at TRIGGER
-- =====================================================
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_organizations BEFORE UPDATE ON organizations FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_users         BEFORE UPDATE ON users         FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_subscriptions BEFORE UPDATE ON subscriptions FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_clients       BEFORE UPDATE ON clients       FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_contracts     BEFORE UPDATE ON contracts     FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_workers       BEFORE UPDATE ON workers       FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- =====================================================
-- 17. FUNCTION: إنشاء بيانات افتراضية لكل org جديدة
-- =====================================================
CREATE OR REPLACE FUNCTION create_default_org_data(p_org_id UUID)
RETURNS VOID AS $$
BEGIN
  INSERT INTO worker_categories (organization_id, name, name_en, icon, is_default, sort_order) VALUES
    (p_org_id, 'سباكة',              'Plumbing',       '🔧', true,  1),
    (p_org_id, 'كهرباء',             'Electrical',     '⚡', true,  2),
    (p_org_id, 'محارة وجبس',         'Plastering',     '🏗️', true,  3),
    (p_org_id, 'نقاشة ودهانات',      'Painting',       '🎨', true,  4),
    (p_org_id, 'ديكور',              'Decor',          '🛋️', true,  5),
    (p_org_id, 'بلاط وسيراميك',      'Tiling',         '⬛', true,  6),
    (p_org_id, 'نجارة وأبواب',       'Carpentry',      '🚪', true,  7),
    (p_org_id, 'تكييف',              'AC & HVAC',      '❄️', true,  8),
    (p_org_id, 'حمامات سباحة ونوافير','Swimming Pools', '🏊', true,  9),
    (p_org_id, 'حدائق',              'Gardens',        '🌿', true, 10),
    (p_org_id, 'نقل',                'Transport',      '🚛', true, 11),
    (p_org_id, 'تغليف',              'Packaging',      '📦', true, 12);
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- DONE ✅
-- =====================================================
