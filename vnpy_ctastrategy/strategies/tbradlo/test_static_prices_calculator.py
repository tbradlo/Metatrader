from decimal import Decimal
from unittest import TestCase

from sortedcontainers import SortedDict

from vnpy_ctastrategy.strategies.tbradlo.static_prices_calculator import StaticPricesCalculator


class TestStaticPricesCalculator(TestCase):

    def test_should_calculate_next_buy(self):
        # given
        last_buy_price = Decimal("30.0")
        prices_calculator = StaticPricesCalculator(buy_step=Decimal("1.0"), sell_step=Decimal("1.0"), price_increments=SortedDict({
            Decimal("0"): Decimal("0.01"),
            Decimal("5000"): Decimal("1")
        }))

        got_next_buy = prices_calculator.next_buy(last_buy_price)

        self.assertEqual(Decimal("29.0"), got_next_buy)

    def test_when_1491_HUGAI_should_calculate_buy_prices(self):
        # given
        last_price = Decimal("31")

        prices_calculator = StaticPricesCalculator(buy_step=Decimal("1.0"), sell_step=Decimal("1.0"), price_increments=SortedDict({
            Decimal("0"): Decimal("0.01"),
            Decimal("5000"): Decimal("1")
        }))

        # when
        got_next_buys = prices_calculator.next_buys(last_price, 10)

        # then
        self.assertEqual([Decimal('30.00'),
                          Decimal('29.00'),
                          Decimal('28.00'),
                          Decimal('27.00'),
                          Decimal('26.00'),
                          Decimal('25.00'),
                          Decimal('24.00'),
                          Decimal('23.00'),
                          Decimal('22.00'),
                          Decimal('21.00')], got_next_buys)

    def test_should_calculate_first_sell(self):
        # given
        prices_calculator = StaticPricesCalculator(buy_step=Decimal("1.0"), sell_step=Decimal("1.0"), price_increments=SortedDict({
            Decimal("0"): Decimal("0.01"),
            Decimal("5000"): Decimal("1")
        }))

        # when
        got_sell_prices = prices_calculator.sell_prices(last_buy_price=Decimal("30.0"), count=1)

        # then
        self.assertEqual([Decimal("31.0")], got_sell_prices)

    def test_should_calculate_many_sells(self):
        # given
        prices_calculator = StaticPricesCalculator(buy_step=Decimal("1.0"), sell_step=Decimal("1.0"), price_increments=SortedDict({
            Decimal("0"): Decimal("0.01"),
            Decimal("5000"): Decimal("1")
        }))

        # when
        got_sell_prices = prices_calculator.sell_prices(last_buy_price=Decimal("25"), count=10)

        # then
        self.assertEqual([Decimal('26.00'),
                          Decimal('27.00'),
                          Decimal('28.00'),
                          Decimal('29.00'),
                          Decimal('30.00'),
                          Decimal('31.00'),
                          Decimal('32.00'),
                          Decimal('33.00'),
                          Decimal('34.00'),
                          Decimal('35.00')], got_sell_prices)
