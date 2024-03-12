//+------------------------------------------------------------------+
//|                                              BUY GRID v5 avg.mq5 |
//|                                    Copyright 2023, Tomasz Bradlo |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Tomasz Bradlo"
#property version   "1.00"

#property strict

#include <ArraySortStruct.mqh>
#include <Generic\HashSet.mqh>



#include <Trade\Trade.mqh>
CTrade         m_trade;

/**
    v0.1, 20 May 2023
    Sell Grid Bot
    Opens buy order every inNextPositionByPoints and sets Take Profit of takeProfitPoints.
*/


//--- input parameters
input string expertName = "GRID Sell";
input int expertId = 11;

input double sellPositionSize = 0.01;
input double nextSellPositionByPoints = 14;
input double takeProfitPoints = 140;
input int maxBuffer = 5;
input int maxSellPositions = 200;

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

Position sellPositions[];

CHashSet<double> existingTakeProfits; //sortedTakeProfits Asc

int totalSellPositions = 0;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnInit(void)
  {
   CreateLabel("btmCommentS", 10, 15);
   CreateLabel("btmOwnsS", 10, 30);

   m_trade.SetExpertMagicNumber(expertId);
   m_trade.SetMarginMode();
   m_trade.SetTypeFillingBySymbol(Symbol());
   m_trade.SetDeviationInPoints(2);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {

  }


//+------------------------------------------------------------------+
//|
//+------------------------------------------------------------------+
void OnTick(void)
  {
   headerLine = "";
   ownsLine = "";
   readPositions();

   calculate();

   WriteLabel("btmCommentS", headerLine);
   WriteLabel("btmOwnsS", ownsLine);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void readPositions()
  {
   ArrayFree(sellPositions);
   existingTakeProfits.Clear();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      long ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && (expertId == PositionGetInteger(POSITION_MAGIC) || expertId == 0) && _Symbol == PositionGetString(POSITION_SYMBOL))
        {
         Position* p = new Position(ticket, PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PROFIT), PositionGetDouble(POSITION_PRICE_OPEN), NormPrice(PositionGetDouble(POSITION_TP)));
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            ArrayAppend(sellPositions, p);
            existingTakeProfits.Add(p.takeProfit);
           }
         delete p;
        }
     }

   ArraySortStruct(sellPositions, openPrice);
   totalSellPositions = ArraySize(sellPositions);

   double totalProfit = 0.;
   double totalSellLots = 0.;

   for(int i=totalSellPositions-1; i>=0; i--)
     {
      totalProfit += sellPositions[i].profit;
      totalSellLots += sellPositions[i].lots;
     }

   headerLine += "Profit: " + DoubleToString(totalProfit,2) + " Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2) + " EQ: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2);
   ownsLine += "Sell: " + totalSellPositions + " / " + DoubleToString(totalSellLots,2) + " Total: " + (OrdersTotal() + PositionsTotal());
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTrade()
  {

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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void calculate()
  {
   openSellOrdersLogic();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void openSellOrdersLogic()
  {
   if(totalSellPositions >= maxSellPositions)
     {
      return;
     }

   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double closestTakeProfit = NormPrice(MathFloor((bidPrice - takeProfitPoints) / nextSellPositionByPoints) * nextSellPositionByPoints);

   ownsLine += " NextS: " + (closestTakeProfit + takeProfitPoints + nextSellPositionByPoints);

   if(!existingTakeProfits.Contains(closestTakeProfit))
     {
      openOrder(ORDER_TYPE_SELL, 0, closestTakeProfit); //regular
     }
   else
     {
      double nextBufferedSell = sellPositions[totalSellPositions-1].openPrice + nextSellPositionByPoints/2;
      ownsLine += " / " + nextBufferedSell;

      if(existingTakeProfits.Count() < maxBuffer && nextBufferedSell > bidPrice)
        {
         openOrder(ORDER_TYPE_SELL, 0, nextTakeProfit(closestTakeProfit)); //buffer in between
        }
      }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int nextTakeProfit(double lastSetTp)
  {
   return MathMin(lastSetTp, sellPositions[0].takeProfit) - nextSellPositionByPoints;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void openOrder(int type, double price = 0, double takeProfit = 0)
  {
   if(type == ORDER_TYPE_SELL)
     {
      m_trade.Sell(sellPositionSize,_Symbol,price,0,NormPrice(takeProfit),expertName + " " + expertId);
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
