from datetime import datetime
from decimal import Decimal
from unittest import TestCase
from unittest.mock import patch

from sortedcontainers import SortedDict

from vnpy_ctastrategy.backtesting import BacktestingEngine

from vnpy_ctastrategy.base import BacktestingMode

from vnpy.trader.constant import Exchange, Direction, Interval
from vnpy.trader.object import TickData, PositionData
from vnpy_ctastrategy.strategies.grid_buy import GridBuyStrategy


class TestGridBuy(TestCase):

    def test_when_initialized_should_send_one_buy_limit(self):
        # given
        test_engine = BacktestingEngine()
        test_engine.set_parameters(vt_symbol="PBR-USD-STK.SMART",
                                   interval=Interval.MINUTE,
                                   mode=BacktestingMode.TICK,
                                   start=datetime.strptime("2023-01-01", "%Y-%m-%d"),
                                   rate=0.002,
                                   slippage=1,
                                   size=1,
                                   pricetick=0.01)
        test_engine.add_strategy(GridBuyStrategy, {
            "buy_amount": 2000,
            "buy_step": 1.0067,
            "take_profit": 1.10,
            "buy_orders_count": 1,
            "sell_orders_count": 1
        })
        test_engine.history_data = [
            a_tick("10:30:00", 13.00)
        ]
        with patch.object(test_engine.strategy, 'fetch_price_steps') as mock_method:
            mock_method.return_value = SortedDict({
                Decimal("0"): Decimal("0.01")
            })

            # when
            test_engine.run_backtesting()

            got_active_orders = {o.price: o.direction for o in test_engine.active_limit_orders.values()}

            # then
            self.assertEqual({13.0: Direction.LONG}, got_active_orders)

    def test_when_all_sold_and_higher_than_max_buy_price_should_NOT_send_one_buys(self):
        # given
        test_engine = BacktestingEngine()
        test_engine.set_parameters(vt_symbol="PBR-USD-STK.SMART",
                                   interval=Interval.MINUTE,
                                   mode=BacktestingMode.TICK,
                                   start=datetime.strptime("2023-01-01", "%Y-%m-%d"),
                                   rate=0.002,
                                   slippage=1,
                                   size=1,
                                   pricetick=0.01)
        test_engine.add_strategy(GridBuyStrategy, {
            "buy_amount": 2000,
            "buy_step": 1.0067,
            "take_profit": 1.10,
            "buy_orders_count": 1,
            "sell_orders_count": 1,
            "max_buy_price": 13.0
        })
        test_engine.history_data = [
            a_tick("10:30:00", 13.01)
        ]
        with patch.object(test_engine.strategy, 'fetch_price_steps') as mock_method:
            mock_method.return_value = SortedDict({
                Decimal("0"): Decimal("0.01")
            })

            # when
            test_engine.run_backtesting()

            got_active_orders = {o.price: o.direction for o in test_engine.active_limit_orders.values()}

            # then
            self.assertEqual({}, got_active_orders)

    def test_should_fill_buy_limit(self):
        test_engine = BacktestingEngine()
        test_engine.set_parameters(vt_symbol="PBR-USD-STK.SMART",
                                   interval=Interval.MINUTE,
                                   mode=BacktestingMode.TICK,
                                   start=datetime.strptime("2023-01-01", "%Y-%m-%d"),
                                   rate=0.002,
                                   slippage=1,
                                   size=1,
                                   pricetick=0.01)
        test_engine.add_strategy(GridBuyStrategy, {
            "buy_amount": 2000,
            "buy_step": 1.0067,
            "take_profit": 1.10,
            "buy_orders_count": 1,
            "sell_orders_count": 1
        })
        test_engine.history_data = [
            a_tick("10:30:00", 13.),
            a_tick("10:31:00", 12.9)
        ]

        with patch.object(test_engine.strategy, 'fetch_price_steps') as mock_method:
            mock_method.return_value = SortedDict({
                Decimal("0"): Decimal("0.01")
            })

            # when
            test_engine.run_backtesting()

            #then
            self.assertEqual(154.0, test_engine.strategy.pos)
            self.assertEqual(12.9, test_engine.strategy.last_buy_price) # TODO is that right?

    def test_when_last_buy_present_should_send_valid_orders(self):
        # given
        test_engine = BacktestingEngine()
        test_engine.set_parameters(vt_symbol="PBR-USD-STK.SMART",
                                   interval=Interval.MINUTE,
                                   mode=BacktestingMode.TICK,
                                   start=datetime.strptime("2023-01-01", "%Y-%m-%d"),
                                   rate=0.002,
                                   slippage=1,
                                   size=1,
                                   pricetick=0.01)
        test_engine.add_strategy(GridBuyStrategy, {
            "buy_amount": 2000,
            "buy_step": 1.0067,
            "take_profit": 1.10,
            "buy_orders_count": 1,
            "sell_orders_count": 1
        })
        test_engine.history_data = [
            a_tick("10:30:00", 12.)
        ]

        test_engine.strategy.last_buy_price = 11.75
        test_engine.strategy.pos = 100

        with patch.object(test_engine.strategy, 'fetch_price_steps') as mock_method:
            mock_method.return_value = SortedDict({
                Decimal("0"): Decimal("0.01")
            })

            # when
            test_engine.run_backtesting()

            got_active_orders = {o.price: o.direction for o in test_engine.active_limit_orders.values()}

            # then
            self.assertEqual(11.75, test_engine.strategy.last_buy_price)
            self.assertEqual({11.7: Direction.LONG, 12.96: Direction.SHORT}, got_active_orders)

    def test_should_sell_everything(self):
        # given
        test_engine = BacktestingEngine()
        test_engine.set_parameters(vt_symbol="PBR-USD-STK.SMART",
                                   interval=Interval.MINUTE,
                                   mode=BacktestingMode.TICK,
                                   start=datetime.strptime("2023-01-01", "%Y-%m-%d"),
                                   rate=0.002,
                                   slippage=1,
                                   size=1,
                                   pricetick=0.01)
        test_engine.add_strategy(GridBuyStrategy, {
            "buy_amount": 2000,
            "buy_step": 1.0067,
            "take_profit": 1.10,
            "buy_orders_count": 2,
            "sell_orders_count": 5
        })
        test_engine.history_data = [
            a_tick("10:30:00", 14.)
        ]

        test_engine.strategy.last_buy_price = 12.
        test_engine.strategy.pos = 200

        with patch.object(test_engine.strategy, 'fetch_price_steps') as mock_method:
            mock_method.return_value = SortedDict({
                Decimal("0"): Decimal("0.01")
            })

            # when
            test_engine.run_backtesting()

            got_active_orders = {o.price: [o.direction, o.volume] for o in test_engine.active_limit_orders.values()}

            # then
            self.assertEqual(12., test_engine.strategy.last_buy_price)
            self.assertEqual({
                11.86: [Direction.LONG, 169],
                11.94: [Direction.LONG, 168],
                13.22: [Direction.SHORT, 167],
                13.31: [Direction.SHORT, 33]}, got_active_orders)


def a_tick(time, price):
    return TickData(symbol="PBR-USD-STK.SMART",
                    exchange=Exchange.NYSE,
                    datetime=datetime.strptime("2023-01-01 " + time, "%Y-%m-%d %H:%M:%S"),
                    gateway_name="IB",
                    ask_price_1=price,
                    bid_price_1=price,
                    last_price=price)


def a_position_data(volume):
    return PositionData(gateway_name="IB",
                        symbol="some symbol",
                        exchange=Exchange.SMART,
                        direction=Direction.NET,
                        volume=volume)