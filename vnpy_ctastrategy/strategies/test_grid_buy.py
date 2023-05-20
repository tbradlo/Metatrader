from datetime import datetime
from unittest import TestCase

from vnpy_ctastrategy.backtesting import BacktestingEngine

from vnpy_ctastrategy.base import EngineType, BacktestingMode

from vnpy.trader.constant import Exchange, Direction, Offset, Interval
from vnpy.trader.object import TickData, PositionData
from vnpy_ctastrategy.strategies.grid_buy import GridBuyStrategy
from unittest.mock import MagicMock, ANY


class TestGridBuy(TestCase):

    def test_when_initialized_should_send_one_buy_limit(self):
        test_engine = BacktestingEngine()
        test_engine.set_parameters(vt_symbol="SAVE-SEK-STK.SFB",
                                   interval=Interval.MINUTE,
                                   mode=BacktestingMode.TICK,
                                   start=datetime.strptime("2023-01-01", "%Y-%m-%d"),
                                   rate=1,
                                   slippage=1,
                                   size=1,
                                   pricetick=0.1)
        test_engine.add_strategy(GridBuyStrategy, {
            "buy_amount": 2500,
            "buy_step": 10,
            "buy_orders_count": 1,
            "sell_orders_count": 1,
            "take_profit_delta": 15
        })
        test_engine.history_data = [
            a_tick("10:30:00", 120.),
            a_tick("10:31:00", 120.)
        ]
        test_engine.run_backtesting()

        got_active_orders = {o.price: o.direction for o in test_engine.active_limit_orders.values()}

        self.assertEqual({110.: Direction.LONG}, got_active_orders)

    def test_should_fill_buy_limit(self):
        test_engine = BacktestingEngine()
        test_engine.set_parameters(vt_symbol="SAVE-SEK-STK.SFB",
                                   interval=Interval.MINUTE,
                                   mode=BacktestingMode.TICK,
                                   start=datetime.strptime("2023-01-01", "%Y-%m-%d"),
                                   rate=1,
                                   slippage=1,
                                   size=1,
                                   pricetick=0.1)
        test_engine.add_strategy(GridBuyStrategy, {
            "buy_amount": 2500,
            "buy_step": 10,
            "buy_orders_count": 1,
            "sell_orders_count": 1,
            "take_profit_delta": 15
        })
        test_engine.history_data = [
            a_tick("10:30:00", 120.),
            a_tick("10:31:00", 100.),
            a_tick("10:31:00", 110.)
        ]
        test_engine.run_backtesting()

        self.assertEqual(23, test_engine.strategy.pos)
        self.assertEqual(110, test_engine.strategy.last_buy_price)

    def test_when_last_buy_present_should_send_valid_orders(self):
        test_engine = BacktestingEngine()
        test_engine.set_parameters(vt_symbol="SAVE-SEK-STK.SFB",
                                   interval=Interval.MINUTE,
                                   mode=BacktestingMode.TICK,
                                   start=datetime.strptime("2023-01-01", "%Y-%m-%d"),
                                   rate=1,
                                   slippage=1,
                                   size=1,
                                   pricetick=0.1)
        test_engine.add_strategy(GridBuyStrategy, {
            "buy_amount": 2500,
            "buy_step": 10,
            "buy_orders_count": 1,
            "sell_orders_count": 1,
            "take_profit_delta": 15
        })
        test_engine.history_data = [
            a_tick("10:30:00", 116.),
            a_tick("10:31:00", 115.)
        ]

        test_engine.strategy.last_buy_price = 110
        test_engine.strategy.pos = 23

        test_engine.run_backtesting()

        got_active_orders = {o.price: o.direction for o in test_engine.active_limit_orders.values()}

        self.assertEqual(110, test_engine.strategy.last_buy_price)
        self.assertEqual({100: Direction.LONG, 125: Direction.SHORT}, got_active_orders)

    def test_should_sell_everything(self):
        test_engine = BacktestingEngine()
        test_engine.set_parameters(vt_symbol="SAVE-SEK-STK.SFB",
                                   interval=Interval.MINUTE,
                                   mode=BacktestingMode.TICK,
                                   start=datetime.strptime("2023-01-01", "%Y-%m-%d"),
                                   rate=1,
                                   slippage=1,
                                   size=1,
                                   pricetick=0.1)
        test_engine.add_strategy(GridBuyStrategy, {
            "buy_amount": 2500,
            "buy_step": 10,
            "buy_orders_count": 1,
            "sell_orders_count": 2,
            "take_profit_delta": 15
        })
        test_engine.history_data = [
            a_tick("10:30:00", 116.),
            a_tick("10:31:00", 115.)
        ]

        test_engine.strategy.last_buy_price = 110
        test_engine.strategy.pos = 23

        test_engine.run_backtesting()

        got_active_orders = {o.price: [o.direction, o.volume] for o in test_engine.active_limit_orders.values()}

        self.assertEqual(110, test_engine.strategy.last_buy_price)
        self.assertEqual({
            100: [Direction.LONG, 25],
            125: [Direction.SHORT, 20],
            135: [Direction.SHORT, 3]}, got_active_orders)


def a_tick(time, price):
    return TickData(symbol="SAVE-SEK-STK.SFB",
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

    # def test_when_initialized_should_send_one_buy_limit(self):
    #     # mock_oms_engine = MagicMock(name='OmsEngine')
    #     # mock_oms_engine.positions.return_value = {"IB.SAVE-SEK-STK.SFB.Net": a_position_data(volume=11)}
    #
    #     mock_cta_engine = MagicMock(name='CtaEngine')
    #     mock_cta_engine.get_engine_type.return_value = EngineType.BACKTESTING
    #     # mock_cta_engine.main_engine.engines.return_value = {'oms': mock_oms_engine}
    #
    #     strategy = GridBuyStrategy(cta_engine=mock_cta_engine, strategy_name="GridBuyStrategy",
    #                                vt_symbol="SAVE-SEK-STK.SFB",
    #                                setting={
    #                                    "buy_amount": 2500,
    #                                    "buy_step": 10,
    #                                    "buy_orders_count": 1,
    #                                    "sell_orders_count": 1,
    #                                    "take_profit_delta": 15
    #                                })
    #     strategy.on_init()
    #     strategy.on_start()
    #     strategy.trading = True
    #
    #     strategy.on_tick(a_tick("10:30:00", 120.))
    #     strategy.on_tick(a_tick("10:31:00", 110.))
    #
    #     mock_cta_engine.send_order.assert_called_with(ANY, Direction.LONG, Offset.OPEN, 110., 23, False, False, False)