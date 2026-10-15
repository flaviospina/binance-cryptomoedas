"""
PlaceholderStrategy — estratégia "vazia" da Fase 0.

Ela NUNCA gera sinal de compra. Existe apenas para que o container suba e
possamos validar, sem risco algum:
  - conexão com a Binance (download de candles, lista de pares),
  - alertas e comandos do Telegram (/status, /balance, /stopbuy, /stop),
  - acesso ao FreqUI via túnel SSH,
  - reinício automático, logs e backup.

As estratégias reais (tendência, reversão à média e rompimento) serão
entregues na Fase 1, cada uma em seu próprio arquivo nesta pasta.
"""

from pandas import DataFrame

from freqtrade.strategy import IStrategy


class PlaceholderStrategy(IStrategy):
    INTERFACE_VERSION = 3

    # Somente SPOT, somente compra (long). Nunca short, nunca alavancagem.
    can_short = False

    timeframe = "1h"
    process_only_new_candles = True
    startup_candle_count = 0

    # Mesmo sem operar, o Freqtrade exige stoploss definido.
    stoploss = -0.05
    minimal_roi = {"0": 10}  # 1000% -> na prática nunca sai por ROI
    use_exit_signal = True

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        # Nenhum indicador: estratégia inerte por desenho.
        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        # Zero em todas as velas = jamais compra.
        dataframe["enter_long"] = 0
        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe["exit_long"] = 0
        return dataframe
