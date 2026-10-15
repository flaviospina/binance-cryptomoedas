# Plano de fases — bot-cripto

Acompanhamento do projeto. Cada fase só avança com aprovação explícita do Flávio.

## Decisões pendentes (preciso de resposta antes da Fase 1/2)

| # | Pergunta | Valor provisório usado | Resposta |
|---|----------|------------------------|----------|
| 1 | Capital de teste real (valor que aceita perder integralmente) | 1 000 USDT (`FREQTRADE__DRY_RUN_WALLET`) | |
| 2 | Pares preferidos (ou deixar a `VolumePairList` escolher o top 20 por volume?) | top 20 por volume em USDT, com filtros | |
| 3 | Limite de drawdown para o kill-switch | 15 % | |
| 4 | IP fixo da VPS (para a whitelist da chave Binance) | — | |
| 5 | Máximo de operações abertas | 3 | |
| 6 | Taxa real da sua conta Binance (0,1 % padrão; menor com VIP/BNB?) | 0,1 % por lado | |
| 7 | Timeframes: 1h e 4h apenas, ou incluir 15m? | 1h e 4h | |

## Fase 0 — Ambiente ✅ (entregue, aguardando aprovação)

- [x] Estrutura do projeto
- [x] `docker-compose.yml` (imagem oficial `stable`, restart automático, porta só em localhost, health-check)
- [x] `.env.example` (todos os segredos via variáveis `FREQTRADE__*`)
- [x] `user_data/config.json` base: dry-run, Spot, stoploss na exchange, BNB na blacklist, pairlist dinâmica com filtros
- [x] `PlaceholderStrategy` (nunca opera) para validar Telegram/FreqUI/conexão
- [x] `.gitignore` cobrindo `.env`, `*.private.json`, sqlite, logs, dados
- [x] `scripts/vps-hardening.sh` (UFW, fail2ban, SSH só por chave, atualizações automáticas, Docker)
- [x] `scripts/backup.sh` (SQLite online backup + configs, retenção 30 dias)
- [x] `scripts/check-seguranca.sh` (checklist automático antes de subir)
- [x] `README.md` em português, passo a passo
- [ ] Validação na VPS real pelo Flávio (`make up`, `/status` no Telegram, FreqUI pelo túnel)

## Fase 1 — Dados e estratégias

- [ ] `config.backtest.json` com whitelist estática (backtest exige lista fixa)
- [ ] Download de 3 anos de candles 1h e 4h (+ BTC/USDT 1d para regime de mercado)
- [ ] `TendenciaEMA` — cruzamento de EMAs + ADX + filtro de tendência do BTC em 1d
- [ ] `ReversaoMedia` — RSI + Bandas de Bollinger, só quando o BTC não está em queda forte
- [ ] `RompimentoDonchian` — Donchian + stop dinâmico por ATR
- [ ] Proteções em todas: `StoplossGuard`, `MaxDrawdown`, `CooldownPeriod`, `LowProfitPairs`
- [ ] Position sizing por risco (1–2 % do capital por operação)

## Fase 2 — Validação rigorosa

- [ ] Backtest com taxa 0,1 % e slippage
- [ ] Treino/teste (hyperopt só no treino) + walk-forward
- [ ] `lookahead-analysis` e `recursive-analysis`
- [ ] Comparação com buy & hold de BTC
- [ ] Relatório por estratégia e por regime (alta, lateral, queda)
- [ ] Critérios: PF > 1,3 fora da amostra; DD máx < 20 %; ≥ 100 trades; positivo em > 1 regime

## Fase 3 — Dry-run 4 a 8 semanas

- [ ] Estratégia aprovada em dry-run na VPS 24/7
- [ ] Relatório semanal automático vs. backtest

## Fase 4 — Live com capital pequeno

- [ ] Aprovação explícita do Flávio
- [ ] Chave com permissão de trade, IP restrito; `FREQTRADE__DRY_RUN=false`
- [ ] `max_open_trades` reduzido; capital fracionado

## Fase 5 — Operação contínua

- [ ] Cron de backup diário
- [ ] Health-check externo via n8n (`/api/v1/ping`)
- [ ] Alertas: bot parado, erro de API, ordem rejeitada, drawdown, saldo inesperado
- [ ] Relatório semanal e export CSV mensal (USDT e BRL) para a Receita Federal
- [ ] Revisão mensal com o Claude (sem reotimizar toda semana)
