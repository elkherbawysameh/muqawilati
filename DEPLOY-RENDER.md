# نشر مقاولاتي على Render.com + Supabase (مجاناً)

---

## الخطوات بالترتيب

### ① إضافة جداول المراحل في Supabase

1. افتح [supabase.com](https://supabase.com) → مشروعك
2. من القائمة الجانبية: **SQL Editor**
3. اضغط **New query**
4. افتح ملف `migrate-phases-supabase.sql` من جهازك وانسخ محتواه
5. الصقه في المحرر واضغط **Run**
6. يجب أن تظهر: ✅ Success

---

### ② احصل على رابط قاعدة البيانات من Supabase

1. في Supabase → **Settings** (أيقونة الترس)
2. من القائمة: **Database**
3. انزل لـ **Connection string**
4. اختر **URI**
5. انسخ الرابط — يبدأ بـ `postgresql://postgres:...`
6. **استبدل `[YOUR-PASSWORD]`** بكلمة المرور اللي اخترتها وقت إنشاء المشروع

> 💡 احتفظ بهذا الرابط، هتحتاجه في الخطوة ⑤

---

### ③ رفع الكود على GitHub

1. افتح [github.com](https://github.com) وأنشئ حساب لو مش عندك
2. اضغط **+** ثم **New repository**
3. اسمّيه `muqawilati` واختر **Private** ثم **Create repository**
4. افتح **Command Prompt** على جهازك في مجلد المشروع:

```
cd "C:\Users\Sameh\Documents\Claude\Projects\Finishing and constructions\muqawilati"
```

5. نفّذ هذه الأوامر بالترتيب:

```bash
git init
echo "node_modules/" > .gitignore
echo ".env" >> .gitignore
git add .
git commit -m "first commit"
git branch -M main
git remote add origin https://github.com/USERNAME/muqawilati.git
git push -u origin main
```

> 🔁 استبدل `USERNAME` باسم مستخدمك على GitHub

---

### ④ إنشاء تطبيق على Render.com

1. افتح [render.com](https://render.com) وسجّل دخول (أو أنشئ حساب مجاناً)
2. اضغط **New +** → **Web Service**
3. اختر **Connect a repository** → وصّل حسابك على GitHub
4. اختر مستودع `muqawilati`
5. اضبط هذه الإعدادات:

| الحقل | القيمة |
|-------|--------|
| Name | muqawilati |
| Region | Frankfurt (EU Central) — أقرب لمصر |
| Branch | main |
| Runtime | Node |
| Build Command | `npm install` |
| Start Command | `node server.js` |
| Instance Type | **Free** |

6. اضغط **Create Web Service** (لا تضغط Deploy بعد)

---

### ⑤ إضافة متغيرات البيئة (Environment Variables)

بعد إنشاء التطبيق، روح **Environment** tab وأضف:

| Key | Value |
|-----|-------|
| `DATABASE_URL` | رابط Supabase اللي نسخته في الخطوة ② |
| `JWT_SECRET` | أي نص طويل عشوائي (مثلاً: `MuqawilatiSecret2024!@#XYZ`) |
| `NODE_ENV` | `production` |

اضغط **Save Changes**

---

### ⑥ Deploy! 🚀

1. روح تبويب **Deploys**
2. اضغط **Deploy latest commit**
3. انتظر دقيقتين وشوف اللوجات
4. لما تشوف: `🚀 مقاولاتي يعمل على: http://localhost:3000` — يبقى شغّال ✅
5. اضغط على رابط التطبيق (في الأعلى بيبدأ بـ `https://muqawilati.onrender.com`)

---

## 🔧 أوامر مفيدة لو في مشاكل

```bash
# لو node_modules مش بتتعرف
npm install

# اختبار الاتصال بقاعدة البيانات محلياً
node -e "require('dotenv').config(); const {Pool}=require('pg'); new Pool({connectionString:process.env.DATABASE_URL,ssl:{rejectUnauthorized:false}}).query('SELECT 1').then(()=>console.log('✅ OK')).catch(e=>console.error('❌',e.message))"
```

---

## 🆘 مشاكل شائعة

| المشكلة | الحل |
|---------|------|
| `ECONNREFUSED` | تأكد إن `DATABASE_URL` صح في Render Environment |
| `SSL required` | تأكد إن `ssl: {rejectUnauthorized: false}` موجودة في server.js (موجودة بالفعل ✅) |
| `relation "clients" does not exist` | شغّل `schema.sql` في Supabase أولاً |
| `relation "client_phases" does not exist` | شغّل `migrate-phases-supabase.sql` في Supabase |
| التطبيق بيفصل بعد 15 دقيقة | طبيعي في الخطة المجانية، بيصحى تاني لما حد يفتحه |

---

## 📝 ملاحظات مهمة

- **الخطة المجانية في Render**: التطبيق بينام بعد 15 دقيقة بدون استخدام، وبيصحى في 30-60 ثانية أول ما حد يفتحه
- **Supabase المجاني**: 500MB تخزين، كافي جداً للبداية
- **لو عايز التطبيق يوصحى دايماً**: في Render في خطة $7/شهر أو اعمل cron job مجاني يعمل ping كل 14 دقيقة
