import math
from abc import abstractmethod
from decimal import Decimal
from sortedcontainers import SortedDict


class BasePricesCalculator:

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

    @abstractmethod
    def next_buy(self, last_buy_price: Decimal):
        pass

    @abstractmethod
    def next_buys(self, last_buy_price: Decimal, count: int):
        pass

    @abstractmethod
    def sell_prices(self, last_buy_price: Decimal, count: int):
        pass

    @abstractmethod
    def higher_buy_price(self, last_buy_price: Decimal):
        pass