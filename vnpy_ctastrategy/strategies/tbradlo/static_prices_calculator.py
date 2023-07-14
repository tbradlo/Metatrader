import math
from decimal import Decimal
from sortedcontainers import SortedDict

from vnpy_ctastrategy.strategies.tbradlo.base_prices_calculator import BasePricesCalculator


class StaticPricesCalculator(BasePricesCalculator):

    def __init__(self, buy_step: Decimal, sell_step: Decimal, price_increments: SortedDict[Decimal, Decimal]):
        super().__init__(buy_step, sell_step, price_increments)

    def next_buy(self, last_buy_price: Decimal):
        norm_last_price = self.normalize(last_buy_price)
        return self.normalize(norm_last_price - self.buy_step)

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
        last_buy_price = self.normalize(last_buy_price)

        sell_prices = []
        for i in range(count):
            sell_price = last_buy_price + self.sell_step
            last_buy_price = self.higher_buy_price(last_buy_price)

            norm_sell_price = self.normalize(sell_price)
            sell_prices.append(norm_sell_price)

        return sell_prices

    def higher_buy_price(self, last_buy_price: Decimal):
        last_buy_price = self.normalize(last_buy_price)

        return self.normalize(last_buy_price + self.buy_step)
