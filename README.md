# bot-cripto — Robô de trading Spot na Binance (Freqtrade)

Sistema automatizado, rodando 24/7 numa VPS, que analisa o mercado e executa
compras e vendas no mercado **Spot** da Binance com regras determinísticas,
testáveis e com gestão de risco em primeiro lugar.

> **Aviso honesto.** Nenhuma estratégia garante lucro. A maioria dos robôs de
> varejo perde dinheiro por excesso de risco, taxas e overfitting. O objetivo
> aqui é uma estratégia com expectativa positiva comprovada em teste, drawdown
> controlado e que pode ser desligada a qualquer momento. Opere apenas com
> capital que você aceita perder integralmente.

## Como o projeto está organizado

```
bot-cripto/
├── docker-compose.yml          # Freqtrade (imagem oficial stable) com reinício automático
├── .env.example                # Modelo das variáveis de ambiente (copie para .env)
├── Makefile                    # Atalhos: make up / logs / backtest / backup ...
├── user_data/
│   ├── config.json             # Config base: dry-run, Spot, stoploss na exchange, pairlist dinâmica
│   ├── strategies/             # Estratégias (Fase 1). Hoje: PlaceholderStrategy (não opera)
│   ├── data/                   # Candles baixados (não versionado)
│   ├── logs/                   # Logs do bot (não versionado)
│   └── backtest_results/       # Resultados brutos (não versionado)
├── scripts/
│   ├── vps-hardening.sh        # Endurece a VPS: UFW, fail2ban, SSH só por chave, Docker
│   ├── backup.sh               # Backup diário do SQLite + configs
│   └── check-seguranca.sh      # Checklist automático antes de subir o bot
└── docs/
    └── PLANO-DE-FASES.md       # Acompanhamento das fases e decisões pendentes
```

Stack: **Freqtrade** (`freqtradeorg/freqtrade:stable`) → **CCXT** → **Binance Spot**.
Monitoramento por **Telegram** e **FreqUI** (painel web, só via túnel SSH).
Banco **SQLite** com backup diário.

## Fases

| Fase | O quê | Estado |
|------|-------|--------|
| 0 | Ambiente, segurança, dry-run básico | **Entregue** — aguardando sua validação na VPS |
| 1 | Dados históricos + 3 estratégias candidatas | Aguardando aprovação da Fase 0 |
| 2 | Validação rigorosa (backtest, out-of-sample, lookahead, vs. buy & hold) | — |
| 3 | Dry-run 4–8 semanas na VPS | — |
| 4 | Live com capital pequeno (só com sua aprovação explícita) | — |
| 5 | Operação contínua: backups, alertas, health-check n8n, relatórios, CSV fiscal | — |

Detalhes e checklist em [`docs/PLANO-DE-FASES.md`](docs/PLANO-DE-FASES.md).

---

## Passo a passo — Fase 0

### 1. Criar a VPS

- Ubuntu LTS (22.04 ou 24.04), 2 vCPU / 2 GB RAM são suficientes para operar.
  Para backtest/hyperopt (Fase 2) ajuda ter 4 GB.
- **IP fixo** (necessário para a whitelist da Binance).
- Copie sua chave pública antes de qualquer coisa:

```bash
ssh-copy-id root@IP_DA_VPS
ssh root@IP_DA_VPS     # confirme que entra sem senha
```

### 2. Endurecer a VPS

Abra **duas** sessões SSH (uma fica de reserva). Na primeira:

```bash
apt-get install -y git
git clone https://github.com/flaviospina/binance-cryptomoedas.git /opt/bot-cripto-setup
sudo bash /opt/bot-cripto-setup/scripts/vps-hardening.sh flavio 22
```

O script:

- atualiza o sistema e instala `ufw`, `fail2ban`, `unattended-upgrades`, Docker e Compose;
- cria o usuário `flavio` (sudo + docker) e copia sua chave SSH para ele;
- desativa login por senha **somente se já houver chave** em `authorized_keys`;
- libera apenas a porta SSH no firewall (com rate-limit);
- liga atualizações de segurança automáticas e sincroniza o relógio
  (a Binance rejeita requisições com relógio fora de sincronia).

Teste na segunda sessão: `ssh flavio@IP_DA_VPS`. Só então feche a primeira.
Anote o IP público: `curl -4 ifconfig.me`.

### 3. Clonar o projeto como usuário `flavio`

```bash
ssh flavio@IP_DA_VPS
git clone https://github.com/flaviospina/binance-cryptomoedas.git ~/bot-cripto
cd ~/bot-cripto
cp .env.example .env
chmod 600 .env
```

### 4. Criar a chave de API da Binance

Binance → Perfil → **Gerenciamento de API** → Criar API (System generated).

| Permissão | Valor |
|-----------|-------|
| Ativar Leitura | ✅ |
| Ativar Trading Spot e de Margem | ✅ (usaremos **só Spot**; o bot está travado em `trading_mode: spot`) |
| Ativar Saques | ❌ **nunca** |
| Ativar Futuros | ❌ **nunca** |
| Restrição de IP | **Restringir acesso apenas a IPs confiáveis** → IP da VPS |

Ative o **2FA** na conta, se ainda não tiver. Em dry-run a chave pode ficar
vazia; o bot usa apenas dados públicos. Preencha só quando for validar a
conexão autenticada (`/balance` no Telegram).

### 5. Criar o bot do Telegram

1. Fale com **@BotFather** → `/newbot` → copie o **token**.
2. Fale com **@userinfobot** → copie o seu **chat id** (número).
3. Mande qualquer mensagem para o seu bot novo (para ele poder te responder).

### 6. Preencher o `.env`

```bash
nano .env
```

Gere senhas fortes para o FreqUI:

```bash
openssl rand -base64 24   # FREQTRADE__API_SERVER__PASSWORD
openssl rand -hex 32      # FREQTRADE__API_SERVER__JWT_SECRET_KEY
openssl rand -hex 16      # FREQTRADE__API_SERVER__WS_TOKEN (health-check n8n)
id -u; id -g              # FT_UID / FT_GID (normalmente 1000)
```

Mantenha `FREQTRADE__DRY_RUN=true`. Esse valor só muda na Fase 4.

### 7. Subir o bot em dry-run

```bash
make check      # checklist de segurança; corrige o que apontar
make up         # sobe o container
make logs       # acompanha; Ctrl+C sai dos logs sem parar o bot
```

Você deve ver no log o bot em `dry run`, a lista de pares escolhida pela
`VolumePairList` e, no Telegram, a mensagem de inicialização. A
`PlaceholderStrategy` **não abre operação nenhuma**; ela existe para validar a
infraestrutura. As estratégias reais chegam na Fase 1.

### 8. Acessar o FreqUI (painel web)

O painel nunca fica exposto na internet. Só a própria VPS enxerga a porta 8080.
No **seu computador**:

```bash
ssh -N -L 8080:127.0.0.1:8080 flavio@IP_DA_VPS
```

Abra `http://localhost:8080` e entre com o usuário e senha do `.env`.

### 9. Comandos do Telegram

| Comando | O que faz |
|---------|-----------|
| `/status` | Operações abertas |
| `/profit` | Resultado acumulado |
| `/balance` | Saldo na exchange (exige chave de API) |
| `/daily` `/weekly` `/monthly` | Resultado por período |
| `/stopbuy` | **Para de abrir novas posições**, mantém as abertas (kill-switch manual) |
| `/stop` | Para o bot inteiro |
| `/start` | Retoma |
| `/forceexit all` | Fecha tudo a mercado (emergência) |
| `/whitelist` | Pares em operação agora |
| `/health` | Último ciclo processado |

### 10. Backup diário

```bash
crontab -e
# adicione (ajuste o caminho):
15 3 * * * /home/flavio/bot-cripto/scripts/backup.sh >> /home/flavio/bot-cripto/user_data/logs/backup.log 2>&1
```

Os arquivos vão para `~/bot-cripto/backups/` (chmod 600, retenção 30 dias).
Para cópia fora da VPS, instale `rclone` e defina `RCLONE_REMOTE=gdrive:bot-cripto`
no cron. O `.env` **não entra** no backup: guarde-o num cofre de senhas.

---

## Como a gestão de risco está configurada (base)

| Item | Onde | Valor inicial |
|------|------|---------------|
| Modo | `config.json` → `trading_mode` | `spot` (sem alavancagem, sem futuros, sem margem) |
| Dry-run | `.env` → `FREQTRADE__DRY_RUN` | `true` |
| Operações abertas | `max_open_trades` | 3 |
| Tamanho da posição | `stake_amount: unlimited` + `tradable_balance_ratio: 0.99` | capital ÷ 3 por operação; na Fase 1 a estratégia ajusta pelo risco (1–2 % por operação) |
| Stoploss | `order_types.stoploss_on_exchange` | `true` — a ordem de stop fica na Binance, protege mesmo com a VPS fora |
| Pares | `pairlists` | top 20 por volume em USDT, listados há ≥ 180 dias, spread ≤ 0,3 %, filtros de preço e volatilidade |
| Blacklist | `exchange.pair_blacklist` | `BNB/*`, stablecoins, tokens alavancados (UP/DOWN/BULL/BEAR), wrapped, LUNA/FTT |
| Proteções (`StoplossGuard`, `MaxDrawdown`, `CooldownPeriod`, `LowProfitPairs`) | estratégia (Fase 1) | kill-switch em 15 % de drawdown (a confirmar) |

Por que `BNB/*` na blacklist: a Binance pode cobrar taxas em BNB, e o Freqtrade
recomenda não operar o par para não confundir saldo de taxa com saldo de posição.

## Checklist de segurança

- [ ] 2FA ativo na Binance
- [ ] Chave de API: Leitura + Spot; **Saque, Margem e Futuros desligados**
- [ ] Chave restrita ao IP da VPS
- [ ] `.env` com `chmod 600`, fora do Git (`make check` confere)
- [ ] SSH só por chave; UFW ativo liberando só SSH; fail2ban ligado
- [ ] FreqUI só por túnel SSH (porta publicada em `127.0.0.1`)
- [ ] `FREQTRADE__DRY_RUN=true` até a Fase 4

## Operação do dia a dia

```bash
make            # lista todos os atalhos
make ps         # container e health-check
make logs       # logs ao vivo
make restart    # reinicia
make pull && make restart   # atualiza o Freqtrade (leia o changelog antes)
make list-pairs # quais pares a pairlist dinâmica escolheria agora
make backup     # backup manual
```

## Problemas comuns

- **`Permission denied` em `user_data/`**: `FT_UID`/`FT_GID` no `.env` precisam ser os do seu usuário (`id -u`, `id -g`). Depois `sudo chown -R $USER:$USER user_data`.
- **Telegram não responde**: confira token e chat id; mande uma mensagem ao bot antes; veja `make logs`.
- **`Timestamp for this request is outside of the recvWindow`**: relógio da VPS fora de sincronia. `sudo chronyc makestep`.
- **`Invalid API-key, IP, or permissions`**: a chave não tem o IP da VPS na whitelist ou está sem permissão Spot.
- **FreqUI não abre**: o túnel SSH está aberto? `curl -s http://127.0.0.1:8080/api/v1/ping` na VPS deve responder `{"status":"pong"}`.

## O que este projeto NÃO faz, por decisão

- Não usa LLM para decidir compras/vendas em tempo real.
- Não usa alavancagem, futuros, grid sem stop, martingale ou "preço médio infinito".
- Não opera moedas de baixa liquidez nem segue sinais de grupos.
- Não coloca em produção estratégia que não passou pelas Fases 2 e 3.
- Não promete nem estima lucro.
