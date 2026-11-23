#!/usr/bin/env bash
# Start script for Personal Management System on Railway.
# First boot: generates this instance's JWT key pair and encryption key on the volume,
# runs the database migrations and creates the owner account. Later boots: migrations only.
set -euo pipefail
log() { echo "[pms-start] $*"; }

# Fixed settings (upstream's .env defaults for a production install).
export APP_ENV=prod APP_DEBUG=0 APP_DEMO=false APP_MAINTENANCE=false
export PUBLIC_ROOT_DIR=public UPLOAD_DIR=upload
export IMAGES_UPLOAD_DIR=upload/images FILES_UPLOAD_DIR=upload/files
export VIDEOS_UPLOAD_DIR=upload/videos MINIATURES_UPLOAD_DIR=upload/miniatures
export APP_IPS_ACCESS_RESTRICTION="${APP_IPS_ACCESS_RESTRICTION:-[]}"
export MAILER_DSN="${MAILER_DSN:-null://null}"
export APP_EMERGENCY_EMAILS_RECEIVER_EMAIL="${APP_EMERGENCY_EMAILS_RECEIVER_EMAIL:-${PMS_ADMIN_EMAIL:-root@localhost}}"
export APP_DEFAULT_NPL_RECEIVER_EMAILS="${APP_DEFAULT_NPL_RECEIVER_EMAILS:-[]}"
export PORT="${PORT:-8080}"

: "${APP_SECRET:?APP_SECRET is required}"
: "${PMS_ADMIN_EMAIL:?PMS_ADMIN_EMAIL is required}"
: "${PMS_ADMIN_PASSWORD:?PMS_ADMIN_PASSWORD is required}"
: "${PMS_LOCK_PASSWORD:?PMS_LOCK_PASSWORD is required}"
if [ -z "${DATABASE_URL:-}" ]; then
  : "${DB_HOST:?DB_HOST or DATABASE_URL is required}" "${DB_PASSWORD:?DB_PASSWORD is required}"
  # IPv6 hosts on Railway's private network need brackets in the URL.
  export DATABASE_URL="mysql://${DB_USER:-pms}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT:-3306}/${DB_NAME:-pms}?serverVersion=mariadb-11.8.0&charset=utf8mb4"
fi

cd /app
console() { php bin/console --no-interaction "$@"; }

# Volume layout (owned by root on Railway; the app writes as www-data).
mkdir -p /data/jwt /data/config /data/upload
for d in images files videos miniatures PROFILE_IMAGE; do mkdir -p "/data/upload/$d"; done
if [ ! -d /data/upload/images/system ]; then cp -a /srv/seed/upload/images/system /data/upload/images/; fi
chown -R www-data:www-data /data/upload

# Encryption key for the Passwords module: generated once, never replaced (losing it loses those passwords).
if [ ! -s /data/config/encryption.yaml ]; then
  log "Generating this instance's encryption key"
  key="$(php -r 'echo base64_encode(random_bytes(32));')"
  umask 077
  printf "parameters:\n    encrypt_key: '%s'\n" "$key" > /data/config/encryption.yaml.tmp
  mv /data/config/encryption.yaml.tmp /data/config/encryption.yaml
  umask 022
fi
chmod 644 /data/config/encryption.yaml

log "Clearing cache"
rm -rf /app/var/cache/prod
console cache:clear >/dev/null
console cache:warmup >/dev/null

# JWT key pair (protected with APP_SECRET), generated once.
if [ ! -s /data/jwt/private.pem ]; then
  log "Generating this instance's JWT key pair"
  console lexik:jwt:generate-keypair --skip-if-exists
fi
chown -R www-data:www-data /data/jwt && chmod 600 /data/jwt/private.pem && chmod 644 /data/jwt/public.pem

# The frontend checks token signatures with the public key built into its bundle: swap in ours.
php -r '
  $js = file_get_contents("/srv/front-index.js.orig");
  $old = json_encode(trim(file_get_contents("/srv/default-jwt-public.pem")), JSON_UNESCAPED_SLASHES);
  $new = json_encode(trim(file_get_contents("/data/jwt/public.pem")), JSON_UNESCAPED_SLASHES);
  $n = substr_count($js, $old);
  if ($n !== 1) { fwrite(STDERR, "frontend JWT key not found exactly once ($n)\n"); exit(1); }
  file_put_contents(trim(file_get_contents("/srv/front-index.path")), str_replace($old, $new, $js));
'

log "Waiting for the database"
for i in $(seq 1 90); do
  if php -r '
    $u = parse_url(getenv("DATABASE_URL"));
    $h = trim($u["host"], "[]");
    try { new PDO("mysql:host=$h;port=".($u["port"] ?? 3306), urldecode($u["user"]), urldecode($u["pass"] ?? ""), [PDO::ATTR_TIMEOUT => 3]); exit(0); }
    catch (Throwable $e) { exit(1); }' 2>/dev/null; then break; fi
  [ "$i" = 90 ] && { log "Database not reachable after 3 minutes"; exit 1; }
  sleep 2
done

console doctrine:database:create --if-not-exists
log "Running migrations"
console doctrine:migrations:migrate --allow-no-migration
console storage:upload-files-into-entities >/dev/null || log "storage:upload-files-into-entities failed (not fatal)"
chown -R www-data:www-data /app/var /data/upload

# Nginx config for $PORT.
sed "s/__PORT__/${PORT}/g" /etc/nginx/pms.conf.template > /etc/nginx/nginx.conf

php-fpm --nodaemonize --force-stderr &
FPM_PID=$!
nginx -c /etc/nginx/nginx.conf -g 'daemon off;' &
NGINX_PID=$!
trap 'kill -TERM $NGINX_PID $FPM_PID 2>/dev/null; wait' TERM INT

# Owner account: created once, through the app's own registration endpoint (localhost only).
for i in $(seq 1 30); do
  curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/healthz" && break
  sleep 1
done
# /can-register always answers HTTP 200; the JSON body says whether an account already exists.
canreg="$(curl -s "http://127.0.0.1:${PORT}/api/can-register" || true)"
if [[ "$canreg" == *'"success":true'* ]]; then
  log "Creating the owner account ${PMS_ADMIN_EMAIL}"
  body="$(php -r 'echo json_encode([
    "email" => getenv("PMS_ADMIN_EMAIL"), "username" => getenv("PMS_ADMIN_USERNAME") ?: "owner",
    "password" => getenv("PMS_ADMIN_PASSWORD"), "passwordConfirmed" => getenv("PMS_ADMIN_PASSWORD"),
    "lockPassword" => getenv("PMS_LOCK_PASSWORD"), "lockPasswordConfirmed" => getenv("PMS_LOCK_PASSWORD")]);')"
  result="$(curl -s -H 'Content-Type: application/json' -d "$body" "http://127.0.0.1:${PORT}/api/register-user" || true)"
  case "$result" in
    *'"success":true'*) log "Owner account created" ;;
    *) log "Owner account was NOT created: ${result:0:300}" ;;
  esac
else
  log "Owner account already exists (registration closed)"
fi
log "Personal Management System ${PMS_VERSION} is up on port ${PORT}"

wait -n "$FPM_PID" "$NGINX_PID"
code=$?
log "A process exited ($code); stopping"
kill -TERM "$NGINX_PID" "$FPM_PID" 2>/dev/null || true
exit "$code"
