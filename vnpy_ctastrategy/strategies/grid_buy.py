from dataclasses import dataclass
from decimal import Decimal
from math import ceil
from typing import Dict, cast

from vnpy.trader.constant import Direction, Status
from vnpy.trader.object import PositionData
from vnpy.trader.utility import ceil_to, BarGenerator, floor_to, round_to

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
    price: Decimal
    volume: Decimal

    def __str__(self):
        return f"Price: {self.price}, Volume: {self.volume}"

# TODO Handle Price Parameters / Steps: e.g.
# price > 2	step = 0.0001
# price > 5	step = 0.0002


class GridBuyStrategy(CtaTemplate):
    """"""

    author = "Tomek"

    buy_amount: float = 500  # spend 2500 SEK = 1k pln
    buy_step: float = 0.25  # buy every 2.5 USD
    buy_orders_count: int = 2  # how many pending buy orders to open
    sell_orders_count: int = 2  # how many pending sell orders to open
    take_profit_delta: float = 0.9  # price gain on a single stock to take profit
    max_own_volume: float = 1000  # how many stock to buy at most
    max_buy_price: float = 99999  # Do not buy when price is above..
    p_last_buy_price: float = 0.  # Set value > 0 if you need to overwrite lastBuyPrice

    def buy_amount_d(self):
        return Decimal(str(self.buy_amount))

    def buy_step_d(self):
        return Decimal(str(self.buy_step))

    def pos_d(self):
        return Decimal(self.pos)

    def take_profit_delta_d(self):
        return Decimal(str(self.take_profit_delta))

    def max_own_volume_d(self):
        return Decimal(str(self.max_own_volume))

    active_sell_orders: Dict[str, Order] = {}
    active_buy_orders: Dict[str, Order] = {}

    last_buy_price: float = 0.

    def last_buy_price_d(self):
        return Decimal(str(self.last_buy_price))

    parameters = [
        "buy_amount",
        "buy_step",
        "buy_orders_count",
        "sell_orders_count",
        "take_profit_delta",
        "max_own_volume",
        "max_buy_price",
        "p_last_buy_price"
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

    def on_start(self):
        if self.p_last_buy_price > 0:
            self.last_buy_price = self.p_last_buy_price

        if self.get_engine_type() == EngineType.LIVE:
            oms_positions = self.cta_engine.main_engine.engines['oms'].positions
            for position in oms_positions.values():
                position = cast(PositionData, position)
                if position.symbol == self.vt_symbol.split(".")[0]:
                    self.pos = int(position.volume)
                    break

            try:
                active_orders: Dict[str, OrderData] = self.cta_engine.main_engine.engines['oms'].active_orders
                for order_id, order_data in active_orders.items():
                    if order_data.direction == Direction.LONG:
                        self.active_buy_orders[order_id] = Order(Decimal(str(order_data.price)), Decimal(str(order_data.volume)))
                    elif order_data.direction == Direction.SHORT:
                        self.active_sell_orders[order_id] = Order(Decimal(str(order_data.price)), Decimal(str(order_data.volume)))
            except AttributeError:
                self.write_log("Reading active orders Failed")
                pass
        self.write_log("strategy start")

    def on_stop(self):
        self.write_log("strategy stop, positions own: " + str(self.pos))

    def on_tick(self, tick: TickData):
        #self.write_log("on tick1")
        self.bg.update_tick(tick)

    def sell_price(self, buy_price: Decimal):
        return buy_price + self.take_profit_delta_d()

    def to_decimal(self, float_value) -> Decimal:
        return Decimal(str(float_value))

    def on_bar(self, bar: BarData):  # TODO narazie po 1m barach, bo by default ticki pobiera z RData a nie z IB
        self.write_log("on bar1")

        if self.pos == 0:
            self.send_buy(self.to_decimal(bar.high_price))  # Buy using "Market Price"
            return

        expected_buy_orders = self.closest_buys()
        expected_sell_orders = self.closest_sells() if self.pos > 0 else []

        self.remove_unexpected_orders(expected_buy_orders, expected_sell_orders)

        active_buy_order_prices = {order.price for order in self.active_buy_orders.values()}
        active_sell_order_prices = {order.price for order in self.active_sell_orders.values()}

        missing_buy_orders = [price for price in expected_buy_orders if price not in active_buy_order_prices]
        missing_sell_orders = [price for price in expected_sell_orders if
                               price not in active_sell_order_prices and price]

        self.send_missing_orders(missing_buy_orders, missing_sell_orders)

    def closest_buys(self) -> [Decimal]:
        return [self.last_buy_price_d() - (i + 1) * self.buy_step_d() for i in range(self.buy_orders_count)]

    def closest_sells(self) -> [Decimal]:
        return [self.sell_price(self.last_buy_price_d() + i * self.buy_step_d()) for i in range(self.sell_orders_count)]

    def buy_price_normalized(self, buy_price: Decimal) -> Decimal:
        return self.round_to(buy_price, self.buy_step_d())

    def round_to(self, value: Decimal, target: Decimal) -> Decimal:
        return (value / target).quantize(Decimal('1')) * target

    def buy_volume(self, buy_price: Decimal) -> Decimal:
        return Decimal(ceil(self.buy_amount_d() / buy_price))

    def send_buy(self, buy_price: Decimal):
        if buy_price > self.max_buy_price:
            self.write_log(f"Max buy price ${self.max_buy_price} reached. Buy skipped")
            return

        normalized_buy_price = self.buy_price_normalized(buy_price)

        for order in self.active_buy_orders.values():
            if normalized_buy_price == order.price:
                self.write_log(f"Buy order ${normalized_buy_price} present. Skipping")
                return

        buy_volume: Decimal = self.buy_volume(buy_price)

        if self.pos_d() + buy_volume > self.max_own_volume_d():
            buy_volume = self.max_own_volume_d() - self.pos_d()  # stop buying if limit exceeded

        if self.pos_d() < Decimal("0.2") * self.max_own_volume_d():
            buy_volume = Decimal(round(buy_volume * Decimal("1.3")))    # buy a bit more at the beginning, to sell it later

        if buy_volume > 0:
            order_ids = self.buy(float(buy_price), float(buy_volume))
            if order_ids:
                self.active_buy_orders[order_ids[0]] = Order(normalized_buy_price, buy_volume)

    def send_missing_orders(self, missing_buy_orders, missing_sell_orders):
        for buy_price in missing_buy_orders:
            self.send_buy(buy_price)

        volume_for_sell: Decimal = self.pos_d()
        for order in self.active_sell_orders.values():
            volume_for_sell -= order.volume

        for sell_price in missing_sell_orders:
            sell_volume = min(volume_for_sell, Decimal(ceil(self.buy_amount_d() / sell_price)))
            order_ids = self.sell(float(sell_price), float(sell_volume))
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
            self.last_buy_price = float(self.buy_price_normalized(self.to_decimal(trade.price)))
            del self.active_buy_orders[trade.vt_orderid]
        elif trade.direction == Direction.SHORT:
            self.last_buy_price = float(self.last_buy_price_d() + self.buy_step_d())
            del self.active_sell_orders[trade.vt_orderid]

        self.put_event()

    def on_stop_order(self, stop_order: StopOrder):
        pass
