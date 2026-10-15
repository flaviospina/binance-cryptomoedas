#!/usr/bin/env bash
# =============================================================================
# backup.sh — Backup diário do banco SQLite, configs e estratégias do bot
#
# - Usa a API de backup online do SQLite (seguro mesmo com o bot rodando / WAL).
# - Gera um .tar.gz por execução em $BACKUP_DIR com permissão 600.
# - Mantém os últimos $RETENTION_DAYS dias.
# - NÃO inclui o .env (segredos). Guarde o .env separadamente, cifrado.
#
# Uso manual:   bash scripts/backup.sh
# Cron diário:  crontab -e  ->  15 3 * * * /home/flavio/bot-cripto/scripts/backup.sh >> /home/flavio/bot-cripto/user_data/logs/backup.log 2>&1
#
# Variáveis opcionais:
#   BACKUP_DIR      destino (padrão: <projeto>/backups)
#   RETENTION_DAYS  dias a manter (padrão: 30)
#   RCLONE_REMOTE   ex. "gdrive:bot-cripto" -> envia a cópia para um remoto rclone
# =============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_DIR}/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

echo "[$(date '+%F %T')] Iniciando backup em ${BACKUP_DIR}"

# 1) Bancos SQLite (trade e dry-run), cópia consistente via API de backup
shopt -s nullglob
for db in "${PROJECT_DIR}"/user_data/*.sqlite; do
  name="$(basename "${db}")"
  python3 - "${db}" "${WORK}/${name}" <<'PY'
import sqlite3, sys
src, dst = sys.argv[1], sys.argv[2]
with sqlite3.connect(src) as s, sqlite3.connect(dst) as d:
    s.backup(d)
print(f"  banco copiado: {src}")
PY
done

# 2) Configs e estratégias (sem dados de mercado, sem logs, sem .env)
mkdir -p "${WORK}/user_data"
cp -r "${PROJECT_DIR}/user_data/strategies" "${WORK}/user_data/" 2>/dev/null || true
cp "${PROJECT_DIR}"/user_data/config*.json "${WORK}/user_data/" 2>/dev/null || true
cp "${PROJECT_DIR}/docker-compose.yml" "${WORK}/" 2>/dev/null || true
[[ -d "${PROJECT_DIR}/docs" ]] && cp -r "${PROJECT_DIR}/docs" "${WORK}/"

# 3) Empacota
ARCHIVE="${BACKUP_DIR}/bot-cripto-${STAMP}.tar.gz"
tar -czf "${ARCHIVE}" -C "${WORK}" .
chmod 600 "${ARCHIVE}"
echo "  gerado: ${ARCHIVE} ($(du -h "${ARCHIVE}" | cut -f1))"

# 4) Retenção
find "${BACKUP_DIR}" -name 'bot-cripto-*.tar.gz' -mtime +"${RETENTION_DAYS}" -print -delete | sed 's/^/  removido antigo: /'

# 5) Cópia remota opcional
if [[ -n "${RCLONE_REMOTE:-}" ]] && command -v rclone >/dev/null 2>&1; then
  rclone copy "${ARCHIVE}" "${RCLONE_REMOTE}/" && echo "  enviado para ${RCLONE_REMOTE}"
fi

echo "[$(date '+%F %T')] Backup concluído."
