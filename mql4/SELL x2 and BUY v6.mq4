#property strict

#include <stdlib.mqh>
#include <ArraySortStruct.mqh>

input string expertName = "Sell*2+Buy";
input int expertId = 5;

// SELL orders params
input double positionSize = 0.01; //SELL position size
input int positionsToOpen = 5;
input double nextSellPositionByPoints = 50;
input int positionLimitsToOpen = 5;
input bool piramide = false;
input double inAccumulateFromPrice = 0; //Accumulate from

// BUY orders params
input double buyPositionSize = 0.01; //BUY position size
input int buyPositionCount = 2;
input double nextBuyPositionByPoints = 100;
input int maxExtraOppositeOrders = 2; // how many buy orders MORE than opened sell orders can be opened


// Stoch params
input int stoch_K_Period = 14;
input int stochTop = 79;
input int stochBtm = 20;

// internal params
double NA = 999999999;
string comment = "";
double accumulateFromPrice = 0;

class Position
  {
public:
   int ticket;
   double lots;
   double profit;
   double openPrice;
   //--- Default constructor
                     Position(){ ticket = -1; lots = 0.; profit = 0.; openPrice = 0.;};
   //--- Parametric constructor
   Position(int p_ticket, double p_lots, double p_profit, double p_openPrice){
      ticket = p_ticket;
      lots = p_lots;
      profit = p_profit;
      openPrice = p_openPrice;
   }
};

Position buyPositions[]; //sorted by openPrice Asc
Position sellLimitPositions[];
Position sellPositions[];

int totalBuyPositions = 0;
int totalSellLimitPositions = 0;
int totalSellPositions = 0;


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
   double bidPrice = MarketInfo(Symbol(), MODE_BID);
   accumulateFromPrice = inAccumulateFromPrice != 0.? inAccumulateFromPrice : bidPrice;
   OnTick();
  }

void OnDeinit(const int reason)
  {
   DeleteButtons();
  }


//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void OnTick(void)
  {
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
    ArrayFree(sellLimitPositions);
    ArrayFree(sellPositions);

   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && (expertId == OrderMagicNumber() || expertId == 0) && _Symbol == OrderSymbol()) {
         Position* p = new Position(OrderTicket(), OrderLots(), OrderProfit(), OrderOpenPrice());
         if (OrderType() == OP_SELL) {
            ArrayAppend(sellPositions, p);
         } else if (OrderType() == OP_BUY){
            ArrayAppend(buyPositions, p);
         } else if (OrderType() == OP_SELLLIMIT) {
            ArrayAppend(sellLimitPositions, p);
         }
         delete p;
      }
   }
   ArraySortStruct(buyPositions, openPrice);
   ArraySortStruct(sellLimitPositions, openPrice);
   ArraySortStruct(sellPositions, openPrice);

   totalBuyPositions = ArraySize(buyPositions);
   totalSellLimitPositions = ArraySize(sellLimitPositions);
   totalSellPositions = ArraySize(sellPositions);
}

void ArrayAppend(Position & array[], Position & position){
   int newSize = ArraySize(array) + 1;
   ArrayResize(array, newSize, 10);
   array[newSize-1] = position;
}

void OnTrade(){
   updateTakeProfitsGlobally();
}

void updateTakeProfitsGlobally() {
   // update SELL take profits if owns more SELLs than expected
   if (totalSellPositions > positionsToOpen){
      double totalLots = 0.0;
      double totalWagedOpenPrice = 0.0;

      //canibalize BUY and maybe SELL positions if way too many sells open
      int tooManyPositions = totalSellPositions - positionsToOpen *2;
      int sellsCountToPay = 0;
      int buysCountToPay = 0;
      if (tooManyPositions > 0 && totalBuyPositions > 0){
         int rescuePositionsCount = MathFloor(tooManyPositions/3);
         buysCountToPay = MathMin(rescuePositionsCount, totalBuyPositions);
         sellsCountToPay = MathMax(0, rescuePositionsCount - buysCountToPay);
         //paying opposite positions - pay using best one (faster recovery)
         for (int i=0; i < buysCountToPay; i++){
            Position position = buyPositions[0];
            totalLots -= position.lots;
            totalWagedOpenPrice -= position.openPrice * position.lots;
         }
      }

      // worst positions to close
      for (int i=0; i<totalSellPositions-positionsToOpen-sellsCountToPay; i++){
         Position position = sellPositions[i];
         totalLots += position.lots;
         totalWagedOpenPrice += position.openPrice * position.lots;
      }
      // canibalize best positions
      for (int i=totalSellPositions-1; i>=totalSellPositions-sellsCountToPay; i--){
         Position position = sellPositions[i];
         totalLots += position.lots;
         totalWagedOpenPrice += position.openPrice * position.lots;
      }


      //OrderCommission(); OrderSwap();
      //double profit = (takeProfitPrice - askPrice) / MODE_TICKSIZE * MODE_TICKVALUE * totalLots

      double takeProfitPrice = NormPrice(totalWagedOpenPrice / totalLots);
      for (int i=0; i<totalSellPositions-positionsToOpen-sellsCountToPay; i++){
         Position position = sellPositions[i];
         OrderModify(position.ticket, 0., 0., takeProfitPrice, 0);
      }
      for (int i=0; i < buysCountToPay; i++){
         Position position = buyPositions[i];
         double spread = MarketInfo(Symbol(), MODE_SPREAD) * MarketInfo(Symbol(), MODE_POINT);
         OrderModify(position.ticket, 0., takeProfitPrice - spread, 0., 0);
      }
      for (int i=totalSellPositions-sellsCountToPay-positionsToOpen; i<totalSellPositions-sellsCountToPay; i++){ //reset TP for kept positions
         Position position = sellPositions[i];
         OrderModify(position.ticket, 0., 0., 0., 0);
      }
      for (int i=totalSellPositions-1; i>=totalSellPositions-sellsCountToPay; i--){
         Position position = sellPositions[i];
         OrderModify(position.ticket, 0., 0., takeProfitPrice, 0);
      }

      comment += " TP: " + takeProfitPrice; //13169
   }

   // update BUY take profits if owns more BUYSs than expected
   if (totalBuyPositions > buyPositionCount){
      double totalLots = 0.0;
      double totalWagedOpenPrice = 0.0;
      for (int i=buyPositionCount; i < totalBuyPositions; i++){
         Position position = buyPositions[i];
         totalLots += position.lots;
         totalWagedOpenPrice += position.openPrice * position.lots;
      }

      double takeProfitPrice = NormPrice(totalWagedOpenPrice / totalLots);
      for (int i=buyPositionCount; i < totalBuyPositions; i++){
         Position position = buyPositions[i];
         OrderModify(position.ticket, 0., 0., takeProfitPrice, 0);
      }
   }
}

int ordersTotal = OrdersTotal();

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void calculate()
{
   stochDoubleBuyLogic();
   doubleSellLogic();
}

void doubleSellLogic(){
   double totalBuyProfit = 0.;
   double totalSellProfit = 0;

   for (int i=totalBuyPositions-1; i>=0; i--){
      totalBuyProfit += buyPositions[i].profit;
   }
   for (int i=totalSellPositions-1; i>=0; i--){
      totalSellProfit += sellPositions[i].profit;
   }

   double bidPrice = MarketInfo(Symbol(), MODE_BID);

   comment += ", SELL: " + totalSellPositions + ", Pending SELL: " + totalSellLimitPositions + ", BUY: " + totalBuyPositions + ", Profit: " + DoubleToStr(totalBuyProfit + totalSellProfit,2) ;

   // Place initial Orders
   if (totalSellPositions + totalSellLimitPositions == 0) {
      if (totalBuyPositions == 0 && buyPositionCount > 0){
         openOrder(OP_BUY);
      }
      if (bidPrice >= accumulateFromPrice){
         openOrder(OP_SELL);
      } else {
         openOrder(OP_SELLLIMIT, accumulateFromPrice);
      }
   } else if (totalSellLimitPositions < positionLimitsToOpen || buyPositionCount == 0) { //buy =0 to handle sellGap
      double nextOpenPrice;
      // Append new Limits if missing

      int toOpenCnt = positionLimitsToOpen - totalSellLimitPositions;
      if (totalSellLimitPositions > 0){
         nextOpenPrice = sellLimitPositions[totalSellLimitPositions-1].openPrice + nextSellPositionByPoints;
         if (totalSellPositions > 0){
            int sellGapSize = MathRound((sellLimitPositions[0].openPrice - sellPositions[totalSellPositions-1].openPrice) / nextSellPositionByPoints) - 1;
            if (sellGapSize > 0){
               //there is a sellLimit gap caused by some best sell orders closed as a rescue
               nextOpenPrice = sellPositions[totalSellPositions-1].openPrice + nextSellPositionByPoints;
               toOpenCnt = sellGapSize;
            }
         }
      } else {
         nextOpenPrice = sellPositions[totalSellPositions-1].openPrice + nextSellPositionByPoints;
      }

      nextOpenPrice = MathMax(nextOpenPrice, bidPrice); //current price much higher scenario
      for (int j=0; j < toOpenCnt; j++) {
         openOrder(OP_SELLLIMIT, nextOpenPrice);
         nextOpenPrice += nextSellPositionByPoints;
      }
   } else if (piramide && totalSellPositions > 0 && totalSellPositions < positionsToOpen && totalSellLimitPositions > 0) {
      // Price goes down (piramide sell) scenario, open buy orders as well if too few

      double nextPiramidePrice = sellPositions[0].openPrice - nextSellPositionByPoints;
      if (bidPrice <= nextPiramidePrice) {
         openOrder(OP_SELL);
         OrderDelete(sellLimitPositions[totalSellLimitPositions-1].ticket);
         if (totalBuyPositions < buyPositionCount) {
            openOrder(OP_BUY);
         }
      }
   }
}

void stochDoubleBuyLogic(){

   //open BUY orders on BUY signal
   if (buyPositionCount > 0) {
      double askPrice = MarketInfo(Symbol(), MODE_ASK);
      double minBoughtPrice = totalBuyPositions == 0 ? 9999999 : buyPositions[0].openPrice;
      double nextBuyPrice = totalBuyPositions == 0 ? askPrice : NormPrice(buyPositions[0].openPrice - nextBuyPositionByPoints);

      bool canOpenMoreBuyOrders = totalBuyPositions < totalSellPositions + maxExtraOppositeOrders;
      string stochSignal = stochSignal(PERIOD_M15);
      comment += "NextBuy: " + nextBuyPrice + (canOpenMoreBuyOrders ? "+" : "-") + ", Stoch: " + stochSignal;
      if (canOpenMoreBuyOrders && askPrice < minBoughtPrice && askPrice <= nextBuyPrice && stochSignal == "buy") {
         openOrder(OP_BUY);
      }
   }
}

void closeAllOrders() {
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if (_Symbol == OrderSymbol() && OrderMagicNumber() == expertId ){
            if (OrderType() == OP_BUY){
               OrderClose(OrderTicket(), OrderLots(), Bid, 0.01*Bid, Yellow);
            } else if (OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT) {
               OrderDelete(OrderTicket());
            } else if (OrderType() == OP_SELL) {
               OrderClose(OrderTicket(), OrderLots(), Ask, 0.01*Ask, Yellow);
            }
          }
      }
   }
}


void openOrder(int type, double price = 0){
   price = NormPrice(price);
   if (type == OP_BUY || type == OP_BUYLIMIT){
      if (price == 0) price = Ask;
         OrderSend(_Symbol, type, buyPositionSize, price, 0.001*Ask, 0, 0, _Symbol + " " + expertName + " " + expertId, expertId, 0, Green);
   } else if (type == OP_SELL || type == OP_SELLLIMIT) {
      if (price == 0) price = Bid;
         OrderSend(_Symbol, type, positionSize, price, 0.001*Bid, 0, 0, _Symbol + " " + expertName + " " + expertId, expertId, 0, Red);
   }
}


double NormPrice(double price) {
   double ts = MarketInfo(Symbol(), MODE_TICKSIZE);
   return( MathRound(price/ts)*ts );
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
     if (action == "BuyOne_btn") BuyOne_Button (action);
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

int BuyOne_Button (const string action)
  {
   openOrder(OP_BUY);
   return(0);
  }

void CreateButtons()
    {
     int Button_Height = (int)(Font_Size*2.8);
     if (!ButtonCreate (0, "SellOne_btn", 0, 002 + 000 + Move_X, 020 + 005 + Move_Y, Button_Width + 000, Button_Height, Corner, "S", Font_Type, Font_Size, Font_Color, clrTeal, clrYellow)) return;
     if (!ButtonCreate (0, "BuyOne_btn", 0, 002 + 035 + Move_X, 020 + 005 + Move_Y, Button_Width + 000, Button_Height, Corner, "B", Font_Type, Font_Size, Font_Color, clrTeal, clrYellow)) return;
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
     ButtonDelete (0, "BuyOne_btn");
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