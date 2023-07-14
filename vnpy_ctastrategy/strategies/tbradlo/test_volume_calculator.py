from decimal import Decimal
from unittest import TestCase


from vnpy_ctastrategy.strategies.tbradlo.volume_calculator import VolumeCalculator


class TestVolumeCalculator(TestCase):

    def test_when_buy_round_to_1_should_round_up(self):
        # given
        volume_calculator = VolumeCalculator("ABC-USD-STK", Decimal(10000), do_nothing)

        # when
        got_volume = volume_calculator.buy_volume(Decimal(10), Decimal(3), Decimal(5000))

        # then
        self.assertEqual(Decimal(4), got_volume)

    def test_WHEN_starting_investment_SHOULD_buy_more_than_regular_package(self):
        # given
        volume_calculator = VolumeCalculator(vt_symbol="ABC-USD-STK", max_cash_to_invest=Decimal(10000), write_log_f=do_nothing)

        # when
        got_volume = volume_calculator.buy_volume(Decimal(4), Decimal(2), Decimal(0))

        # then
        self.assertEqual(3, got_volume)

    def test_WHEN_already_invested_more_than_allowed_SHOULD_return_Zero(self):
        # given
        volume_calculator = VolumeCalculator(vt_symbol="ABC-USD-STK", max_cash_to_invest=Decimal(10000), write_log_f=do_nothing)

        # when
        got_volume = volume_calculator.buy_volume(Decimal(10), Decimal(3), Decimal(10001))

        # then
        self.assertEqual(0, got_volume)

    def test_when_buy_round_to_100_should_round_but_not_zero(self):
        # given
        volume_calculator = VolumeCalculator("ABC-JPY-STK", Decimal(10000), do_nothing)

        # when
        got_volume = volume_calculator.buy_volume(Decimal(10), Decimal(3), Decimal(0))

        # then
        self.assertEqual(Decimal(100), got_volume)

    def test_when_buy_round_to_100_should_round(self):
        # given
        volume_calculator = VolumeCalculator("ABC-JPY-STK", Decimal(10000), do_nothing)

        # when
        got_volume = volume_calculator.buy_volume(Decimal(10), Decimal(3), Decimal(0))

        # then
        self.assertEqual(Decimal(100), got_volume)

    def test_WHEN_regular_sell_SHOULD_work(self):
        # given
        volume_calculator = VolumeCalculator("ABC-USD-STK", Decimal(10000), do_nothing)

        # when
        got_volume = volume_calculator.sell_volume(Decimal(10), Decimal(100), Decimal(20))

        # then
        self.assertEqual(Decimal(5), got_volume)

    def test_WHEN_nothing_to_sell_SHOULD_return_0(self):
        # given
        volume_calculator = VolumeCalculator("ABC-USD-STK", Decimal(10000), do_nothing)

        # when
        got_volume = volume_calculator.sell_volume(Decimal(0), Decimal(100), Decimal(20))

        # then
        self.assertEqual(Decimal(0), got_volume)


    def test_WHEN_japan_sell_SHOULD_sell_minimum_amount(self):
        # given
        volume_calculator = VolumeCalculator("ABC-JPY-STK", Decimal(10000), do_nothing)

        # when
        got_volume = volume_calculator.sell_volume(Decimal(10), Decimal(100), Decimal(20))

        # then
        self.assertEqual(Decimal(100), got_volume)

    def test_WHEN_japan_sell_SHOULD_sell_valid_amount(self):
        # given
        volume_calculator = VolumeCalculator("ABC-JPY-STK", Decimal(10000), do_nothing)

        # when
        got_volume = volume_calculator.sell_volume(Decimal(543), Decimal(615), Decimal(2))

        # then
        self.assertEqual(Decimal(300), got_volume)

def do_nothing(msg: str):
    return