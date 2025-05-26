#!/bin/bash
set -euo pipefail

BACKUP_DIR=""
MYSQL_USER=""
MYSQL_PASSWORD=""
THREADS=$(nproc)
DATE_FOLDER=$(date +'%d.%m.%Y')
DATE_NOW=$(date +'%H-%M-%S')

AWS_BUCKET=""
AWS_ENDPOINT_URL=""
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""

EXCLUDES="phpmyadmin|sys|mysql|performance_schema|information_schema"

mkdir -p "$BACKUP_DIR"

echo "🗂️ Получаем список баз..."
DATABASES=$(mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -N -e "SHOW DATABASES;" | grep -Ev "$EXCLUDES")

echo "🗂️ Будут забэкаплены базы: $DATABASES"

START_TIME=$(date +%s)

for DB in $DATABASES; do
  echo "🌐 Дамп базы $DB..."
  DUMP_DIR="$BACKUP_DIR/${DB}_dump"
  
  # Добавляем уникальный суффикс к имени архива для уникальности
  UNIQUE_SUFFIX=$(date +%H-%M-%S)_$RANDOM
  ARCHIVE_NAME="${DB}_${UNIQUE_SUFFIX}.tar.zst"
  ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"

  rm -rf "$DUMP_DIR"
  mkdir -p "$DUMP_DIR"

  mydumper -u "$MYSQL_USER" -p "$MYSQL_PASSWORD" -o "$DUMP_DIR" -t "$THREADS" --database "$DB"

  echo "📦 Архивируем базу $DB..."
  tar -cf - -C "$BACKUP_DIR" "$(basename "$DUMP_DIR")" | zstd -T"$THREADS" -o "$ARCHIVE_PATH"

  rm -rf "$DUMP_DIR"

  echo "☁️ Загружаем $ARCHIVE_NAME в Bucket через s5cmd..."

  AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  s5cmd --endpoint-url "$AWS_ENDPOINT_URL" cp "$ARCHIVE_PATH" "s3://$AWS_BUCKET/mysql/$DATE_FOLDER/$ARCHIVE_NAME"

  echo "✅ $ARCHIVE_NAME загружен."
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo "⏱ Время работы скрипта: $((ELAPSED / 60)) мин. $((ELAPSED % 60)) сек."
echo "⏱ Бэкап завершён."
