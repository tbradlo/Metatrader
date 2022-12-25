#property strict

/**
    v0.6, 25 Dec 2022
    Prototype of Grid Bot - similar to 3Commas Grid Bot
    Opens buy order every inNextPositionByPoints and sets Take Profit of takeProfitPoints.
    Good candidate can be NASDAQ being close to the bottom, maybe OIL as well.
    Profitable but requires a big depo.
*/

#include <stdlib.mqh>
#include <ArraySortStruct.mqh>

input string expertName = "GRID buy*2";
input int expertId = 8;

input double inPositionsSize = 0.01; //how big positions to open
input double inNextBuyPositionByPoints = 10;
input double sellBufferPoints = 40; // keep X points sell buffer to have sth to sell in case of rapid grow
input double minBuyPrice = 10000.; // Price at which Account Margin will be 100% (used for positionSize calculation)

input double takeProfitPoints = 10;


input double sellPositionSize = 0.50; //SELL position size
input int sellPositionsToOpen = 2; //How many SELLs to keep open
input double nextSellPositionByPoints = 125;

// Stoch params
input int stoch_K_Period = 14;
input int stochTop = 79;
input int stochBtm = 20;


string comment = "";

class Position
  {
public:
   int ticket;
   double lots;
   double profit;
   double openPrice;
   double takeProfit;
   //--- Default constructor
                     Position(){ ticket = -1; lots = 0.; profit = 0.; openPrice = 0.; takeProfit = 0.;};
   //--- Parametric constructor
   Position(int p_ticket, double p_lots, double p_profit, double p_openPrice, double p_takeProfit){
      ticket = p_ticket;
      lots = p_lots;
      profit = p_profit;
      openPrice = p_openPrice;
      takeProfit = p_takeProfit;
   }
};

Position buyPositions[]; //sorted by openPrice Asc
Position buyPositionsTp[]; //sorted by takeProfit Asc
Position sellPositions[];

int totalBuyPositions = 0;
int totalSellPositions = 0;

double nextPositionByPoints = 0.;
bool inactive = false;
double positionSize = 0;

extern int Corner = 2;
extern int Move_X = 0;
extern int Move_Y = 0;
extern string B00001 = "============================";
extern int Button_Width = 30;
extern string Font_Type = "Arial Bold";
extern color Font_Color = clrWhite;
extern int Font_Size = 8;


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnInit(void)
  {
     CreateButtons();
     double askPrice = MarketInfo(Symbol(), MODE_ASK);
     nextPositionByPoints = inNextBuyPositionByPoints;
     positionSize = inPositionsSize > 0 ? inPositionsSize : calculatePositionSize();
     OnTick();
  }

void OnDeinit(const int reason)
  {
    DeleteButtons();
  }


//+------------------------------------------------------------------+

//|
//+------------------------------------------------------------------+
void OnTick(void)
  {
    double bidPrice = MarketInfo(Symbol(), MODE_BID);

    comment = "";
    readPositions();

    calculate();

    if (ordersTotal != totalBuyPositions + totalSellPositions){
      OnTrade();
      ordersTotal = totalBuyPositions + totalSellPositions;
    }

    Comment(comment);
}


void readPositions(){
    ArrayFree(buyPositions);
    ArrayFree(sellPositions);
    ArrayFree(buyPositionsTp);

   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && (expertId == OrderMagicNumber() || expertId == 0) && _Symbol == OrderSymbol()) {
         Position* p = new Position(OrderTicket(), OrderLots(), OrderProfit(), OrderOpenPrice(), OrderTakeProfit());
         if (OrderType() == OP_BUY) {
            ArrayAppend(buyPositions, p);
            ArrayAppend(buyPositionsTp, p);
         } if (OrderType() == OP_SELL) {
            ArrayAppend(sellPositions, p);
         }
         delete p;
      }
   }
   ArraySortStruct(buyPositions, openPrice);
   ArraySortStruct(buyPositionsTp, takeProfit);
   ArraySortStruct(sellPositions, openPrice);

   totalBuyPositions = ArraySize(buyPositions);
   totalSellPositions = ArraySize(sellPositions);

   double totalProfit = 0.;
   double totalSellLots = 0.;

   for (int i=totalBuyPositions-1; i>=0; i--){
      totalProfit += buyPositions[i].profit;
   }
   for (int i=totalSellPositions-1; i>=0; i--){
      totalProfit += sellPositions[i].profit;
      totalSellLots += sellPositions[i].lots;
   }

   comment += ", SELL: " + totalSellPositions + "(" + totalSellLots + " lots), BUY: " + totalBuyPositions + ", Profit: " + DoubleToStr(totalProfit,2) + " Balance: " + DoubleToStr(AccountBalance(),2) + " EQ: " + DoubleToStr(AccountEquity(),2);
}

void OnTrade(){
  //calculatePositionSize();
}

void ArrayAppend(Position & array[], Position & position){
   int newSize = ArraySize(array) + 1;
   ArrayResize(array, newSize, 10);
   array[newSize-1] = position;
}

int ordersTotal = OrdersTotal();

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void calculate()
{
   stochDoubleSellLogic();
   openOrdersLogic();
}

void openOrdersLogic(){

   double askPrice = MarketInfo(Symbol(), MODE_ASK);
   // Place initial Orders
   if (totalBuyPositions == 0) {
      if (sellPositionsToOpen > 0){
         openOrder(OP_SELL);
      }
      openBuyOrders();
   } else if (buyPositionsTp[0].takeProfit - askPrice >= nextPositionByPoints) {
      openBuyOrders();
   }
}

//open one or two buy orders (in case of lack of "sell buffer")
void openBuyOrders(){
   double askPrice = MarketInfo(Symbol(), MODE_ASK);
   double closestClosePrice =  NormPrice(MathFloor(askPrice / nextPositionByPoints)*nextPositionByPoints);

   if (totalBuyPositions == 0) {
      //use standarized takeProfit positions (for buffer calculation purposes)
      double takeProfitPrice = NormPrice(MathFloor((askPrice+takeProfitPoints) / nextPositionByPoints)*nextPositionByPoints);
      openOrder(OP_BUY, 0, takeProfitPrice);
      if (sellBufferPoints > nextPositionByPoints){
         openOrder(OP_BUY, 0, takeProfitPrice+nextPositionByPoints);
      }
   } else {
      double closestTakeProfit =  NormPrice(MathCeil((askPrice+takeProfitPoints) / nextPositionByPoints)*nextPositionByPoints);
      double maxBufferedTp = closestTakeProfit + sellBufferPoints;

      int closestPosition = -1;
      int nextTpPosition = -1;
      for (int i=0; i<totalBuyPositions; i++){
         Position position = buyPositionsTp[i];
         if (position.takeProfit == closestTakeProfit){ // TP exists
            closestPosition = i;
            nextTpPosition = i+1;
            break;
         } else if (position.takeProfit > closestTakeProfit){ // bigger TP exist
            nextTpPosition = i;
            break;
         }
      }

      if (closestPosition == -1){
         openOrder(OP_BUY, 0, closestTakeProfit);
      }

      if (nextTpPosition == -1 && nextPositionByPoints < sellBufferPoints){
      comment += "B ";
         openOrder(OP_BUY, 0, closestTakeProfit+nextPositionByPoints);
      } else {
         //check if there is any TP gap for the buffer
         double nextTp = closestTakeProfit + nextPositionByPoints;
         for (int i=nextTpPosition; i<totalBuyPositions && nextTp <= maxBufferedTp; i++){
            Position position = buyPositionsTp[i];
            if (position.takeProfit > nextTp){
               openOrder(OP_BUY, 0, nextTp);
               break;
               return;
            } else if (position.takeProfit == nextTp){
               nextTp = nextTp + nextPositionByPoints;
            }
         }
         //check np gap but missing at the top
         if (nextTp <= maxBufferedTp){
            openOrder(OP_BUY, 0, nextTp);
            return;
         }
      }
   }
}

void openOrder(int type, double price = 0, double takeProfit = 0){
   if (positionSize == 0){
       calculatePositionSize();
   }
   if (positionSize == -1){
      return;
   }
   if (type == OP_BUY){
      if (price == 0) price = Ask;

      double takeProfit =

      OrderSend(_Symbol, type, positionSize, price, 0.001*Ask, 0, NormPrice(takeProfit), expertName + " " + expertId, expertId, 0, Green);
   } else if (type == OP_SELL || type == OP_SELLLIMIT) {
      if (price == 0) price = Bid;
      OrderSend(_Symbol, type, sellPositionSize, price, 0.01*Bid, 0, NormPrice(takeProfit), expertName + " " + expertId, expertId, 0, Red);
   }
}


double NormPrice(double price) {
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   return( MathRound(price/tickSize)*tickSize );
}

double calculatePositionSize(){
      double bidPrice = MarketInfo(Symbol(), MODE_BID);
      double askPrice = MarketInfo(Symbol(), MODE_ASK);
      double pointValuePerLot = MarketInfo(_Symbol, MODE_TICKVALUE) / MarketInfo(_Symbol, MODE_TICKSIZE);
      double maxAdditionalLoss = 0;
      double totalOpenedLots = 0;
      for (int i=0; i < totalBuyPositions; i++){
         totalOpenedLots = buyPositions[i].lots;
      }
      maxAdditionalLoss = (minBuyPrice-bidPrice) * totalOpenedLots * pointValuePerLot;
      comment += " Max additional loss: " + DoubleToStr(maxAdditionalLoss,2) + "@" + minBuyPrice;

      double equityAtLowestPrice = AccountEquity()+maxAdditionalLoss;
      double marginRequredAtLowestPrice = MarginAtMinBuyPrice(totalOpenedLots, pointValuePerLot);

      comment += " equityAtLowestPrice: " + DoubleToStr(equityAtLowestPrice,2) + " marginRequredAtLowestPrice: " + DoubleToStr(marginRequredAtLowestPrice,2) ;

      double nextOpenPrice = totalBuyPositions > 0 ? buyPositions[0].openPrice - nextPositionByPoints : askPrice;
      int positionsToOpen = MathFloor((nextOpenPrice - minBuyPrice)/nextPositionByPoints + 1);

      comment += " positionsToOpen: " + positionsToOpen;

      // 9936-2 = margin(0.01*635) + (12352-6000)*0.01*635*1
      // 9934 = 0.002*635*1*6000/30 + 6352*0.002*635*1
      // (9936-2) / (635*1*6000/30 + 6352*635*1) = 0.02
      // equityAtLowestPrice - marginRequredAtLowestPrice = marginRequredAtLowestPrice(newPositionsSize? * positionsToOpen)+ (askPrice-minBuyPrice) * newPositionsSize? * positionsToOpen * pointValuePerLot
      // = >
      double newPositionsSize = (equityAtLowestPrice - marginRequredAtLowestPrice) / (positionsToOpen * pointValuePerLot * minBuyPrice / AccountLeverage() + ((askPrice-minBuyPrice)*positionsToOpen*pointValuePerLot));
      newPositionsSize = MathFloor(newPositionsSize / MarketInfo(_Symbol, MODE_LOTSTEP)) * MarketInfo(_Symbol, MODE_LOTSTEP);

      positionSize = newPositionsSize == 0 ? -1 : newPositionsSize;
      comment += " NewPositionSize: " + DoubleToStr(positionSize,2) + " lotstep: " + MarketInfo(_Symbol, MODE_LOTSTEP);
      return positionSize;
}

double MarginAtMinBuyPrice(double lots, double pointValuePerLot)
{
   return lots * pointValuePerLot * minBuyPrice / AccountLeverage();
}

void stochDoubleSellLogic(){
     //open SELL orders on SELL signal
   if (sellPositionsToOpen > 0) {
      double bidPrice = MarketInfo(Symbol(), MODE_BID);
      double nextSellPrice = totalSellPositions == 0 ? bidPrice : NormPrice(sellPositions[totalSellPositions-1].openPrice + nextSellPositionByPoints);

      comment += " NextSell: " + nextSellPrice;
      if (bidPrice >= nextSellPrice && stochSignal(PERIOD_M15) == "sell") {
         openOrder(OP_SELL);
      }
   }
}

string stochSignal(int period) {
   string signal = NULL;

   int D_Period = 3;
   int Slowing = 3;
    //double ClosePriceYesterday = ClosePriceYesterday();
    double stoch_K0 = iStochastic(_Symbol, period, stoch_K_Period, D_Period, Slowing, MODE_SMA, 0, MODE_MAIN, 0); //current
    double stoch_D0 = iStochastic(_Symbol, period, stoch_K_Period, D_Period, Slowing, MODE_SMA, 0, MODE_SIGNAL, 0); //current
    double stoch_K1 = iStochastic(_Symbol, period, stoch_K_Period, D_Period, Slowing, MODE_SMA, 0, MODE_MAIN, 1); //last
    double stoch_D1 = iStochastic(_Symbol, period, stoch_K_Period, D_Period, Slowing, MODE_SMA, 0, MODE_SIGNAL, 1); //last

   //Comment("K0: " + stoch_K0 + " D0: " + stoch_D0 + " K1: " + stoch_K1 + " D1: " + stoch_D1);

    if (stoch_K0 > stochTop && stoch_D0 > stochTop)
      if (stoch_D0 > stoch_K0 && stoch_D1 < stoch_K1){
         signal = "sell";
      }

    if (stoch_K0 < stochBtm && stoch_D0 < stochBtm)
      if (stoch_D0 < stoch_K0 && stoch_D1 > stoch_K1) {
         signal = "buy";
      }
    return signal;
}

void OnChartEvent (const int id, const long &lparam, const double &dparam, const string &action)
    {
     ResetLastError();
     if (id == CHARTEVENT_OBJECT_CLICK) {if (ObjectType (action) == OBJ_BUTTON) {ButtonPressed (0, action);}}
    }


void ButtonPressed (const long chartID, const string action)
    {
     ObjectSetInteger (chartID, action, OBJPROP_BORDER_COLOR, clrBlack); // button pressed
     if (action == "SellOne_btn") SellOne_Button (action);
     Sleep (2000);
     ObjectSetInteger (chartID, action, OBJPROP_BORDER_COLOR, clrYellow); // button unpressed
     ObjectSetInteger (chartID, action, OBJPROP_STATE, false); // button unpressed
     ChartRedraw();
    }

int SellOne_Button (const string action)
  {
   openOrder(OP_SELL);
   return(0);
  }

 void CreateButtons()
     {
      int Button_Height = (int)(Font_Size*2.8);
      if (!ButtonCreate (0, "SellOne_btn", 0, 002 + 000 + Move_X, 020 + 005 + Move_Y, Button_Width + 000, Button_Height, Corner, "S", Font_Type, Font_Size, Font_Color, clrTeal, clrYellow)) return;
      ChartRedraw();
     }

 bool ButtonCreate (const long chart_ID = 0, const string name = "Button", const int sub_window = 0, const int x = 0, const int y = 0, const int width = 500,
                    const int height = 18, int corner = 0, const string text = "button", const string font = "Arial Bold",
                    const int font_size = 10, const color clr = clrBlack, const color back_clr = C'170,170,170', const color border_clr = clrNONE,
                    const bool state = false, const bool back = false, const bool selection = false, const bool hidden = true, const long z_order = 0)
   {
    ResetLastError();
    if (!ObjectCreate (chart_ID,name, OBJ_BUTTON, sub_window, 0, 0))
      {
       Print (__FUNCTION__, " : failed to create the button! Error code : ", GetLastError());
       return(false);
      }
    ObjectSetInteger (chart_ID, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger (chart_ID, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger (chart_ID, name, OBJPROP_XSIZE, width);
    ObjectSetInteger (chart_ID, name, OBJPROP_YSIZE, height);
    ObjectSetInteger (chart_ID, name, OBJPROP_CORNER, corner);
    ObjectSetInteger (chart_ID, name, OBJPROP_FONTSIZE, font_size);
    ObjectSetInteger (chart_ID, name, OBJPROP_COLOR, clr);
    ObjectSetInteger (chart_ID, name, OBJPROP_BGCOLOR, back_clr);
    ObjectSetInteger (chart_ID, name, OBJPROP_BORDER_COLOR, border_clr);
    ObjectSetInteger (chart_ID, name, OBJPROP_BACK, back);
    ObjectSetInteger (chart_ID, name, OBJPROP_STATE, state);
    ObjectSetInteger (chart_ID, name, OBJPROP_SELECTABLE, selection);
    ObjectSetInteger (chart_ID, name, OBJPROP_SELECTED, selection);
    ObjectSetInteger (chart_ID, name, OBJPROP_HIDDEN, hidden);
    ObjectSetInteger (chart_ID, name, OBJPROP_ZORDER,z_order);
    ObjectSetString  (chart_ID, name, OBJPROP_TEXT, text);
    ObjectSetString  (chart_ID, name, OBJPROP_FONT, font);
    return(true);
   }

  void DeleteButtons()
     {
      ButtonDelete (0, "SellOne_btn");
     }

 bool ButtonDelete (const long chart_ID=0, const string name="Button")
   {
    ResetLastError();
    if (!ObjectDelete (chart_ID,name))
      {
       Print (__FUNCTION__, ": Failed to delete the button! Error code = ", GetLastError());
       return(false);
      }
    return(true);
   }