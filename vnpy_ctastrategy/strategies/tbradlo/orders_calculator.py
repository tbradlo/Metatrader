from decimal import Decimal
from math import ceil
from typing import List

from vnpy_ctastrategy.strategies.execution_tuple import ExecutionTuple
from vnpy_ctastrategy.strategies.tbradlo.base_prices_calculator import BasePricesCalculator


class OrdersCalculator:

    REDUCE_ALL_THRESHOLD = Decimal('0.75')
    REDUCE_WORST_THRESHOLD = Decimal('0.50')
    COMMISSION_PERCENT = Decimal('1.004')

    def __init__(self, prices_calculator: BasePricesCalculator, vt_symbol: str, max_cash_to_invest: Decimal):
        self.vt_symbol = vt_symbol
        self.prices_calculator = prices_calculator
        self.max_cash_to_invest = max_cash_to_invest

    def reduce_orders(self, executions: List[ExecutionTuple]):
        if '-STK' not in self.vt_symbol or not executions:
            return []

        cash_invested = sum([execution.price * execution.volume for execution in executions])
        own_volume = sum([execution.volume for execution in executions])
        if own_volume <= 0:
            return []

        avg_price = cash_invested / own_volume

        cash_invested_to_reduce_all = self.REDUCE_ALL_THRESHOLD * self.max_cash_to_invest

        if cash_invested > cash_invested_to_reduce_all:
            cash_to_sell = cash_invested - cash_invested_to_reduce_all
            sell_volume = Decimal(ceil(cash_to_sell / avg_price))    # TODO japan volume 100 support
            sell_price = self.prices_calculator.normalize(avg_price * self.COMMISSION_PERCENT)
            return [(sell_price, sell_volume)]

        cash_invested_to_reduce_worst = self.REDUCE_WORST_THRESHOLD * self.max_cash_to_invest
        last_buy = executions[-1].volume > 0

        if last_buy and cash_invested > cash_invested_to_reduce_worst:
            cash_to_sell = cash_invested - cash_invested_to_reduce_worst
            worst_execution = None
            for execution in executions:
                if execution.volume > 0 and (worst_execution is None or worst_execution.price < execution.price):
                    worst_execution = execution

            sell_price = self.prices_calculator.normalize(worst_execution.price * self.COMMISSION_PERCENT)
            sell_volume = Decimal(ceil(cash_to_sell / sell_price))    # TODO japan volume 100 support

            return [(sell_price, sell_volume)]

        return []