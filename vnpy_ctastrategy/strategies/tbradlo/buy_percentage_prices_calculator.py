import math
from decimal import Decimal
from sortedcontainers import SortedDict


class PercentagePricesCalculator:

    def __init__(self, buy_step: Decimal, sell_step: Decimal, price_increments: SortedDict[Decimal, Decimal]):
        self.buy_step = buy_step
        self.sell_step = sell_step
        self.price_increments = price_increments

    @staticmethod
    def round_to(value: Decimal, target: Decimal) -> Decimal:
        return (value / target).quantize(Decimal('1')) * target

    def normalize(self, buy_price: Decimal):
        index = self.price_increments.bisect_right(buy_price) - 1
        range_from = self.price_increments.keys()[index]
        increment_to_use = self.price_increments.get(range_from)
        return self.round_to(buy_price, increment_to_use)

    def next_buy(self, last_buy_price: Decimal):
        absolute_step_no, start_price = self.absolute_step_no(last_buy_price)

        lower_price_power = round(absolute_step_no)-1

        precise_lower_buy_price = start_price * self.buy_step ** lower_price_power

        return self.normalize(precise_lower_buy_price)

    def absolute_step_no(self, buy_price):
        start_price = next(iter(self.price_increments.values()))
        absolute_step_no = math.log(buy_price / start_price, self.buy_step)
        return absolute_step_no, start_price

    def next_buys(self, last_buy_price: Decimal, count: int):
        got_next_buys = []
        for i in range(count):
            last_buy_price = self.next_buy(last_buy_price)
            got_next_buys.append(last_buy_price)
        return got_next_buys

    def sell_prices(self, last_buy_price: Decimal, count: int):
        absolute_step_no, start_price = self.absolute_step_no(last_buy_price)
        absolute_step_no = round(absolute_step_no)

        sell_prices = []
        for i in range(count):
            buy_price = start_price * self.buy_step ** (absolute_step_no + i)
            sell_price = buy_price * self.sell_step
            norm_price = self.normalize(sell_price)
            sell_prices.append(norm_price)

        return sell_prices

    def higher_buy_price(self, last_buy_price: Decimal):
        absolute_step_no, start_price = self.absolute_step_no(last_buy_price)

        higher_price_power = round(absolute_step_no)+1

        precise_lower_buy_price = start_price * self.buy_step ** higher_price_power

        return self.normalize(precise_lower_buy_price)
