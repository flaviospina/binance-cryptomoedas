#!/usr/bin/env bash
# =============================================================================
# check-seguranca.sh — Checklist automático antes de subir o bot
#
# Verifica o que dá para verificar por script; o resto é checklist manual
# (2FA na Binance, permissões da chave, whitelist de IP) — ver README.
# Uso: bash scripts/check-seguranca.sh
# =============================================================================
set -uo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_DIR}"

ok()   { printf '  \033[1;32m[OK]\033[0m   %s\n' "$*"; }
warn() { printf '  \033[1;33m[AVISO]\033[0m %s\n' "$*"; WARN=$((WARN+1)); }
fail() { printf '  \033[1;31m[ERRO]\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
WARN=0; FAIL=0

echo "Verificando ${PROJECT_DIR}"

# .env
if [[ -f .env ]]; then
  ok ".env existe"
  perm=$(stat -c '%a' .env)
  [[ "${perm}" == "600" ]] && ok ".env com chmod 600" || fail ".env está com permissão ${perm}; rode: chmod 600 .env"
  if git ls-files --error-unmatch .env >/dev/null 2>&1; then
    fail ".env está VERSIONADO no git! Rode: git rm --cached .env"
  else
    ok ".env não está no git"
  fi
  # dry-run
  if grep -Eq '^FREQTRADE__DRY_RUN=false' .env; then
    warn "FREQTRADE__DRY_RUN=false -> modo LIVE (dinheiro real). Confirme que as Fases 2 e 3 foram aprovadas."
  else
    ok "dry-run ligado"
  fi
  # chaves
  key=$(grep -E '^FREQTRADE__EXCHANGE__KEY=' .env | cut -d= -f2-)
  [[ -z "${key}" ]] && warn "Chave da Binance vazia (ok em dry-run)" || ok "Chave da Binance definida"
  pw=$(grep -E '^FREQTRADE__API_SERVER__PASSWORD=' .env | cut -d= -f2-)
  [[ ${#pw} -ge 16 ]] && ok "Senha do FreqUI com ${#pw} caracteres" || fail "Senha do FreqUI vazia ou curta (<16). Gere com: openssl rand -base64 24"
  jwt=$(grep -E '^FREQTRADE__API_SERVER__JWT_SECRET_KEY=' .env | cut -d= -f2-)
  [[ ${#jwt} -ge 32 ]] && ok "JWT secret definido" || fail "JWT secret vazio ou curto. Gere com: openssl rand -hex 32"
  tg=$(grep -E '^FREQTRADE__TELEGRAM__TOKEN=' .env | cut -d= -f2-)
  [[ -n "${tg}" ]] && ok "Token do Telegram definido" || warn "Telegram sem token (sem alertas!)"
else
  fail ".env não existe. Rode: cp .env.example .env && chmod 600 .env"
fi

# segredos vazando no git
if git grep -nE 'FREQTRADE__EXCHANGE__(KEY|SECRET)=[A-Za-z0-9]{10,}' -- ':!.env.example' >/dev/null 2>&1; then
  fail "Possível chave de API commitada no repositório!"
else
  ok "Nenhuma chave de API encontrada nos arquivos versionados"
fi

# porta do FreqUI só em localhost
if grep -Eq '^\s*-\s*"127\.0\.0\.1:8080:8080"' docker-compose.yml; then
  ok "FreqUI publicado apenas em 127.0.0.1 (acesso via túnel SSH)"
else
  fail "docker-compose.yml expõe o FreqUI fora de localhost"
fi

# config
if python3 -c "import json,sys; c=json.load(open('user_data/config.json')); sys.exit(0 if c.get('trading_mode')=='spot' else 1)"; then
  ok "trading_mode = spot"
else
  fail "trading_mode diferente de spot no config.json"
fi
if python3 -c "import json,sys; c=json.load(open('user_data/config.json')); sys.exit(0 if any(b.startswith('BNB') for b in c['exchange']['pair_blacklist']) else 1)"; then
  ok "BNB na blacklist"
else
  fail "BNB/* não está na blacklist"
fi
if python3 -c "import json,sys; c=json.load(open('user_data/config.json')); sys.exit(0 if c.get('order_types',{}).get('stoploss_on_exchange') else 1)"; then
  ok "stoploss_on_exchange = true"
else
  warn "stoploss_on_exchange não está ativo"
fi

# firewall (só se ufw existir, i.e. na VPS)
if command -v ufw >/dev/null 2>&1; then
  if sudo -n ufw status 2>/dev/null | grep -q 'Status: active'; then
    ok "UFW ativo"
  else
    warn "UFW inativo ou sem permissão para checar (rode scripts/vps-hardening.sh)"
  fi
fi

echo
echo "Resultado: ${FAIL} erro(s), ${WARN} aviso(s)."
echo "Checklist manual (não dá para automatizar):"
echo "  [ ] 2FA ativo na conta Binance"
echo "  [ ] Chave de API: Leitura + Spot. Saque, Margem e Futuros DESLIGADOS"
echo "  [ ] Chave restrita ao IP fixo da VPS"
echo "  [ ] 2FA / chave SSH na VPS, senha desativada"
[[ ${FAIL} -eq 0 ]]
