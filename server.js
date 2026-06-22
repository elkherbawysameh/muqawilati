require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const { randomUUID } = require('crypto');

const app = express();
const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'change_this_secret_in_production';

// ─── DB POOL ──────────────────────────────────────────────────────────────────
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});
const db = {
  query: async (text, params) => { const r = await pool.query(text, params); return r.rows; },
  one:   async (text, params) => { const r = await pool.query(text, params); return r.rows[0] || null; },
  all:   async (text, params) => { const r = await pool.query(text, params); return r.rows; },
};

// ─── MIDDLEWARE ───────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));
app.use('/uploads', express.static(path.join(__dirname, 'public', 'uploads')));

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, 'public', 'uploads');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) =>
    cb(null, Date.now() + '-' + Math.round(Math.random() * 1e6) + path.extname(file.originalname))
});
const upload = multer({ storage, limits: { fileSize: 10 * 1024 * 1024 } });

const authenticate = async (req, res, next) => {
  const token = (req.headers.authorization || '').replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'Unauthorized' });
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    req.orgId = decoded.organization_id;
    next();
  } catch {
    res.status(401).json({ error: 'Invalid token' });
  }
};

// ─── HELPERS ──────────────────────────────────────────────────────────────────
const PHASES = ['design', 'study', 'execution'];
const PHASE_LABELS = { design: 'تصميم', study: 'دراسة وتسعير', execution: 'تنفيذ' };

async function createDefaultOrgData(client, orgId) {
  const categories = [
    ['نجار','Carpenter','🪚',1], ['سباك','Plumber','🔧',2],
    ['كهربائي','Electrician','⚡',3], ['بياض','Plasterer','🪣',4],
    ['سيراميك','Tiler','🏗️',5], ['نقاش','Painter','🎨',6],
    ['حداد','Blacksmith','⚒️',7], ['ألومنيوم','Aluminum Worker','🪟',8],
    ['جبس','Gypsum','🧱',9], ['عمال','General Workers','👷',10],
    ['مقاول','Contractor','🏗️',11], ['أخرى','Other','🔩',12],
  ];
  for (const [name, name_en, icon, sort_order] of categories) {
    await client.query(
      'INSERT INTO worker_categories(id,organization_id,name,name_en,icon,sort_order) VALUES($1,$2,$3,$4,$5,$6)',
      [randomUUID(), orgId, name, name_en, icon, sort_order]
    );
  }
}

async function getOrCreateContract(clientId, orgId) {
  let contract = await db.one(
    `SELECT id FROM contracts WHERE client_id=$1 AND organization_id=$2 AND status='active' ORDER BY created_at LIMIT 1`,
    [clientId, orgId]
  );
  if (!contract) {
    const c = await db.one('SELECT name FROM clients WHERE id=$1', [clientId]);
    const id = randomUUID();
    await pool.query(
      `INSERT INTO contracts(id,organization_id,client_id,title,status) VALUES($1,$2,$3,$4,'active')`,
      [id, orgId, clientId, `عقد ${c?.name || ''}`]
    );
    contract = { id };
  }
  return contract.id;
}

async function nextInvoiceNumber(orgId) {
  const org = await db.one('SELECT invoice_prefix FROM organizations WHERE id=$1', [orgId]);
  const prefix = org?.invoice_prefix || 'INV';
  const last = await db.one(
    'SELECT invoice_number FROM invoices WHERE organization_id=$1 ORDER BY created_at DESC LIMIT 1', [orgId]
  );
  if (!last) return `${prefix}-0001`;
  const num = parseInt(last.invoice_number.split('-').pop()) + 1;
  return `${prefix}-${String(num).padStart(4, '0')}`;
}

function log(orgId, userId, entityType, entityId, action, details) {
  pool.query(
    'INSERT INTO activity_logs(id,organization_id,user_id,entity_type,entity_id,action,details) VALUES($1,$2,$3,$4,$5,$6,$7)',
    [randomUUID(), orgId, userId, entityType, entityId, action, details ? JSON.stringify(details) : null]
  ).catch(() => {});
}

// ─── AUTH ─────────────────────────────────────────────────────────────────────
app.post('/api/auth/register', async (req, res) => {
  const { org_name, email, password, full_name } = req.body;
  if (!org_name || !email || !password) return res.status(400).json({ error: 'جميع الحقول مطلوبة' });
  if (await db.one('SELECT id FROM users WHERE email=$1', [email]))
    return res.status(400).json({ error: 'الإيميل مسجل مسبقاً' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const orgId = randomUUID();
    await client.query('INSERT INTO organizations(id,name) VALUES($1,$2)', [orgId, org_name]);
    await createDefaultOrgData(client, orgId);
    const hash = await bcrypt.hash(password, 12);
    const userId = randomUUID();
    await client.query(
      `INSERT INTO users(id,organization_id,email,password_hash,full_name,role,is_owner,is_active)
       VALUES($1,$2,$3,$4,$5,'owner',true,true)`,
      [userId, orgId, email.toLowerCase(), hash, full_name || '']
    );
    const pr = await client.query('SELECT id FROM plans WHERE price=0 LIMIT 1');
    await client.query(
      `INSERT INTO subscriptions(id,organization_id,plan_id,account_type,status,current_period_start,current_period_end)
       VALUES($1,$2,$3,'paid','active',now(),now() + interval '30 days')`,
      [randomUUID(), orgId, pr.rows[0]?.id || null]
    );
    await client.query('COMMIT');
    const token = jwt.sign(
      { user_id: userId, organization_id: orgId, role: 'owner', is_owner: true },
      JWT_SECRET, { expiresIn: '30d' }
    );
    res.json({ token, user: { id: userId, email: email.toLowerCase(), full_name: full_name||'', role: 'owner', is_owner: true, organization_id: orgId, org_name } });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    res.status(500).json({ error: 'فشل التسجيل' });
  } finally {
    client.release();
  }
});

app.post('/api/auth/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'أدخل الإيميل وكلمة المرور' });
  const user = await db.one(
    `SELECT u.*, o.name as org_name FROM users u JOIN organizations o ON o.id=u.organization_id
     WHERE u.email=$1 AND u.is_active=true`, [email.toLowerCase()]
  );
  if (!user || !(await bcrypt.compare(password, user.password_hash)))
    return res.status(401).json({ error: 'بيانات خاطئة' });
  await pool.query('UPDATE users SET last_login_at=now() WHERE id=$1', [user.id]);
  const token = jwt.sign(
    { user_id: user.id, organization_id: user.organization_id, role: user.role, is_owner: user.is_owner },
    JWT_SECRET, { expiresIn: '30d' }
  );
  res.json({ token, user: { id: user.id, email: user.email, full_name: user.full_name, role: user.role,
    is_owner: user.is_owner, organization_id: user.organization_id, org_name: user.org_name } });
});

app.get('/api/auth/me', authenticate, async (req, res) => {
  const user = await db.one(
    `SELECT u.id,u.email,u.full_name,u.role,u.is_owner,u.organization_id,
            o.name as org_name,o.phone,o.address,o.invoice_prefix,o.tax_rate
     FROM users u JOIN organizations o ON o.id=u.organization_id WHERE u.id=$1`,
    [req.user.user_id]
  );
  res.json(user);
});

// ─── DASHBOARD ────────────────────────────────────────────────────────────────
app.get('/api/dashboard', authenticate, async (req, res) => {
  const oid = req.orgId;
  const [tc, tw, ti, tcv, tr, piv, rc] = await Promise.all([
    db.one('SELECT COUNT(*) as c FROM clients WHERE organization_id=$1', [oid]),
    db.one('SELECT COUNT(*) as c FROM workers WHERE organization_id=$1', [oid]),
    db.one('SELECT COUNT(*) as c FROM invoices WHERE organization_id=$1', [oid]),
    db.one('SELECT COALESCE(SUM(unit_price*quantity),0) as s FROM contract_items WHERE organization_id=$1', [oid]),
    db.one("SELECT COALESCE(SUM(amount),0) as s FROM contract_payments WHERE organization_id=$1 AND type='received'", [oid]),
    db.one("SELECT COALESCE(SUM(unit_price*quantity),0) as s FROM contract_items WHERE organization_id=$1 AND status='done'", [oid]),
    db.all(`SELECT c.id,c.name,c.phone,c.location,
      COALESCE((SELECT SUM(ci.unit_price*ci.quantity) FROM contracts ct JOIN contract_items ci ON ci.contract_id=ct.id WHERE ct.client_id=c.id AND ct.organization_id=$1),0) as total_contract,
      COALESCE((SELECT SUM(cp.amount) FROM contracts ct JOIN contract_payments cp ON cp.contract_id=ct.id WHERE ct.client_id=c.id AND ct.organization_id=$1),0) as total_received,
      (SELECT COUNT(*) FROM contracts ct JOIN contract_items ci ON ci.contract_id=ct.id WHERE ct.client_id=c.id AND ct.organization_id=$1) as total_items,
      (SELECT COUNT(*) FROM contracts ct JOIN contract_items ci ON ci.contract_id=ct.id WHERE ct.client_id=c.id AND ct.organization_id=$1 AND ci.status='done') as done_items
     FROM clients c WHERE c.organization_id=$1 ORDER BY c.created_at DESC LIMIT 5`, [oid]),
  ]);
  res.json({
    total_clients: parseInt(tc.c), total_workers: parseInt(tw.c),
    total_invoices: parseInt(ti.c), total_contract_value: parseFloat(tcv.s),
    total_received: parseFloat(tr.s), pending_items_value: parseFloat(piv.s),
    recent_clients: rc.map(c => ({
      ...c, total_contract: parseFloat(c.total_contract), total_received: parseFloat(c.total_received),
      total_items: parseInt(c.total_items), done_items: parseInt(c.done_items)
    }))
  });
});

// ─── CLIENTS ──────────────────────────────────────────────────────────────────
app.get('/api/clients', authenticate, async (req, res) => {
  const clients = await db.all(
    `SELECT c.*,
       COALESCE((SELECT SUM(ci.unit_price*ci.quantity) FROM contracts ct JOIN contract_items ci ON ci.contract_id=ct.id WHERE ct.client_id=c.id),0) as total_contract,
       COALESCE((SELECT SUM(cp.amount) FROM contracts ct JOIN contract_payments cp ON cp.contract_id=ct.id WHERE ct.client_id=c.id),0) as total_received,
       (SELECT COUNT(*) FROM contracts ct JOIN contract_items ci ON ci.contract_id=ct.id WHERE ct.client_id=c.id) as total_items,
       (SELECT COUNT(*) FROM contracts ct JOIN contract_items ci ON ci.contract_id=ct.id WHERE ct.client_id=c.id AND ci.status='done') as done_items
     FROM clients c WHERE c.organization_id=$1 ORDER BY c.created_at DESC`, [req.orgId]
  );
  res.json(clients.map(c => ({
    ...c, total_contract: parseFloat(c.total_contract), total_received: parseFloat(c.total_received),
    total_items: parseInt(c.total_items), done_items: parseInt(c.done_items)
  })));
});

app.get('/api/clients/:id', authenticate, async (req, res) => {
  const c = await db.one('SELECT * FROM clients WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  if (!c) return res.status(404).json({ error: 'Not found' });
  const contractId = await getOrCreateContract(c.id, req.orgId);
  const [items, payments, photos, stats] = await Promise.all([
    db.all('SELECT * FROM contract_items WHERE contract_id=$1 ORDER BY sort_order,created_at', [contractId]),
    db.all('SELECT * FROM contract_payments WHERE contract_id=$1 ORDER BY payment_date DESC', [contractId]),
    db.all('SELECT * FROM contract_attachments WHERE contract_id=$1 ORDER BY created_at DESC', [contractId]),
    db.one(
      `SELECT COALESCE(SUM(ci.unit_price*ci.quantity),0) as total_contract,
              COALESCE((SELECT SUM(amount) FROM contract_payments WHERE contract_id=$1),0) as total_received,
              COUNT(*) as total_items,
              COUNT(*) FILTER (WHERE ci.status='done') as done_items
       FROM contract_items ci WHERE ci.contract_id=$1`, [contractId]
    ),
  ]);
  res.json({
    ...c, contract_id: contractId,
    total_contract: parseFloat(stats.total_contract), total_received: parseFloat(stats.total_received),
    total_items: parseInt(stats.total_items), done_items: parseInt(stats.done_items),
    items, payments, photos,
  });
});

app.post('/api/clients', authenticate, async (req, res) => {
  const { name, phone, email, location, notes, payment_method, advance_percentage } = req.body;
  if (!name) return res.status(400).json({ error: 'Name required' });
  const id = randomUUID();
  await pool.query(
    'INSERT INTO clients(id,organization_id,name,phone,email,location,notes,payment_method,advance_percentage) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)',
    [id, req.orgId, name, phone||'', email||'', location||'', notes||'', payment_method||'installments', advance_percentage||0]
  );
  log(req.orgId, req.user.user_id, 'client', id, 'created', { name });
  res.json({ id });
});

app.put('/api/clients/:id', authenticate, async (req, res) => {
  const { name, phone, email, location, notes, payment_method, advance_percentage } = req.body;
  await pool.query(
    'UPDATE clients SET name=$1,phone=$2,email=$3,location=$4,notes=$5,payment_method=$6,advance_percentage=$7,updated_at=now() WHERE id=$8 AND organization_id=$9',
    [name, phone||'', email||'', location||'', notes||'', payment_method||'installments', advance_percentage||0, req.params.id, req.orgId]
  );
  res.json({ message: 'Updated' });
});

app.delete('/api/clients/:id', authenticate, async (req, res) => {
  const contracts = await db.all('SELECT id FROM contracts WHERE client_id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  for (const ct of contracts) {
    const photos = await db.all('SELECT filename FROM contract_attachments WHERE contract_id=$1', [ct.id]);
    photos.forEach(p => { const fp = path.join(__dirname,'public','uploads',p.filename); if(fs.existsSync(fp)) fs.unlinkSync(fp); });
  }
  await pool.query('DELETE FROM clients WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  res.json({ message: 'Deleted' });
});

// ─── CONTRACT ITEMS ───────────────────────────────────────────────────────────
app.post('/api/clients/:id/items', authenticate, async (req, res) => {
  const contractId = await getOrCreateContract(req.params.id, req.orgId);
  const { description, unit, quantity, unit_price, phase } = req.body;
  const id = randomUUID();
  await pool.query(
    'INSERT INTO contract_items(id,contract_id,organization_id,description,unit,quantity,unit_price,phase) VALUES($1,$2,$3,$4,$5,$6,$7,$8)',
    [id, contractId, req.orgId, description, unit||'بند', quantity||1, unit_price||0, PHASES.includes(phase) ? phase : null]
  );
  res.json({ id });
});

app.put('/api/items/:id', authenticate, async (req, res) => {
  const item = await db.one('SELECT * FROM contract_items WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  if (!item) return res.status(404).json({ error: 'Not found' });
  const { description, unit, quantity, unit_price, status, phase } = req.body;
  const newStatus = status !== undefined ? status : item.status;
  const completedAt = newStatus === 'done' && item.status !== 'done' ? new Date() : item.completed_at;
  const newPhase = phase !== undefined ? (PHASES.includes(phase) ? phase : null) : item.phase;
  await pool.query(
    'UPDATE contract_items SET description=$1,unit=$2,quantity=$3,unit_price=$4,status=$5,completed_at=$6,phase=$7 WHERE id=$8',
    [description||item.description, unit||item.unit, quantity??item.quantity, unit_price??item.unit_price, newStatus, completedAt, newPhase, req.params.id]
  );
  res.json({ message: 'Updated' });
});

app.delete('/api/items/:id', authenticate, async (req, res) => {
  await pool.query('DELETE FROM contract_items WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  res.json({ message: 'Deleted' });
});

// ─── PAYMENTS ─────────────────────────────────────────────────────────────────
app.post('/api/clients/:id/payments', authenticate, async (req, res) => {
  const contractId = await getOrCreateContract(req.params.id, req.orgId);
  const { amount, payment_date, notes, type } = req.body;
  const id = randomUUID();
  await pool.query(
    'INSERT INTO contract_payments(id,contract_id,organization_id,amount,payment_date,notes,type) VALUES($1,$2,$3,$4,$5,$6,$7)',
    [id, contractId, req.orgId, amount, payment_date||new Date().toISOString().split('T')[0], notes||'', type||'received']
  );
  res.json({ id });
});

app.put('/api/payments/:id', authenticate, async (req, res) => {
  const { amount, payment_date, notes } = req.body;
  await pool.query(
    'UPDATE contract_payments SET amount=$1, payment_date=$2, notes=$3 WHERE id=$4 AND organization_id=$5',
    [amount, payment_date, notes || '', req.params.id, req.orgId]
  );
  res.json({ message: 'Updated' });
});

app.delete('/api/payments/:id', authenticate, async (req, res) => {
  await pool.query('DELETE FROM contract_payments WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  res.json({ message: 'Deleted' });
});

// ─── CLIENT PHOTOS ────────────────────────────────────────────────────────────
app.post('/api/clients/:id/photos', authenticate, upload.array('photos', 20), async (req, res) => {
  const contractId = await getOrCreateContract(req.params.id, req.orgId);
  const ids = [];
  for (const f of req.files || []) {
    const id = randomUUID();
    await pool.query(
      'INSERT INTO contract_attachments(id,contract_id,organization_id,filename,file_url,file_type,caption,uploaded_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8)',
      [id, contractId, req.orgId, f.filename, `/uploads/${f.filename}`, req.body.type||'photo', req.body.caption||'', req.user.user_id]
    );
    ids.push(id);
  }
  res.json({ ids });
});

app.delete('/api/photos/:id', authenticate, async (req, res) => {
  const photo = await db.one('SELECT * FROM contract_attachments WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  if (photo) {
    const fp = path.join(__dirname,'public','uploads',photo.filename);
    if (fs.existsSync(fp)) fs.unlinkSync(fp);
    await pool.query('DELETE FROM contract_attachments WHERE id=$1', [req.params.id]);
  }
  res.json({ message: 'Deleted' });
});

// ─── WORKER CATEGORIES ────────────────────────────────────────────────────────
app.get('/api/categories', authenticate, async (req, res) => {
  const cats = await db.all(
    `SELECT wc.*, COUNT(w.id) as worker_count FROM worker_categories wc
     LEFT JOIN workers w ON w.category_id=wc.id WHERE wc.organization_id=$1
     GROUP BY wc.id ORDER BY wc.sort_order,wc.name`, [req.orgId]
  );
  res.json(cats.map(c => ({ ...c, worker_count: parseInt(c.worker_count) })));
});

app.post('/api/categories', authenticate, async (req, res) => {
  const { name, name_en, icon } = req.body;
  const id = randomUUID();
  await pool.query('INSERT INTO worker_categories(id,organization_id,name,name_en,icon) VALUES($1,$2,$3,$4,$5)',
    [id, req.orgId, name, name_en||'', icon||'🔧']);
  res.json({ id });
});

app.put('/api/categories/:id', authenticate, async (req, res) => {
  const { name, name_en, icon } = req.body;
  await pool.query('UPDATE worker_categories SET name=$1,name_en=$2,icon=$3 WHERE id=$4 AND organization_id=$5',
    [name, name_en||'', icon||'🔧', req.params.id, req.orgId]);
  res.json({ message: 'Updated' });
});

app.delete('/api/categories/:id', authenticate, async (req, res) => {
  await pool.query('UPDATE workers SET category_id=NULL WHERE category_id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  await pool.query('DELETE FROM worker_categories WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  res.json({ message: 'Deleted' });
});

// ─── WORKERS ──────────────────────────────────────────────────────────────────
app.get('/api/workers', authenticate, async (req, res) => {
  const { category_id } = req.query;
  let q = `SELECT w.*, wc.name as category_name, wc.icon as category_icon
           FROM workers w LEFT JOIN worker_categories wc ON wc.id=w.category_id WHERE w.organization_id=$1`;
  const params = [req.orgId];
  if (category_id) { q += ` AND w.category_id=$2`; params.push(category_id); }
  res.json(await db.all(q + ' ORDER BY w.name', params));
});

app.get('/api/workers/:id', authenticate, async (req, res) => {
  const w = await db.one(
    `SELECT w.*, wc.name as category_name, wc.icon as category_icon
     FROM workers w LEFT JOIN worker_categories wc ON wc.id=w.category_id
     WHERE w.id=$1 AND w.organization_id=$2`, [req.params.id, req.orgId]
  );
  if (!w) return res.status(404).json({ error: 'Not found' });
  w.photos = await db.all('SELECT * FROM worker_photos WHERE worker_id=$1 ORDER BY uploaded_at DESC', [req.params.id]);
  res.json(w);
});

app.post('/api/workers', authenticate, async (req, res) => {
  const { name, phone, address, notes, category_id } = req.body;
  const id = randomUUID();
  await pool.query(
    'INSERT INTO workers(id,organization_id,name,phone,address,notes,category_id) VALUES($1,$2,$3,$4,$5,$6,$7)',
    [id, req.orgId, name, phone||'', address||'', notes||'', category_id||null]
  );
  res.json({ id });
});

app.put('/api/workers/:id', authenticate, async (req, res) => {
  const { name, phone, address, notes, category_id } = req.body;
  await pool.query(
    'UPDATE workers SET name=$1,phone=$2,address=$3,notes=$4,category_id=$5,updated_at=now() WHERE id=$6 AND organization_id=$7',
    [name, phone||'', address||'', notes||'', category_id||null, req.params.id, req.orgId]
  );
  res.json({ message: 'Updated' });
});

app.delete('/api/workers/:id', authenticate, async (req, res) => {
  const photos = await db.all('SELECT filename FROM worker_photos WHERE worker_id=$1', [req.params.id]);
  photos.forEach(p => { const fp = path.join(__dirname,'public','uploads',p.filename); if(fs.existsSync(fp)) fs.unlinkSync(fp); });
  await pool.query('DELETE FROM workers WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  res.json({ message: 'Deleted' });
});

app.post('/api/workers/:id/photos', authenticate, upload.array('photos', 20), async (req, res) => {
  for (const f of req.files || [])
    await pool.query('INSERT INTO worker_photos(id,worker_id,organization_id,filename,caption) VALUES($1,$2,$3,$4,$5)',
      [randomUUID(), req.params.id, req.orgId, f.filename, req.body.caption||'']);
  res.json({ message: 'Uploaded' });
});

app.delete('/api/worker-photos/:id', authenticate, async (req, res) => {
  const photo = await db.one('SELECT * FROM worker_photos WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  if (photo) {
    const fp = path.join(__dirname,'public','uploads',photo.filename);
    if (fs.existsSync(fp)) fs.unlinkSync(fp);
    await pool.query('DELETE FROM worker_photos WHERE id=$1', [req.params.id]);
  }
  res.json({ message: 'Deleted' });
});

// ─── INVOICES ─────────────────────────────────────────────────────────────────
app.get('/api/invoices', authenticate, async (req, res) => {
  const { client_id } = req.query;
  let q = `SELECT i.*, c.name as client_name FROM invoices i LEFT JOIN clients c ON c.id=i.client_id WHERE i.organization_id=$1`;
  const params = [req.orgId];
  if (client_id) { q += ` AND i.client_id=$2`; params.push(client_id); }
  res.json(await db.all(q + ' ORDER BY i.created_at DESC', params));
});

app.get('/api/invoices/:id', authenticate, async (req, res) => {
  const inv = await db.one(
    `SELECT i.*,c.name as client_name,c.phone as client_phone,c.location as client_location,
            o.name as company_name,o.phone as company_phone,o.address as company_address
     FROM invoices i LEFT JOIN clients c ON c.id=i.client_id
     JOIN organizations o ON o.id=i.organization_id WHERE i.id=$1 AND i.organization_id=$2`,
    [req.params.id, req.orgId]
  );
  if (!inv) return res.status(404).json({ error: 'Not found' });
  inv.items = await db.all('SELECT * FROM invoice_items WHERE invoice_id=$1', [req.params.id]);
  res.json(inv);
});

app.post('/api/invoices', authenticate, async (req, res) => {
  const { client_id, items, tax_rate, notes, due_date } = req.body;
  const invNum = await nextInvoiceNumber(req.orgId);
  const taxR = parseFloat(tax_rate)||0;
  const subtotal = (items||[]).reduce((s,it) => s + (it.quantity||1)*(it.unit_price||0), 0);
  const taxAmt = subtotal * taxR / 100;
  const invId = randomUUID();
  await pool.query(
    `INSERT INTO invoices(id,organization_id,client_id,invoice_number,issue_date,due_date,subtotal,tax_rate,tax_amount,total,status,notes)
     VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'issued',$11)`,
    [invId, req.orgId, client_id||null, invNum, new Date().toISOString().split('T')[0], due_date||null, subtotal, taxR, taxAmt, subtotal+taxAmt, notes||'']
  );
  for (const it of items||[])
    await pool.query('INSERT INTO invoice_items(id,invoice_id,description,quantity,unit_price,total) VALUES($1,$2,$3,$4,$5,$6)',
      [randomUUID(), invId, it.description, it.quantity||1, it.unit_price||0, (it.quantity||1)*(it.unit_price||0)]);
  res.json({ id: invId, invoice_number: invNum });
});

app.delete('/api/invoices/:id', authenticate, async (req, res) => {
  await pool.query('DELETE FROM invoices WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  res.json({ message: 'Deleted' });
});

// ─── CLIENT PHASES ────────────────────────────────────────────────────────────
app.get('/api/clients/:id/phases', authenticate, async (req, res) => {
  if (!await db.one('SELECT id FROM clients WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]))
    return res.status(404).json({ error: 'Not found' });
  const rows = await db.all(
    `SELECT * FROM client_phases WHERE client_id=$1 AND organization_id=$2
     ORDER BY CASE phase WHEN 'design' THEN 1 WHEN 'study' THEN 2 WHEN 'execution' THEN 3 END`,
    [req.params.id, req.orgId]
  );
  const phaseMap = {};
  rows.forEach(r => { phaseMap[r.phase] = r; });
  const result = PHASES.map(p => phaseMap[p] || { id: null, client_id: req.params.id, phase: p, status: 'not_started', started_at: null, completed_at: null, notes: '' });
  const contractId = await getOrCreateContract(req.params.id, req.orgId);
  const itemStats = await db.all(
    `SELECT phase, COUNT(*) as total_items, SUM(unit_price*quantity) as subtotal,
            COUNT(*) FILTER (WHERE status='done') as done_items
     FROM contract_items WHERE contract_id=$1 GROUP BY phase`, [contractId]
  );
  const statsMap = {};
  itemStats.forEach(s => { statsMap[s.phase] = s; });
  result.forEach(p => {
    const s = statsMap[p.phase] || {};
    p.total_items = parseInt(s.total_items || 0);
    p.done_items  = parseInt(s.done_items || 0);
    p.subtotal    = parseFloat(s.subtotal || 0);
  });
  res.json(result);
});

app.post('/api/clients/:id/phases/activate', authenticate, async (req, res) => {
  const { phase, notes } = req.body;
  if (!PHASES.includes(phase)) return res.status(400).json({ error: 'مرحلة غير صحيحة' });
  if (!await db.one('SELECT id FROM clients WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]))
    return res.status(404).json({ error: 'Not found' });
  const existing = await db.one('SELECT * FROM client_phases WHERE client_id=$1 AND phase=$2', [req.params.id, phase]);
  if (existing) {
    await pool.query(
      `UPDATE client_phases SET status='active',started_at=COALESCE(started_at,now()),notes=$1,updated_at=now() WHERE id=$2`,
      [notes || existing.notes, existing.id]
    );
    return res.json({ id: existing.id, message: 'تم تفعيل المرحلة' });
  }
  const id = randomUUID();
  await pool.query(
    `INSERT INTO client_phases(id,client_id,organization_id,phase,status,started_at,notes) VALUES($1,$2,$3,$4,'active',now(),$5)`,
    [id, req.params.id, req.orgId, phase, notes || '']
  );
  log(req.orgId, req.user.user_id, 'phase', id, 'activated', { phase });
  res.json({ id, message: 'تم تفعيل المرحلة' });
});

app.put('/api/client-phases/:id', authenticate, async (req, res) => {
  const { status, notes } = req.body;
  const ph = await db.one('SELECT * FROM client_phases WHERE id=$1 AND organization_id=$2', [req.params.id, req.orgId]);
  if (!ph) return res.status(404).json({ error: 'Not found' });
  const completedAt = status === 'completed' && ph.status !== 'completed' ? new Date() : ph.completed_at;
  await pool.query(
    'UPDATE client_phases SET status=$1,notes=$2,completed_at=$3,updated_at=now() WHERE id=$4',
    [status || ph.status, notes ?? ph.notes, completedAt, req.params.id]
  );
  res.json({ message: 'تم التحديث' });
});

// ─── ANALYTICS ────────────────────────────────────────────────────────────────
app.get('/api/analytics/phases', authenticate, async (req, res) => {
  const oid = req.orgId;
  const totalClients   = await db.one('SELECT COUNT(*) as c FROM clients WHERE organization_id=$1', [oid]);
  const phaseCounts    = await db.all(`SELECT phase,status,COUNT(*) as cnt FROM client_phases WHERE organization_id=$1 GROUP BY phase,status`, [oid]);
  const completedAll   = await db.one(`SELECT COUNT(*) as c FROM clients c WHERE c.organization_id=$1 AND (SELECT COUNT(*) FROM client_phases cp WHERE cp.client_id=c.id AND cp.status='completed')=3`, [oid]);
  const revenueByPhase = await db.all(`SELECT phase,SUM(unit_price*quantity) as total FROM contract_items WHERE organization_id=$1 AND phase IS NOT NULL GROUP BY phase`, [oid]);
  const unclassified   = await db.one(`SELECT COUNT(DISTINCT c.id) as c FROM clients c WHERE c.organization_id=$1 AND NOT EXISTS (SELECT 1 FROM client_phases cp WHERE cp.client_id=c.id)`, [oid]);
  const dropDesign     = await db.one(`SELECT COUNT(*) as c FROM client_phases WHERE organization_id=$1 AND phase='design' AND status='completed' AND client_id NOT IN (SELECT client_id FROM client_phases WHERE organization_id=$1 AND phase IN ('study','execution'))`, [oid]);
  const dropStudy      = await db.one(`SELECT COUNT(*) as c FROM client_phases WHERE organization_id=$1 AND phase='study' AND status='completed' AND client_id NOT IN (SELECT client_id FROM client_phases WHERE organization_id=$1 AND phase='execution')`, [oid]);

  const funnel = {};
  PHASES.forEach(p => { funnel[p] = { active: 0, completed: 0, skipped: 0 }; });
  phaseCounts.forEach(r => { if (funnel[r.phase] && r.status !== 'not_started') funnel[r.phase][r.status] = parseInt(r.cnt); });

  res.json({
    total_clients: parseInt(totalClients.c),
    completed_all_phases: parseInt(completedAll.c),
    unclassified_clients: parseInt(unclassified.c),
    funnel: PHASES.map(p => ({ phase: p, label: PHASE_LABELS[p], ...funnel[p], total: funnel[p].active + funnel[p].completed + funnel[p].skipped })),
    drop_off: { after_design: parseInt(dropDesign.c), after_study: parseInt(dropStudy.c) },
    revenue_by_phase: revenueByPhase.map(r => ({ phase: r.phase, label: PHASE_LABELS[r.phase]||r.phase, total: parseFloat(r.total||0) })),
  });
});

// ─── SETTINGS ─────────────────────────────────────────────────────────────────
app.get('/api/settings', authenticate, async (req, res) => {
  const org = await db.one('SELECT * FROM organizations WHERE id=$1', [req.orgId]);
  res.json({ company_name: org?.name||'', company_phone: org?.phone||'',
             company_address: org?.address||'', invoice_prefix: org?.invoice_prefix||'INV', tax_rate: org?.tax_rate||14 });
});

app.post('/api/settings', authenticate, async (req, res) => {
  const { company_name, company_phone, company_address, invoice_prefix, tax_rate } = req.body;
  await pool.query(
    'UPDATE organizations SET name=$1,phone=$2,address=$3,invoice_prefix=$4,tax_rate=$5,updated_at=now() WHERE id=$6',
    [company_name||'', company_phone||'', company_address||'', invoice_prefix||'INV', tax_rate||14, req.orgId]
  );
  res.json({ message: 'Saved' });
});

// ─── SERVE FRONTEND ───────────────────────────────────────────────────────────
app.get('*', (req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

// ─── START ────────────────────────────────────────────────────────────────────
pool.query('SELECT 1').then(() => {
  console.log('✅ PostgreSQL connected');
  app.listen(PORT, () => console.log(`🚀 مقاولاتي يعمل على: http://localhost:${PORT}`));
}).catch(err => { console.error('❌ DB connection failed:', err.message); process.exit(1); });
