#!/usr/bin/env bash
# =============================================================================
# vps-hardening.sh — Endurecimento básico de uma VPS Ubuntu LTS para o bot
#
# O que faz (idempotente — pode rodar mais de uma vez):
#   1. Atualiza o sistema e instala utilitários (ufw, fail2ban, unattended-upgrades, sqlite3)
#   2. Cria (se não existir) o usuário de operação do bot, com sudo e grupo docker
#   3. Instala Docker Engine + Docker Compose plugin (repositório oficial)
#   4. SSH: somente chave, sem senha, sem login root por senha
#      -> SÓ desativa senha se já existir uma chave em authorized_keys (evita se trancar fora)
#   5. UFW: nega tudo de entrada, libera apenas a porta SSH
#   6. fail2ban protegendo o SSH
#   7. Atualizações de segurança automáticas
#   8. Fuso horário e sincronização de relógio (importante para assinar requisições da Binance)
#
# Uso (como root ou com sudo), na VPS recém-criada:
#   sudo bash scripts/vps-hardening.sh [usuario] [porta_ssh]
# Ex.: sudo bash scripts/vps-hardening.sh flavio 22
#
# ANTES de rodar: copie sua chave pública para a VPS (ssh-copy-id) e confirme
# que consegue entrar por chave. Abra uma segunda sessão SSH e mantenha-a aberta
# enquanto testa a nova configuração.
# =============================================================================
set -euo pipefail

BOT_USER="${1:-flavio}"
SSH_PORT="${2:-22}"
TIMEZONE="${TZ:-America/Sao_Paulo}"

if [[ $EUID -ne 0 ]]; then
  echo "Rode como root: sudo bash $0 $*" >&2
  exit 1
fi

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

export DEBIAN_FRONTEND=noninteractive

log "1/8 Atualizando sistema e instalando pacotes base"
apt-get update -y
apt-get upgrade -y
apt-get install -y ufw fail2ban unattended-upgrades apt-listchanges \
  ca-certificates curl gnupg lsb-release sqlite3 python3 git chrony

log "2/8 Usuário de operação: ${BOT_USER}"
if ! id -u "${BOT_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${BOT_USER}"
  echo "Usuário ${BOT_USER} criado (sem senha: entra só por chave SSH)."
fi
usermod -aG sudo "${BOT_USER}"
# Se o root já tem authorized_keys, copia para o novo usuário (facilita o 1º acesso)
if [[ -f /root/.ssh/authorized_keys && ! -f "/home/${BOT_USER}/.ssh/authorized_keys" ]]; then
  install -d -m 700 -o "${BOT_USER}" -g "${BOT_USER}" "/home/${BOT_USER}/.ssh"
  install -m 600 -o "${BOT_USER}" -g "${BOT_USER}" /root/.ssh/authorized_keys "/home/${BOT_USER}/.ssh/authorized_keys"
  echo "Chave pública do root copiada para ${BOT_USER}."
fi

log "3/8 Docker Engine + Compose plugin"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
usermod -aG docker "${BOT_USER}"

log "4/8 SSH somente por chave"
SSHD_DROPIN=/etc/ssh/sshd_config.d/99-hardening.conf
if [[ -s "/home/${BOT_USER}/.ssh/authorized_keys" || -s /root/.ssh/authorized_keys ]]; then
  cat > "${SSHD_DROPIN}" <<SSH
Port ${SSH_PORT}
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
SSH
  sshd -t && systemctl restart ssh
  echo "SSH: senha desativada, login só por chave, porta ${SSH_PORT}."
else
  echo "AVISO: nenhuma chave em authorized_keys. Senha SSH NÃO foi desativada para não te trancar fora."
  echo "       Rode ssh-copy-id ${BOT_USER}@IP e execute este script de novo."
fi

log "5/8 Firewall UFW (só SSH de entrada)"
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw limit "${SSH_PORT}/tcp" comment "SSH (rate-limited)"
ufw --force enable
ufw status verbose

log "6/8 fail2ban"
cat > /etc/fail2ban/jail.local <<F2B
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 4
backend  = systemd

[sshd]
enabled = true
port    = ${SSH_PORT}
F2B
systemctl enable --now fail2ban
systemctl restart fail2ban

log "7/8 Atualizações automáticas de segurança"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<APT
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT
sed -i 's|^//\s*"${distro_id}:${distro_codename}-security";|        "${distro_id}:${distro_codename}-security";|' /etc/apt/apt.conf.d/50unattended-upgrades || true
sed -i 's|^//Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "false";|' /etc/apt/apt.conf.d/50unattended-upgrades || true
systemctl enable --now unattended-upgrades

log "8/8 Fuso horário e relógio"
timedatectl set-timezone "${TIMEZONE}"
systemctl enable --now chrony
timedatectl status | sed -n '1,6p'

cat <<FIM

=============================================================================
 Hardening concluído.

 PRÓXIMOS PASSOS (manuais):
   - Teste em OUTRO terminal:  ssh -p ${SSH_PORT} ${BOT_USER}@IP_DA_VPS
   - Anote o IP público fixo:  curl -4 ifconfig.me
     -> use-o na whitelist de IP da chave de API da Binance.
   - Opcional (2FA no SSH, além da chave): apt install libpam-google-authenticator
   - Saia e entre de novo para o grupo docker valer:  docker ps
   - Clone o projeto no home de ${BOT_USER} e siga o README.
=============================================================================
FIM
