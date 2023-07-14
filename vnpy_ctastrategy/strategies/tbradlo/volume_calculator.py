import math
from decimal import Decimal


class VolumeCalculator:

    def __init__(self, vt_symbol: str, max_cash_to_invest: Decimal, write_log_f):
        self.round_to = 1 if "-JPY-STK" not in vt_symbol else 100  # on TSEJ you must buy multi of 100 stock
        self.max_cash_to_invest = max_cash_to_invest
        self.write_log_f = write_log_f

    def buy_volume(self, buy_amount: Decimal, buy_price: Decimal, already_invested: Decimal) -> Decimal:
        if already_invested > self.max_cash_to_invest:
            self.write_log_f(f"BUY skipped: Invested too much, own: {already_invested}/{self.max_cash_to_invest}")
            return Decimal(0)

        if already_invested < Decimal("0.2") * self.max_cash_to_invest:
            buy_amount = Decimal(round(buy_amount * Decimal("1.4"))) # buy a bit more at the beginning

        volume = Decimal(math.ceil(buy_amount / buy_price))
        rounded = Decimal(round(volume / self.round_to) * self.round_to)
        return rounded if rounded > 0 else Decimal(self.round_to)

    def sell_volume(self, volume_for_sell: Decimal, buy_amount: Decimal, sell_price: Decimal):
        if volume_for_sell <= 0:
            return 0
        sell_volume = min(volume_for_sell, Decimal(math.ceil(buy_amount / sell_price)))
        rounded = Decimal(round(sell_volume / self.round_to) * self.round_to)
        return rounded if rounded > 0 else Decimal(self.round_to)
