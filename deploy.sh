#!/bin/bash
# سكريبت الـ deployment التلقائي
# شغّله على السيرفر بعد رفع الملفات

set -e

APP_DIR="/var/www/muqawilati"
echo "🚀 بدء الـ deployment..."

# إنشاء المجلدات
mkdir -p $APP_DIR/public/uploads
mkdir -p $APP_DIR/logs

# تثبيت Node.js لو مش موجود
if ! command -v node &> /dev/null; then
    echo "📦 تثبيت Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# تثبيت PM2 لو مش موجود
if ! command -v pm2 &> /dev/null; then
    echo "📦 تثبيت PM2..."
    sudo npm install -g pm2
fi

# تثبيت الـ packages
echo "📦 تثبيت الـ packages..."
cd $APP_DIR
npm install --production

# تشغيل أو إعادة تشغيل التطبيق
echo "▶️  تشغيل التطبيق..."
pm2 delete muqawilati 2>/dev/null || true
pm2 start ecosystem.config.js
pm2 save
pm2 startup

echo "✅ تم الـ deployment بنجاح!"
echo "🌐 التطبيق شغّال على البورت 3000"
echo "📋 لعرض اللوج: pm2 logs muqawilati"
