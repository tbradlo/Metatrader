from decimal import Decimal
from unittest import TestCase
from unittest.mock import Mock

from vnpy_ctastrategy.strategies.execution_tuple import ExecutionTuple
from vnpy_ctastrategy.strategies.tbradlo.orders_calculator import OrdersCalculator


class TestOrdersCalculator(TestCase):

    def test_WHEN_owns_over_75_percent_SHOULD_reduce_at_avg_price(self):
        # given
        executions = [
            ExecutionTuple('date1', Decimal('200'), Decimal('5')),
            ExecutionTuple('date1', Decimal('100'), Decimal('10')) # 2k in total
        ]

        prices_calculator = Mock()
        prices_calculator.normalize = lambda number: round(number, 2)
        orders_calculator = OrdersCalculator(prices_calculator=prices_calculator, vt_symbol="ABC-USD-STK.SMART", max_cash_to_invest=Decimal('2000'))

        # when
        got_reduce_orders = orders_calculator.reduce_orders(executions)

        self.assertEqual(
            [(Decimal('133.87'), Decimal('4'))], got_reduce_orders)

    def test_WHEN_owns_over_75_percent_AND_sell_orders_present_SHOULD_reduce_at_avg_price(self):
        # given
        executions = [
            ExecutionTuple('date1', Decimal('200'), Decimal('5')),
            ExecutionTuple('date1', Decimal('200'), Decimal('5')),
            ExecutionTuple('date1', Decimal('200'), Decimal('-5')),
            ExecutionTuple('date1', Decimal('100'), Decimal('10')) # 2k in total
        ]

        prices_calculator = Mock()
        prices_calculator.normalize = lambda number: round(number, 2)
        orders_calculator = OrdersCalculator(prices_calculator=prices_calculator, vt_symbol="ABC-USD-STK.SMART", max_cash_to_invest=Decimal('2000'))

        # when
        got_reduce_orders = orders_calculator.reduce_orders(executions)

        self.assertEqual(
            [(Decimal('133.87'), Decimal('4'))], got_reduce_orders)

    def test_WHEN_owns_over_50_percent_SHOULD_reduce_worst_position(self):
        # given
        executions = [
            ExecutionTuple('date1', Decimal('4'), Decimal('10')), # 40
            ExecutionTuple('date1', Decimal('3'), Decimal('10')), # 30
            ExecutionTuple('date1', Decimal('2'), Decimal('10')) # 20 - 90 in total
        ]

        prices_calculator = Mock()
        prices_calculator.normalize = lambda number: round(number, 2)
        orders_calculator = OrdersCalculator(prices_calculator=prices_calculator, vt_symbol="ABC-USD-STK.SMART", max_cash_to_invest=Decimal('160'))

        # when
        got_reduce_orders = orders_calculator.reduce_orders(executions)

        self.assertEqual(
            [(Decimal('4.02'), Decimal('3'))], got_reduce_orders)