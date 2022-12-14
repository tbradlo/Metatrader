#property strict

#include <stdlib.mqh>
#include <ArraySortStruct.mqh>

input string expertName = "OnSignal";
input int expertId = 6;

input double takeProfit = 100;

// SELL orders params
input double sellPositionSize = 0.01; //SELL position size
input int sellPositionsToOpen = 1;
input double nextSellPositionByPoints = 300;
input int maxExtraSellPositions = 5; //Max unmatched SELL positions
input double inSellFromPrice = 0; //Sell from

// BUY orders params
input double buyPositionSize = 0.01; //BUY position size
input int buyPositionToOpen = 1;
input double nextBuyPositionByPoints = 300;
input int maxExtraBuyPositions = 5; // Max unmatched BUY positions
input double inBuyFromPrice = 0; //BUY from


// Stoch params
input int stoch_K_Period = 14;//
input int stochTop = 79;
input int stochBtm = 20;

// internal params
string comment = "";
double sellFromPrice = 0;
double buyFromPrice = 0;

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
Position buyLimitPositions[];
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

double totalProfit = 0;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnInit(void)
  {
   CreateButtons();
   sellFromPrice = inSellFromPrice != 0.? inSellFromPrice : MarketInfo(Symbol(), MODE_BID);
   buyFromPrice = inBuyFromPrice != 0.? inBuyFromPrice : MarketInfo(Symbol(), MODE_ASK);
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

    if (totalProfit >= takeProfit){
      closeAllOrders();
    }

    Comment(comment);
}

void readPositions(){
    ArrayFree(buyPositions);
    ArrayFree(sellLimitPositions);
    ArrayFree(sellPositions);

   double breakEvenPrice = 0;
   double totalBuyWagedOpenPrice = 0;
   double totalBuyLots = 0;
   double totalSellWagedOpenPrice = 0;
   double totalSellLots = 0;
   totalProfit = 0;

   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && (expertId == OrderMagicNumber() || expertId == 0) && _Symbol == OrderSymbol()) {
         Position* p = new Position(OrderTicket(), OrderLots(), OrderProfit(), OrderOpenPrice());
         if (OrderType() == OP_SELL) {
            ArrayAppend(sellPositions, p);
            totalProfit += p.profit;
            totalSellWagedOpenPrice += p.openPrice * p.lots;
            totalSellLots += p.lots;
         } else if (OrderType() == OP_BUY){
            ArrayAppend(buyPositions, p);
            totalProfit += p.profit;
            totalBuyWagedOpenPrice += p.openPrice * p.lots;
            totalBuyLots += p.lots;
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


   if (totalBuyPositions > 0 && totalSellPositions == 0){
      breakEvenPrice = NormPrice(totalBuyWagedOpenPrice / totalBuyLots);
   } else if(totalSellPositions > 0 && totalBuyPositions == 0){
      breakEvenPrice = NormPrice(totalSellWagedOpenPrice / totalSellLots);
   } else if (totalBuyPositions > 0 && totalSellPositions > 0 && totalBuyPositions != totalSellPositions){
     // equation calculated from: (1750-BE)*0,01 - (1800-BE)*0,03 == 0) => BE = 1825
      double buyAvgPrice = totalBuyWagedOpenPrice / totalBuyLots;
      double sellAvgPrice = totalSellWagedOpenPrice / totalSellLots;
      breakEvenPrice = MathAbs(NormPrice((buyAvgPrice*totalBuyLots - sellAvgPrice*totalSellLots) / (totalSellLots - totalBuyLots)));
   } else {
      breakEvenPrice = 0;
   }

   comment += " BUY: " + totalBuyPositions + " SELL: " + totalSellPositions;
   comment += " BE: " + breakEvenPrice + " Profit: " + DoubleToStr(totalProfit,2);
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
   if (totalSellPositions > sellPositionsToOpen){
      double totalLots = 0.0;
      double totalWagedOpenPrice = 0.0;

      // worst positions to close
      for (int i=0; i<totalSellPositions-sellPositionsToOpen; i++){
         Position position = sellPositions[i];
         totalLots += position.lots;
         totalWagedOpenPrice += position.openPrice * position.lots;
      }

      //OrderCommission(); OrderSwap();
      //double profit = (takeProfitPrice - askPrice) / MODE_TICKSIZE * MODE_TICKVALUE * totalLots

      double takeProfitPrice = NormPrice(totalWagedOpenPrice / totalLots);
      for (int i=0; i<totalSellPositions-sellPositionsToOpen; i++){
         Position position = sellPositions[i];
         OrderModify(position.ticket, 0., 0., takeProfitPrice, 0);
      }
      comment += " TP: " + takeProfitPrice; //13169
   }

   // update BUY take profits if owns more BUYSs than expected
   if (totalBuyPositions > buyPositionToOpen){
      double totalLots = 0.0;
      double totalWagedOpenPrice = 0.0;
      for (int i=buyPositionToOpen; i < totalBuyPositions; i++){
         Position position = buyPositions[i];
         totalLots += position.lots;
         totalWagedOpenPrice += position.openPrice * position.lots;
      }

      double takeProfitPrice = NormPrice(totalWagedOpenPrice / totalLots);
      for (int i=buyPositionToOpen; i < totalBuyPositions; i++){
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
   doubleBuyLogic();
   doubleSellLogic();
}

void doubleSellLogic(){
   //open SELL orders on SELL signal
   if (sellPositionsToOpen > 0) {
      double bidPrice = MarketInfo(Symbol(), MODE_BID);
      double maxSoldPrice = totalSellPositions == 0 ? 0 : sellPositions[totalSellPositions-1].openPrice;
      double nextSellPrice = totalSellPositions == 0 ? bidPrice : NormPrice(sellPositions[totalSellPositions-1].openPrice + nextSellPositionByPoints);

      bool canOpenMoreSellOrders = totalSellPositions < totalBuyPositions + maxExtraSellPositions;
      string stochSignal = stochSignal(PERIOD_M15);
      comment += "NextSell: " + nextSellPrice + (canOpenMoreSellOrders ? "+" : "-");
      if (canOpenMoreSellOrders && bidPrice > maxSoldPrice && bidPrice >= nextSellPrice && stochSignal == "sell") {
         openOrder(OP_SELL);
      }
   }

}

void doubleBuyLogic(){
   //open BUY orders on BUY signal
   if (buyPositionToOpen > 0) {
      double askPrice = MarketInfo(Symbol(), MODE_ASK);
      double minBoughtPrice = totalBuyPositions == 0 ? 9999999 : buyPositions[0].openPrice;
      double nextBuyPrice = totalBuyPositions == 0 ? askPrice : NormPrice(buyPositions[0].openPrice - nextBuyPositionByPoints);

      bool canOpenMoreBuyOrders = totalBuyPositions < totalSellPositions + maxExtraBuyPositions;
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
         OrderSend(_Symbol, type, sellPositionSize, price, 0.001*Bid, 0, 0, _Symbol + " " + expertName + " " + expertId, expertId, 0, Red);
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