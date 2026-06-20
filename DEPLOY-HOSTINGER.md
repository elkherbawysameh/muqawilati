# نشر مقاولاتي على Hostinger (Shared Hosting + MySQL)
## خطوة بخطوة — بدون VPS

---

## ✅ المتطلبات أولاً
قبل ما تبدأ، تأكد إن خطة Hostinger بتاعتك تدعم Node.js:
1. افتح hPanel → اضغط على موقعك → **Manage**
2. ابحث في القائمة عن **Node.js** أو **Advanced**
3. لو لقيت خيار Node.js ✅ → كمّل
4. لو مش موجود ❌ → محتاج ترقّي لخطة Business أو أعلى

---

## ① إنشاء قاعدة البيانات

**في hPanel:**
1. **Databases → MySQL Databases**
2. اضغط **Create a new database**
3. اكتب اسم (مثلاً: `muqawilati`) → اضغط **Create**
4. أنشئ مستخدم جديد (أو استخدم الموجود) وخليه يتحكم في قاعدة البيانات
5. **احتفظ بـ:**
   - Database name (عادة: `u123456_muqawilati`)
   - Username (عادة: `u123456_user`)
   - Password

---

## ② استيراد السكيمة (إنشاء الجداول)

**في hPanel:**
1. **phpMyAdmin** → افتح قاعدة بياناتك
2. اضغط تبويب **Import**
3. اضغط **Choose File** → اختر ملف `schema-mysql.sql` من جهازك
4. اضغط **Import** في الأسفل
5. يجب أن تظهر رسالة ✅ نجاح وتشوف الجداول في القائمة

---

## ③ رفع ملفات التطبيق

**في hPanel:**
1. **File Manager** → افتح مجلد `public_html` (أو اسم دومينك)
2. اضغط **Upload Files** → ارفع كل محتويات مجلد `muqawilati`
   - ❌ لا ترفع مجلد `node_modules` (كبير جداً)
   - ❌ لا ترفع ملف `.env`

**أو** استخدم FileZilla (SFTP):
- Host: دومينك أو IP
- Username/Password: بيانات Hostinger
- Remote: `/public_html/` أو `/domains/yourdomain/`

---

## ④ إنشاء ملف .env على السيرفر

**في File Manager:**
1. افتح مجلد التطبيق
2. اضغط **New File** → اكتب `.env`
3. اضغط **Edit** والصق هذا المحتوى:

```
DB_HOST=localhost
DB_USER=u123456_user
DB_PASSWORD=كلمة_المرور_اللي_اخترتها
DB_NAME=u123456_muqawilati
DB_PORT=3306
JWT_SECRET=aVeryLongRandomString2024MuqawilatiSecretKey!@#$%
NODE_ENV=production
PORT=3000
```

> **مهم:** استبدل `u123456` باليوزرنيم الفعلي الخاص بيك

---

## ⑤ تفعيل Node.js وتثبيت الـ Packages

**في hPanel → Node.js:**
1. اضغط **Create Application** أو **Setup**
2. اختر:
   - **Node.js Version:** 18 أو 20 (الأحدث المتاحة)
   - **Application Root:** المسار لمجلد التطبيق
   - **Application Startup File:** `server.js`
3. بعد الإنشاء، اضغط **Open Terminal** (أو SSH)
4. اكتب:
```bash
npm install --production
```
5. اضغط **Restart** أو **Start**

---

## ⑥ التحقق من نجاح الرفع

افتح المتصفح على دومينك:
```
https://yourdomain.com
```
يجب أن تظهر صفحة تسجيل الدخول.

---

## 🔧 أوامر مفيدة (من Terminal في hPanel)

```bash
# مشاهدة لوجات التطبيق
cat logs/app.log

# إعادة تشغيل
# استخدم زر Restart في واجهة Node.js

# اختبار الاتصال بقاعدة البيانات
node -e "require('dotenv').config(); const m=require('mysql2/promise'); m.createPool({host:process.env.DB_HOST,user:process.env.DB_USER,password:process.env.DB_PASSWORD,database:process.env.DB_NAME}).execute('SELECT 1').then(()=>console.log('✅ OK')).catch(e=>console.error('❌',e.message))"
```

---

## 🆘 مشاكل شائعة وحلولها

| المشكلة | الحل |
|---------|------|
| صفحة بيضاء | تأكد إن Node.js شغّال من hPanel |
| `ER_ACCESS_DENIED` | تأكد من بيانات `.env` (يوزر/باسوورد صح) |
| `ER_BAD_DB_ERROR` | تأكد إن اسم قاعدة البيانات صح في `.env` |
| `Cannot find module 'mysql2'` | شغّل `npm install` مرة تانية |
| جداول مش موجودة | ارجع لـ phpMyAdmin واستورد `schema-mysql.sql` |

---

## 📞 الدعم
أي مشكلة، ابعت رسالة الخطأ اللي بتظهر وهنحلها.
