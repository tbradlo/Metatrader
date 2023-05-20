from dataclasses import dataclass
from math import ceil
from typing import Dict

from vnpy.trader.constant import Direction, Status
from vnpy.trader.utility import ceil_to, BarGenerator, floor_to

from vnpy_ctastrategy import (
    CtaTemplate,
    StopOrder,
    TickData,
    BarData,
    TradeData,
    OrderData,
)
from vnpy_ctastrategy.base import EngineType


@dataclass
class Order:
    def __init__(self, price, volume):
        self.price = price
        self.volume = volume


class GridBuyStrategy(CtaTemplate):
    """"""

    author = "Tomek"

    buy_amount: float = 2500  # spend 2500 SEK = 1k pln
    buy_step: float = 5  # buy every 2.5 USD
    buy_orders_count: int = 2  # how many pending buy orders to open
    sell_orders_count: int = 2  # how many pending sell orders to open
    take_profit_delta: float = 10.0  # price gain on a single stock to take profit
    max_own_volume: int = 100  # how many stock to buy at most

    active_sell_orders: Dict[str, Order] = {}
    active_buy_orders: Dict[str, Order] = {}

    last_buy_price: float = 0

    parameters = [
        "buy_amount",
        "buy_step",
        "buy_orders_count",
        "sell_orders_count",
        "take_profit_delta",
        "max_own_volume"
    ]
    variables = [
        "last_buy_price"
    ]

    def __init__(self, cta_engine, strategy_name, vt_symbol, setting):
        """"""
        super().__init__(cta_engine, strategy_name, vt_symbol, setting)
        self.bg = BarGenerator(self.on_bar)

    def on_init(self):
        self.write_log("Strategy initialization")

        if self.get_engine_type() == EngineType.LIVE:
        #     try:
        #         self.pos = self.cta_engine.main_engine.engines['oms'].positions["IB." + self.vt_symbol + ".Net"].volume
        #     except AttributeError:
        #         self.write_log("No owned positions found")
        #         pass
            try:
                active_orders: Dict[str, OrderData] = self.cta_engine.main_engine.engines['oms'].active_orders
                #  self.active_buy_orders, self.active_sell_orders = [o for o in active_orders if o.]
            except AttributeError:
                self.write_log("No active orders found")
                pass

        self.write_log("Strategy initialization completed")

    def on_start(self):
        self.write_log("strategy start")

    def on_stop(self):
        self.write_log("strategy stop, positions own: " + str(self.pos))

    def on_tick(self, tick: TickData):
        self.write_log("on tick1")
        self.bg.update_tick(tick)

    def sell_price(self, buy_price):
        return buy_price + self.take_profit_delta

    def on_bar(self, bar: BarData):  # TODO narazie po 1m barach, bo by default ticki pobiera z RData a nie z IB
        self.write_log("on bar1")
        if self.last_buy_price == 0:
            self.last_buy_price = ceil_to(bar.close_price, self.buy_step)  # init for simplicity

        expected_buy_orders = self.closest_buys()
        expected_sell_orders = self.closest_sells() if self.pos > 0 else []

        self.remove_unexpected_orders(expected_buy_orders, expected_sell_orders)

        active_buy_order_prices = {order.price for order in self.active_buy_orders.values()}
        active_sell_order_prices = {order.price for order in self.active_sell_orders.values()}

        missing_buy_orders = [price for price in expected_buy_orders if price not in active_buy_order_prices]
        missing_sell_orders = [price for price in expected_sell_orders if
                               price not in active_sell_order_prices and price]

        self.send_missing_orders(missing_buy_orders, missing_sell_orders)

    def closest_buys(self):
        return [self.last_buy_price - (i + 1) * self.buy_step for i in range(self.buy_orders_count)]

    def closest_sells(self):
        return [self.sell_price(self.last_buy_price + i * self.buy_step) for i in range(self.sell_orders_count)]

    def send_missing_orders(self, missing_buy_orders, missing_sell_orders):
        for buy_price in missing_buy_orders:
            buy_volume = ceil(self.buy_amount / buy_price)

            if self.pos + buy_volume > self.max_own_volume:
                buy_volume = self.max_own_volume - self.pos  # stop buying if limit exceeded

            if self.pos < 0.2 * self.max_own_volume:
                buy_volume = round(buy_volume * 1.3)    # buy a bit more at the beginning, to sell it later

            if buy_volume > 0:
                order_ids = self.buy(buy_price, buy_volume)
                if order_ids:
                    self.active_buy_orders[order_ids[0]] = Order(buy_price, buy_volume)

        volume_for_sell = self.pos
        for order in self.active_sell_orders.values():
            volume_for_sell -= order.volume

        for sell_price in missing_sell_orders:
            sell_volume = min(volume_for_sell, ceil(self.buy_amount / sell_price))
            order_ids = self.sell(sell_price, sell_volume)
            if order_ids:
                self.active_sell_orders[order_ids[0]] = Order(sell_price, sell_volume)
            volume_for_sell -= sell_volume

    def remove_unexpected_orders(self, expected_buy_orders, expected_sell_orders):
        """
        Remove unexpected orders: dividend cuts case (dividend is cut out of buy/sell order)
        """
        buy_orders_to_close = {orderId: order.price for orderId, order in self.active_buy_orders.items() if
                               order.price not in expected_buy_orders}
        sell_orders_to_close = {orderId: order.price for orderId, order in self.active_sell_orders.items() if
                                order.price not in expected_sell_orders}
        for orderId in buy_orders_to_close.keys():
            self.cancel_order(orderId)
            del self.active_buy_orders[orderId]
        for orderId in sell_orders_to_close.keys():
            self.cancel_order(orderId)
            del self.active_sell_orders[orderId]

    def on_order(self, order: OrderData):
        pass

    def on_trade(self, trade: TradeData):

        if trade.direction == Direction.LONG:
            self.last_buy_price = trade.price
            del self.active_buy_orders[trade.vt_orderid]
        elif trade.direction == Direction.SHORT:
            self.last_buy_price += self.buy_step
            del self.active_sell_orders[trade.vt_orderid]

        self.put_event()

    def on_stop_order(self, stop_order: StopOrder):
        pass
