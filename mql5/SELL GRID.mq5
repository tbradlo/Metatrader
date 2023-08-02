//+------------------------------------------------------------------+
//|                                              BUY GRID v3 avg.mq5 |
//|                                    Copyright 2023, Tomasz Bradlo |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Tomasz Bradlo"
#property version   "3.00"

#property strict

#include <ArraySortStruct.mqh>
#include <Generic\HashSet.mqh>



#include <Trade\Trade.mqh>
CTrade         m_trade;

/**
    v0.1, 24 Mar 2023
    Prototype of Grid Bot - similar to 3Commas Grid Bot
*/


//--- input parameters
input string expertName = "GRID sell";
input int expertId = 15;

// SELL (main positions)
input double sellPositionsSize = 0.01; //how big positions to open
input double nextSellPositionByPoints = 20;
input int sellPositionsToOpen = 20;
input int maxBuffer = 1; // keep X positions sell buffer to have sth to sell in case of rapid grow
input double takeProfitPoints = 30;

// BUY (hedge)
input double buyPositionsSize = 0.05; //BUY position size
input int buyPositionsToOpen = 4; //How many BUYs to keep open
input double nextBuyPositionByPoints = 30;

// BUY Stoch params
input int stoch_K_Period = 14;
input int stochTop = 79;
input int stochBtm = 20;


string headerLine = "";
string ownsLine = "";

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class Position
  {
public:
   int               ticket;
   double            lots;
   double            profit;
   double            openPrice;
   double            takeProfit;
   //--- Default constructor
                     Position() { ticket = -1; lots = 0.; profit = 0.; openPrice = 0.; takeProfit = 0.;};
   //--- Parametric constructor
                     Position(int p_ticket, double p_lots, double p_profit, double p_openPrice, double p_takeProfit)
     {
      ticket = p_ticket;
      lots = p_lots;
      profit = p_profit;
      openPrice = p_openPrice;
      takeProfit = p_takeProfit;
     }
  };

Position buyPositions[]; //sorted by openPrice Asc
Position sellPositions[];

CHashSet<double> existingTakeProfits; //sortedTakeProfits Asc

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

int handleStoch;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnInit(void)
  {
   CreateLabel("btmComment", 10, 15);
   CreateLabel("btmOwns", 10, 30);
   int D_Period = 3;
   int Slowing = 3;
   handleStoch = iStochastic(_Symbol, PERIOD_M15,stoch_K_Period,D_Period,Slowing,MODE_SMA,STO_LOWHIGH);
   m_trade.SetExpertMagicNumber(expertId);
   m_trade.SetMarginMode();
   m_trade.SetTypeFillingBySymbol(Symbol());
   m_trade.SetDeviationInPoints(2);

   CreateButtons();
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
//OnTick();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DeleteButtons();
  }


//+------------------------------------------------------------------+

//|
//+------------------------------------------------------------------+
void OnTick(void)
  {
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   headerLine = "";
   ownsLine = "";
   readPositions();

   calculate();

   WriteLabel("btmComment", headerLine);
   WriteLabel("btmOwns", ownsLine);
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void readPositions()
  {
   ArrayFree(buyPositions);
   ArrayFree(sellPositions);
   existingTakeProfits.Clear();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      long ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && (expertId == PositionGetInteger(POSITION_MAGIC) || expertId == 0) && _Symbol == PositionGetString(POSITION_SYMBOL))
        {
         Position* p = new Position(ticket, PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PROFIT), PositionGetDouble(POSITION_PRICE_OPEN), NormPrice(PositionGetDouble(POSITION_TP)));
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            ArrayAppend(buyPositions, p);
           }
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            ArrayAppend(sellPositions, p);
            existingTakeProfits.Add(p.takeProfit);
           }
         delete p;
        }
     }

   ArraySortStruct(buyPositions, openPrice);
   ArraySortStruct(sellPositions, openPrice);

   totalBuyPositions = ArraySize(buyPositions);
   totalSellPositions = ArraySize(sellPositions);

   double totalProfit = 0.;
   double totalSellLots = 0.;
   double totalBuyLots = 0.;

   for(int i=totalBuyPositions-1; i>=0; i--)
     {
      totalProfit += buyPositions[i].profit;
      totalBuyLots += buyPositions[i].lots;
     }
   for(int i=totalSellPositions-1; i>=0; i--)
     {
      totalProfit += sellPositions[i].profit;
      totalSellLots += sellPositions[i].lots;
     }

   headerLine += "Profit: " + DoubleToString(totalProfit,2) + " Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2) + " EQ: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2);
   ownsLine += "Sell: " + totalSellPositions + " / " + DoubleToString(totalSellLots,2) + " Buy: " + totalBuyPositions + " / " + DoubleToString(totalBuyLots,2) + " Total: " + (OrdersTotal() + PositionsTotal());
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTrade()
  {
   updateBuyTakeProfitsGlobally();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ArrayAppend(Position & array[], Position & position)
  {
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
   if(!stochDoubleBuyLogic())
     {
      openOrdersLogic();
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void openOrdersLogic()
  {

   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
// Place initial Orders
   if(totalBuyPositions == 0)
     {
      if(totalSellPositions == 0 && sellPositionsToOpen > 0)
        {
         openOrder(ORDER_TYPE_SELL);
         Print("sell opened");
        }
     }

    openBuyOrders();
  }


void openBuyOrders()
  {
      double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double closestTakeProfit = NormPrice(MathCeil((askPrice + takeProfitPoints) / nextPositionByPoints) * nextPositionByPoints);

      for (int i=0; i<=maxBuffer; i++){
         double tp = NormPrice(closestTakeProfit + i * nextPositionByPoints);
         if (!existingTakeProfits.Contains(tp)) {
            openOrder(ORDER_TYPE_BUY, 0, tp);
         }
      }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void openOrder(int type, double price = 0, double takeProfit = 0)
  {
   if(type == ORDER_TYPE_BUY)
     {
      m_trade.Buy(buyPositionsSize,_Symbol,price,0,NormPrice(takeProfit),expertName + " " + expertId);
     }
   else
      if(type == ORDER_TYPE_SELL)
        {
         m_trade.Sell(sellPositionsSize,_Symbol,price,0,NormPrice(takeProfit),expertName + " " + expertId);
        }
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double NormPrice(double price)
  {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return(MathRound(price/tickSize)*tickSize);
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool stochDoubleBuyLogic()
  {
//open BUY orders on BUY signal
   if(buyPositionsToOpen > 0)
     {
      double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double nextBuyPrice = totalBuyPositions == 0 ? askPrice : NormPrice(buyPositions[0].openPrice - nextBuyPositionByPoints);

      headerLine += " NextB: " + nextBuyPrice;
      if(askPrice <= nextBuyPrice && stochSignal() == "buy")
        {
         openOrder(ORDER_TYPE_BUY);
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void updateBuyTakeProfitsGlobally()
  {
// update BUY take profits if owns more SELLs than expected
   if(totalBuyPositions > buyPositionsToOpen)
     {

      //canibalize best and close 3rd best
      int bestPositionIdx = 0;
      int positionToCloseIdx = 2;

      Position bestPosition = buyPositions[bestPositionIdx];
      Position positionToClose = buyPositions[positionToCloseIdx];

      double totalLots = bestPosition.lots + positionToClose.lots;
      double takeProfitPrice = NormPrice((bestPosition.lots * bestPosition.openPrice + positionToClose.lots * positionToClose.openPrice)/totalLots); //TODO include SWAP

      if(bestPosition.takeProfit != takeProfitPrice)
        {
         m_trade.PositionModify(bestPosition.ticket, 0, takeProfitPrice);
         Print("BEST BUY TP DONE " + bestPosition.ticket + " " + bestPosition.openPrice + " " + bestPosition.takeProfit);
        }
      if(positionToClose.takeProfit != takeProfitPrice)
        {
         m_trade.PositionModify(positionToClose.ticket, 0, takeProfitPrice);
         Print("worst SEll TP DONE " + positionToClose.ticket + " " + positionToClose.openPrice + " " + positionToClose.takeProfit);
        }

      for(int i=0; i<totalBuyPositions; i++)
        {
         if(i != bestPositionIdx && i != positionToCloseIdx)
           {
            Position position = buyPositions[i];
            if(position.takeProfit != 0.)
              {
               m_trade.PositionModify(position.ticket, 0, 0);
               Print("Reset BUY TP DONE " + DoubleToString(position.ticket,0) + " " + position.openPrice);
              }
           }
        }
      headerLine += " BuyTP: " + takeProfitPrice;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string stochSignal()
  {
   double stoch[];

   CopyBuffer(handleStoch, MAIN_LINE,1,2,stoch);

//Comment("K0: " + stoch_K0 + " D0: " + stoch_D0 + " K1: " + stoch_K1 + " D1: " + stoch_D1);
//https://www.youtube.com/watch?v=YrzfNo8iKlw
   if(stoch[1] > stochTop && stoch[0] > stochTop)
      return "sell";

   if(stoch[1] > stochBtm && stoch[0] < stochBtm)
      return "buy";

   return NULL;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &action)
  {
   ResetLastError();
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(action == "SellOne_btn")
        {
         ButtonPressed(0, action);
        }
     }
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ButtonPressed(const long chartID, const string action)
  {
   ObjectSetInteger(chartID, action, OBJPROP_BORDER_COLOR, clrBlack);  // button pressed
   if(action == "SellOne_btn")
      SellOne_Button(action);
   Sleep(2000);
   ObjectSetInteger(chartID, action, OBJPROP_BORDER_COLOR, clrYellow);  // button unpressed
   ObjectSetInteger(chartID, action, OBJPROP_STATE, false);  // button unpressed
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int SellOne_Button(const string action)
  {
   openOrder(ORDER_TYPE_SELL);
   return(0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CreateButtons()
  {
   int Button_Height = (int)(Font_Size*2.8);
   if(!ButtonCreate(0, "SellOne_btn", 0, 10 + Move_X, 55 + Move_Y, Button_Width + 000, Button_Height, CORNER_LEFT_LOWER, "S", Font_Type, Font_Size, Font_Color, clrTeal, clrYellow))
      return;
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ButtonCreate(const long chart_ID = 0, const string name = "Button", const int sub_window = 0, const int x = 0, const int y = 0, const int width = 500,
                  const int height = 18, int corner = 0, const string text = "button", const string font = "Arial Bold",
                  const int font_size = 10, const color clr = clrBlack, const color back_clr = C'170,170,170', const color border_clr = clrNONE,
                  const bool state = false, const bool back = false, const bool selection = false, const bool hidden = true, const long z_order = 0)
  {
   ResetLastError();
   if(!ObjectCreate(chart_ID,name, OBJ_BUTTON, sub_window, 0, 0))
     {
      Print(__FUNCTION__, " : failed to create the button! Error code : ", GetLastError());
      return(false);
     }
   ObjectSetInteger(chart_ID,name,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(chart_ID,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(chart_ID, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chart_ID, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chart_ID, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(chart_ID, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(chart_ID, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(chart_ID, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(chart_ID, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(chart_ID, name, OBJPROP_BGCOLOR, back_clr);
   ObjectSetInteger(chart_ID, name, OBJPROP_BORDER_COLOR, border_clr);
   ObjectSetInteger(chart_ID, name, OBJPROP_BACK, back);
   ObjectSetInteger(chart_ID, name, OBJPROP_STATE, state);
   ObjectSetInteger(chart_ID, name, OBJPROP_SELECTABLE, selection);
   ObjectSetInteger(chart_ID, name, OBJPROP_SELECTED, selection);
   ObjectSetInteger(chart_ID, name, OBJPROP_HIDDEN, hidden);
   ObjectSetInteger(chart_ID, name, OBJPROP_ZORDER,z_order);
   ObjectSetString(chart_ID, name, OBJPROP_TEXT, text);
   ObjectSetString(chart_ID, name, OBJPROP_FONT, font);
   return(true);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteButtons()
  {
   ButtonDelete(0, "SellOne_btn");
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ButtonDelete(const long chart_ID=0, const string name="Button")
  {
   ResetLastError();
   if(!ObjectDelete(chart_ID,name))
     {
      Print(__FUNCTION__, ": Failed to delete the button! Error code = ", GetLastError());
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
void WriteLabel(string sName,string sValue)
  {
   ObjectSetString(0,sName,OBJPROP_TEXT,sValue);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CreateLabel(
   const string objectName,
   const int xDistance = 10,
   const int yDistance = 10
)
  {
//---  "btmComment",CORNER_LEFT_LOWER, ANCHOR_LEFT_LOWER, "Status",10,10
   if(ObjectCreate(0,objectName,OBJ_LABEL, 0,0,0))
     {
      ObjectSetInteger(0,objectName,OBJPROP_CORNER,CORNER_LEFT_LOWER);
      ObjectSetInteger(0,objectName,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0,objectName,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,objectName,OBJPROP_XDISTANCE,xDistance);
      ObjectSetInteger(0,objectName,OBJPROP_YDISTANCE,yDistance);
      // ObjectSetInteger(0,"btmComment",OBJPROP_BGCOLOR,clrGreen);
      // ObjectSetInteger(0,"btmComment",OBJPROP_COLOR, clrWhite);
      //ObjectSetInteger(0,"btmComment",OBJPROP_XSIZE, 1000);
      // ObjectSetInteger(0,"btmComment",OBJPROP_YSIZE, 10);
      //ObjectSetString(0, objectName, OBJPROP_FONT,"Arial");
      // ObjectSetInteger(0,"btmComment",OBJPROP_SELECTABLE,false);
     }
   else
      Print("Failed to create the object OBJ_LABEL btmComment, Error code = ", GetLastError());
  }
//+------------------------------------------------------------------+
