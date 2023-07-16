from dataclasses import dataclass
from decimal import Decimal
from typing import Dict, cast, Any

from sortedcontainers import SortedDict

from vnpy.trader.constant import Direction, Exchange
from vnpy.trader.database import get_database
from vnpy.trader.object import PositionData
from vnpy.trader.utility import BarGenerator

from vnpy_ctastrategy import (
    CtaTemplate,
    StopOrder,
    TickData,
    BarData,
    TradeData,
    OrderData,
)
from vnpy_ctastrategy.base import EngineType
from vnpy_ctastrategy.strategies.execution_tuple import ExecutionTuple
from vnpy_ctastrategy.strategies.tbradlo.base_prices_calculator import BasePricesCalculator
from vnpy_ctastrategy.strategies.tbradlo.buy_percentage_prices_calculator import PercentagePricesCalculator
from vnpy_ctastrategy.strategies.tbradlo.static_prices_calculator import StaticPricesCalculator
from vnpy_ctastrategy.strategies.tbradlo.volume_calculator import VolumeCalculator


@dataclass
class Order:
    price: Decimal
    volume: Decimal

    def __str__(self):
        return f"Price: {self.price}, Volume: {self.volume}"


class GridBuyStrategy(CtaTemplate):
    """"""

    author = "Tomek"

    buy_amount: float = 500.  # params must be static
    buy_step: float = 1.01
    take_profit: float = 1.15
    buy_orders_count: int = 2
    sell_orders_count: int = 2
    max_cash_invested: float = 10000.
    max_buy_price: float = 9999.
    buy_steps_algo: str = "percent"
    executions: [ExecutionTuple] = []
    profit: float = 0.

    parameters = [
        "buy_amount",
        "buy_step",
        "take_profit",
        "buy_orders_count",
        "sell_orders_count",
        "max_cash_invested",
        "max_buy_price",
        "buy_steps_algo"
    ]
    variables = [
        "last_buy_price",
        "total_bought",
        "total_sold",
        'executions',
        'profit'
    ]

    def __init__(self, cta_engine: Any, strategy_name: str, vt_symbol: str, setting: dict):
        self.active_sell_orders: Dict[str, Order] = {}
        self.active_buy_orders: Dict[str, Order] = {}
        self.executions = []
        self.profit = 0.

        self.last_buy_price: float = 0.
        self.total_bought: float = 0.
        self.total_sold: float = 0.

        self.current_value: Decimal = Decimal('0')

        self.started = False
        self.prices_calculator: BasePricesCalculator
        self.volume_calculator: VolumeCalculator

        super().__init__(cta_engine, strategy_name, vt_symbol, setting)

        self.bg = BarGenerator(self.on_bar)

    def buy_amount_d(self):
        return Decimal(str(self.buy_amount))

    def buy_step_d(self):
        return Decimal(str(self.buy_step))

    def take_profit_d(self):
        return Decimal(str(self.take_profit))

    def pos_d(self):
        return Decimal(self.pos)

    def max_cash_invested_d(self):
        return Decimal(str(self.max_cash_invested))

    def last_buy_price_d(self):
        return Decimal(str(self.last_buy_price))


    def fetch_price_steps(self):
        symbol, exchange = self.vt_symbol.rsplit(".", 1)
        if self.cta_engine.main_engine:
            market_rule_id, price_increments = self.cta_engine.main_engine.get_gateway("IB").api.query_price_steps_sync(self.vt_symbol)
            get_database().save_price_increment_data(market_rule_id, symbol, Exchange(exchange), price_increments)
            return price_increments
        else:
            return get_database().load_price_increment_data(symbol, Exchange(exchange))

    def set_price_increments(self, price_increments: SortedDict[Decimal, Decimal]):
        if self.buy_steps_algo == "static":
            self.prices_calculator = StaticPricesCalculator(
                buy_step=self.buy_step_d(),
                sell_step=self.take_profit_d(),
                price_increments=price_increments
            )
        else:
            self.prices_calculator = PercentagePricesCalculator(
                buy_step=self.buy_step_d(),
                sell_step=self.take_profit_d(),
                price_increments=price_increments
            )

    def on_init(self):
        self.active_buy_orders.clear()  # clear strategy state for backtesting
        self.active_sell_orders.clear()
        self.total_bought = self.total_sold = 0.
        self.set_price_increments(self.fetch_price_steps())
        self.volume_calculator = VolumeCalculator(self.vt_symbol, self.max_cash_invested_d(), self.write_log)
        self.write_log("Strategy initialization completed")
        #
        # self.cta_engine.sync_strategy_data(self)

    def on_start(self):
        # convert deserialized array int tuple
        for i in range(0, len(self.executions)):
            if not isinstance(self.executions[i], ExecutionTuple):
                self.executions[i] = ExecutionTuple(*self.executions[i])

        if self.get_engine_type() == EngineType.LIVE:
            oms_positions = self.cta_engine.main_engine.engines['oms'].positions
            for position in oms_positions.values():
                position = cast(PositionData, position)
                if position.symbol == self.vt_symbol.rsplit(".", 1)[0]:
                    self.pos = int(position.volume)
                    break
            if "-CASH." in self.vt_symbol:
                ccy = self.vt_symbol.split("-")[0]
                accounts_by_ccy = {key.split(".")[-1]: value for key, value in self.cta_engine.main_engine.engines['oms'].accounts.items() if key.endswith(f".{ccy}")}
                if accounts_by_ccy:
                    self.pos = int(accounts_by_ccy[ccy].balance)

            try:
                self.active_buy_orders.clear()
                self.active_sell_orders.clear()
                active_orders: Dict[str, OrderData] = self.cta_engine.main_engine.engines['oms'].active_orders
                for order_id, order_data in active_orders.items():
                    if order_data.symbol == self.vt_symbol.rsplit(".", 1)[0]:
                        self.cta_engine.orderid_strategy_map[order_id] = self
                        self.cta_engine.strategy_orderid_map[self.strategy_name].add(order_id)
                        if order_data.direction == Direction.LONG:
                            self.active_buy_orders[order_id] = Order(Decimal(str(order_data.price)), Decimal(str(order_data.volume)))
                        elif order_data.direction == Direction.SHORT:
                            self.active_sell_orders[order_id] = Order(Decimal(str(order_data.price)), Decimal(str(order_data.volume)))
            except AttributeError:
                self.write_log("Reading active orders Failed")
                pass

        self.write_log(f"strategy start, Own vol: {self.pos} Sells: {len(self.active_sell_orders)} Buys: {len(self.active_buy_orders)}")
        self.write_log(f"strategy orders in dict: : {len({key: value for key, value in self.cta_engine.orderid_strategy_map.items() if value == self})}")
        self.started = True

        try:
            last_tick = self.cta_engine.main_engine.engines['oms'].ticks[self.vt_symbol]
            self.on_tick(last_tick)
        except KeyError:
            self.write_log("Reading last tick failed")
            pass

    def on_stop(self):
        self.write_log("strategy stop, positions own: " + str(self.pos_d()))
        self.started = False

    def on_tick(self, tick: TickData):
        if not self.started:
            return

        bid_price = self.to_decimal(tick.bid_price_1 if tick.bid_price_1 > 0 else tick.pre_close)
        ask_price = self.to_decimal(tick.ask_price_1 if tick.ask_price_1 > 0 else tick.pre_close)

        self.current_value = Decimal(str(bid_price * self.pos))
        self.bg.update_tick(tick) # TODO needed?
        self.calculate(bid_price, ask_price)

        if '-STK' in self.vt_symbol:
            self.update_profit()

    def update_profit(self):
        paid = Decimal('0')
        received = Decimal('0')
        for execution in self.executions:
            if execution.direction == 'S':
                received += execution.price * execution.volume
            elif execution.direction == 'B':
                paid += execution.price * execution.volume
        self.profit = float(received - paid + self.current_value)
        self.put_event()

    @staticmethod
    def to_decimal(float_value) -> Decimal:
        return Decimal(str(float_value))

    def calculate(self, bid_price: Decimal, ask_price: Decimal):
        if self.pos == 0:
            if len(self.active_buy_orders) == 0:
                self.send_buy(ask_price)  # Buy using "Market Price"
            return

        expected_buy_orders = self.prices_calculator.next_buys(self.last_buy_price_d(), self.buy_orders_count)
        expected_sell_orders = self.prices_calculator.sell_prices(self.last_buy_price_d(), self.sell_orders_count)

        self.remove_unexpected_orders(expected_buy_orders, expected_sell_orders)

        active_buy_order_prices = {order.price for order in self.active_buy_orders.values()}
        active_sell_order_prices = {order.price for order in self.active_sell_orders.values()}

        missing_buy_orders = [price for price in expected_buy_orders if price not in active_buy_order_prices]
        missing_sell_orders = [price for price in expected_sell_orders if
                               price not in active_sell_order_prices and price]

        self.send_missing_orders(missing_buy_orders, missing_sell_orders)

    def on_bar(self, bar: BarData):  # TODO narazie po 1m barach, bo by default ticki pobiera z RData a nie z IB
        if not self.started:
            return
        # self.write_log("on bar1")  # bar.datetime.timestamp() > datetime.strptime("2022-01-20","%Y-%m-%d").timestamp()
        self.current_value = bar.close_price * self.pos
        self.calculate(self.to_decimal(bar.low_price), self.to_decimal(bar.high_price))

    def send_buy(self, buy_price: Decimal):
        if buy_price > self.max_buy_price:
            # self.write_log(f"Max buy price {self.max_buy_price} reached. Buy skipped")
            return

        for order in self.active_buy_orders.values():
            if buy_price == order.price:
                #  self.write_log(f"Buy order {normalized_buy_price} present. Skipping")
                return

        buy_volume: Decimal = self.volume_calculator.buy_volume(self.buy_amount_d(), buy_price, self.current_value)

        if buy_volume > 0:
            order_ids = self.buy(float(buy_price), float(buy_volume))
            self.write_log(f"BUY: {buy_volume} x {buy_price}")
            if order_ids:
                self.active_buy_orders[order_ids[0]] = Order(buy_price, buy_volume)

    def send_missing_orders(self, missing_buy_orders, missing_sell_orders):
        for buy_price in missing_buy_orders:
            self.send_buy(buy_price)

        volume_for_sell: Decimal = self.pos_d()
        for order in self.active_sell_orders.values():
            volume_for_sell -= order.volume

        for sell_price in missing_sell_orders:
            # if self.current_value + self.total_sold - self.total_bought > 0:
                # in profit, reduce if own > 66% max
                # self.write_log(f"ON PROFIT")
            sell_volume = self.volume_calculator.sell_volume(volume_for_sell, self.buy_amount_d(), sell_price)
            if sell_volume > 0:
                order_ids = self.sell(float(sell_price), float(sell_volume))
                self.write_log(f"SELL: {sell_volume} x {sell_price}")
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
            self.write_log("Cancelled BUY order")
        for orderId in sell_orders_to_close.keys():
            self.cancel_order(orderId)
            del self.active_sell_orders[orderId]
            self.write_log("Cancelled SELL order")

    def on_order(self, order: OrderData):
        pass

    def on_trade(self, trade: TradeData):
        self.write_log(f"OnTrade called lastBuyPrice: {trade.vt_symbol} {trade.direction}")
        old_price = self.last_buy_price_d()
        if trade.direction == Direction.LONG:
            self.last_buy_price = float(self.prices_calculator.normalize(self.to_decimal(trade.price)))
            if trade.vt_orderid in self.active_buy_orders:
                order = self.active_buy_orders[trade.vt_orderid]
                order.volume -= trade.volume
                if order.volume <= 0:
                    del self.active_buy_orders[trade.vt_orderid]
            self.total_bought += round(float(trade.price) * float(trade.volume) * 1.0006, 2)
        elif trade.direction == Direction.SHORT:
            self.last_buy_price = float(self.prices_calculator.higher_buy_price(self.last_buy_price_d()))
            if trade.vt_orderid in self.active_sell_orders:
                order = self.active_sell_orders[trade.vt_orderid]
                order.volume -= trade.volume
                if order.volume <= 0:
                    del self.active_sell_orders[trade.vt_orderid]
            self.total_sold += round(float(trade.price) * float(trade.volume) / 1.0006)

        self.executions.append(
            ExecutionTuple(trade.datetime.strftime("%Y-%m-%dT%H:%M:%SZ"), trade.direction.value, trade.price, float(trade.volume)))

        self.write_log(f"OnTrade updated lastBuyPrice: {old_price} -> {self.last_buy_price_d()}")

        self.put_event()

    def on_stop_order(self, stop_order: StopOrder):
        pass
