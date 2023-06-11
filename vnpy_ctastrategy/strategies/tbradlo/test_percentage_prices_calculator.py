from decimal import Decimal
from unittest import TestCase

from vnpy_ctastrategy.strategies.tbradlo.buy_percentage_prices_calculator import PercentagePricesCalculator
from sortedcontainers import SortedDict


class TestPercentagePricesCalculator(TestCase):

    def test_should_calculate_next_buy(self):
        # given
        last_buy_price = Decimal("46.9")
        prices_calculator = PercentagePricesCalculator(buy_step=Decimal("1.0652"), sell_step=0, price_increments=SortedDict({
            Decimal("0"): Decimal("0.0001"),
            Decimal("0.1"): Decimal("0.0001"),
            Decimal("20"): Decimal("0.02"),
            Decimal("50"): Decimal("0.05")
        }))

        got_next_buy = prices_calculator.next_buy(last_buy_price)

        self.assertEqual(Decimal("44.76"), got_next_buy)

    def test_when_PEAB_should_calculate_buy_prices(self):
        # given
        last_price = Decimal("55")

        prices_calculator = PercentagePricesCalculator(buy_step=Decimal("1.0652"), sell_step=0, price_increments=SortedDict({
            Decimal("0"): Decimal("0.0001"),
            Decimal("5"): Decimal("0.005"),
            Decimal("10"): Decimal("0.01"),
            Decimal("20"): Decimal("0.02"),
            Decimal("50"): Decimal("0.05")
        }))

        # when
        got_next_buys = prices_calculator.next_buys(last_price, 20)

        # then
        self.assertEqual([Decimal('50.80'),
                          Decimal('47.68'),
                          Decimal('44.76'),
                          Decimal('42.02'),
                          Decimal('39.44'),
                          Decimal('37.02'),
                          Decimal('34.76'),
                          Decimal('32.64'),
                          Decimal('30.64'),
                          Decimal('28.76'),
                          Decimal('27.00'),
                          Decimal('25.34'),
                          Decimal('23.80'),
                          Decimal('22.34'),
                          Decimal('20.98'),
                          Decimal('19.69'),
                          Decimal('18.48'),
                          Decimal('17.35'),
                          Decimal('16.29'),
                          Decimal('15.29')], got_next_buys)

    def test_should_calculate_first_sell(self):
        # given
        prices_calculator = PercentagePricesCalculator(buy_step=Decimal("1.0652"), sell_step=Decimal("1.10"), price_increments=SortedDict({
            Decimal("0"): Decimal("0.0001"),
            Decimal("0.1"): Decimal("0.0001"),
            Decimal("20"): Decimal("0.02"),
            Decimal("50"): Decimal("0.05")
        }))

        # when
        got_sell_prices = prices_calculator.sell_prices(last_buy_price=Decimal("44.76"), count=1)

        # then
        self.assertEqual([Decimal("49.22")], got_sell_prices)

    def test_should_calculate_many_sells(self):
        # given
        prices_calculator = PercentagePricesCalculator(buy_step=Decimal("1.0652"), sell_step=Decimal("1.10"), price_increments=SortedDict({
            Decimal("0"): Decimal("0.0001"),
            Decimal("0.1"): Decimal("0.0001"),
            Decimal("20"): Decimal("0.02"),
            Decimal("50"): Decimal("0.05")
        }))

        # when
        got_sell_prices = prices_calculator.sell_prices(last_buy_price=Decimal("44.76"), count=10)

        # then
        self.assertEqual([Decimal('49.22'),
                          Decimal('52.45'),
                          Decimal('55.85'),
                          Decimal('59.50'),
                          Decimal('63.40'),
                          Decimal('67.50'),
                          Decimal('71.90'),
                          Decimal('76.60'),
                          Decimal('81.60'),
                          Decimal('86.90')], got_sell_prices)
