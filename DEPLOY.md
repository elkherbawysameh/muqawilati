# 🚀 دليل نشر مقاولاتي على Hostinger VPS
## خطوة بخطوة من الصفر

---

## 📋 المتطلبات
- VPS يعمل Ubuntu 22.04 (على Hostinger)
- دومين موجّه لـ IP السيرفر
- بيانات SSH (IP + username + password)

---

## ① الاتصال بالسيرفر

افتح **Terminal** على جهازك واكتب:
```bash
ssh root@YOUR_SERVER_IP
# أدخل كلمة المرور لما يطلبها
```

---

## ② تحديث النظام

```bash
apt update && apt upgrade -y
```

---

## ③ تثبيت Node.js 20

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
node -v   # يجب أن يظهر v20.x.x
```

---

## ④ تثبيت PostgreSQL

```bash
apt install postgresql postgresql-contrib -y
systemctl start postgresql
systemctl enable postgresql
```

### إنشاء قاعدة البيانات والمستخدم:
```bash
sudo -u postgres psql
```
ثم داخل psql:
```sql
CREATE DATABASE muqawilati;
CREATE USER muqawilati_user WITH ENCRYPTED PASSWORD 'ضع_كلمة_مرور_قوية_هنا';
GRANT ALL PRIVILEGES ON DATABASE muqawilati TO muqawilati_user;
\c muqawilati
GRANT ALL ON SCHEMA public TO muqawilati_user;
\q
```

---

## ⑤ رفع ملفات التطبيق

### من جهازك (Windows) - افتح PowerShell أو CMD:
```bash
# ضغط المجلد أولاً (بدون node_modules)
# ثم ارفعه
scp -r "C:\Users\Sameh\Documents\Claude\Projects\Finishing and constructions\muqawilati" root@YOUR_SERVER_IP:/var/www/
```

**أو استخدم FileZilla:**
1. Host: `YOUR_SERVER_IP` | Username: `root` | Protocol: `SFTP`
2. ارفع مجلد `muqawilati` إلى `/var/www/`

---

## ⑥ إعداد ملف .env

```bash
cd /var/www/muqawilati
cp .env.example .env
nano .env
```

عدّل القيم:
```
DATABASE_URL=postgresql://muqawilati_user:كلمة_المرور@localhost:5432/muqawilati
JWT_SECRET=اكتب_هنا_نص_عشوائي_طويل_جداً_مثلاً_50_حرف
NODE_ENV=production
PORT=3000
```
احفظ بـ `Ctrl+O` ثم `Ctrl+X`

---

## ⑦ تشغيل السكيمة على قاعدة البيانات

```bash
psql -U muqawilati_user -d muqawilati -h localhost -f /var/www/muqawilati/schema.sql
# أدخل كلمة المرور لما يطلبها
```

---

## ⑧ تثبيت الـ Packages

```bash
cd /var/www/muqawilati
npm install --production
```

---

## ⑨ تثبيت PM2 وتشغيل التطبيق

```bash
npm install -g pm2

# إنشاء مجلد اللوجات
mkdir -p /var/www/muqawilati/logs

# تشغيل التطبيق
pm2 start /var/www/muqawilati/ecosystem.config.js

# اجعله يشتغل تلقائياً عند إعادة تشغيل السيرفر
pm2 save
pm2 startup
# نفّذ الأمر اللي يظهر لك

# تأكد إنه شغّال
pm2 status
pm2 logs muqawilati --lines 20
```

---

## ⑩ تثبيت وإعداد Nginx

```bash
apt install nginx -y
systemctl start nginx
systemctl enable nginx
```

### إنشاء ملف الإعداد:
```bash
nano /etc/nginx/sites-available/muqawilati
```

الصق هذا (غيّر `YOUR_DOMAIN`):
```nginx
server {
    listen 80;
    server_name YOUR_DOMAIN www.YOUR_DOMAIN;
    client_max_body_size 20M;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    location /uploads/ {
        alias /var/www/muqawilati/public/uploads/;
        expires 30d;
    }
}
```
احفظ، ثم:
```bash
ln -s /etc/nginx/sites-available/muqawilati /etc/nginx/sites-enabled/
nginx -t          # اختبار الإعداد
systemctl reload nginx
```

---

## ⑪ HTTPS مجاني (Let's Encrypt)

```bash
apt install certbot python3-certbot-nginx -y
certbot --nginx -d YOUR_DOMAIN -d www.YOUR_DOMAIN
# اتبع التعليمات وأدخل إيميلك
```

التجديد التلقائي:
```bash
certbot renew --dry-run  # اختبار
```

---

## ✅ التحقق من نجاح الرفع

افتح المتصفح على: `https://YOUR_DOMAIN`

يجب أن تظهر صفحة تسجيل الدخول / إنشاء حساب.

---

## 🔧 أوامر مفيدة للإدارة

```bash
# مراقبة التطبيق
pm2 status
pm2 logs muqawilati
pm2 monit

# إعادة التشغيل
pm2 restart muqawilati

# تحديث التطبيق (بعد رفع ملفات جديدة)
cd /var/www/muqawilati
npm install --production
pm2 restart muqawilati

# النسخ الاحتياطي لقاعدة البيانات
pg_dump -U muqawilati_user muqawilati > backup_$(date +%Y%m%d).sql

# مشاهدة لوجات Nginx
tail -f /var/log/nginx/error.log
```

---

## 🆘 مشاكل شائعة وحلولها

| المشكلة | الحل |
|---------|------|
| `Connection refused` | تأكد إن `pm2 status` يظهر `online` |
| `502 Bad Gateway` | تأكد إن التطبيق شغّال: `pm2 restart muqawilati` |
| `database error` | تأكد من بيانات `.env` وإن السكيمة اتعملت |
| صور مش بتظهر | تأكد من صلاحيات: `chmod -R 755 /var/www/muqawilati/public/uploads` |

---

## 📞 الدعم
أي مشكلة، ابعت الـ error message وهنحلها.
