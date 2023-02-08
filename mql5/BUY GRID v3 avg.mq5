//+------------------------------------------------------------------+
//|                                              BUY GRID v3 avg.mq5 |
//|                                    Copyright 2023, Tomasz Bradlo |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Tomasz Bradlo"
#property version   "3.00"

#property strict

#include <ArraySortStruct.mqh>

#include <Trade\Trade.mqh>
CTrade         m_trade;

/**
    v0.7, 25 Dec 2022
    Prototype of Grid Bot - similar to 3Commas Grid Bot
    Opens buy order every inNextPositionByPoints and sets Take Profit of takeProfitPoints.
    Good candidate can be NASDAQ being close to the bottom, maybe OIL as well.
    Profitable but requires a big depo.
*/


//--- input parameters
input string expertName = "GRID buy";
input int expertId = 8;

input double inPositionsSize = 0.1; //how big positions to open
input double inNextBuyPositionByPoints = 20;
input double sellBufferPoints = 10; // keep X points sell buffer to have sth to sell in case of rapid grow
input double minBuyPrice = 10000.; // Price at which Account Margin will be 100% (used for positionSize calculation)

input double takeProfitPoints = 30;


input double sellPositionSize = 0.30; //SELL position size
input int sellPositionsToOpen = 2; //How many SELLs to keep open
input double nextSellPositionByPoints = 250;

// Stoch params
input int stoch_K_Period = 14;
input int stochTop = 79;
input int stochBtm = 20;


string headerLine = "";

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

int handleStoch;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnInit(void)
  {
   int D_Period = 3;
   int Slowing = 3;
   handleStoch = iStochastic(_Symbol, PERIOD_M15,stoch_K_Period,D_Period,Slowing,MODE_SMA,STO_LOWHIGH);
   m_trade.SetExpertMagicNumber(expertId);
   m_trade.SetMarginMode();
   m_trade.SetTypeFillingBySymbol(Symbol());
   m_trade.SetDeviationInPoints(2);

   CreateButtons();
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   nextPositionByPoints = inNextBuyPositionByPoints;
   positionSize = inPositionsSize > 0 ? inPositionsSize : calculatePositionSize();
   OnTick();
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
   readPositions();

   calculate();

   if(ordersTotal != totalBuyPositions + totalSellPositions)
     {
      OnTrade();
      ordersTotal = totalBuyPositions + totalSellPositions;
     }

   Comment(headerLine);
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void readPositions()
  {
   ArrayFree(buyPositions);
   ArrayFree(sellPositions);
   ArrayFree(buyPositionsTp);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      long ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && (expertId == PositionGetInteger(POSITION_MAGIC) || expertId == 0) && _Symbol == PositionGetString(POSITION_SYMBOL))
        {
         Position* p = new Position(ticket, PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PROFIT), PositionGetDouble(POSITION_PRICE_OPEN), NormPrice(PositionGetDouble(POSITION_TP)));
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            ArrayAppend(buyPositions, p);
            ArrayAppend(buyPositionsTp, p);
           }
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
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

   headerLine += ", SELL: " + totalSellPositions + "(" + totalSellLots + " lots), BUY: " + totalBuyPositions + "(" + totalBuyLots + " lots), Profit: "
                 + DoubleToString(totalProfit,2) + " Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2) + " EQ: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2) + " total: " + OrdersTotal();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTrade()
  {
   updateTakeProfitsGlobally();
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
   stochDoubleSellLogic();
   openOrdersLogic();
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
        }
      openBuyOrders();
     }
   else
      if(buyPositionsTp[0].takeProfit - askPrice >= nextPositionByPoints)
        {
          openBuyOrders();
        }
  }

//open one or two buy orders (in case of lack of "sell buffer")
void openBuyOrders()
  {
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double closestClosePrice =  NormPrice(MathFloor(askPrice / nextPositionByPoints)*nextPositionByPoints);

   if(totalBuyPositions == 0)
     {
      //use standarized takeProfit positions (for buffer calculation purposes)
      double takeProfitPrice = NormPrice(MathCeil((askPrice+takeProfitPoints) / nextPositionByPoints)*nextPositionByPoints);
      openOrder(ORDER_TYPE_BUY, 0, takeProfitPrice);
      if(sellBufferPoints > nextPositionByPoints)
        {
         openOrder(ORDER_TYPE_BUY, 0, takeProfitPrice+nextPositionByPoints);
        }
     }
   else
     {
      double closestTakeProfit =  NormPrice(MathCeil((askPrice+takeProfitPoints) / nextPositionByPoints)*nextPositionByPoints); //11420
      headerLine += " closest TP: " + closestTakeProfit;
      double maxBufferedTp = closestTakeProfit + sellBufferPoints; //11460

      headerLine += " bp0tp: " + buyPositionsTp[0].takeProfit;
      int closestPosition = -1;
      int nextTpPosition = -1;
      for(int i=0; i<totalBuyPositions; i++)
        {
         Position position = buyPositionsTp[i];
         if(position.takeProfit == closestTakeProfit)   // TP exists
           {
            closestPosition = i;
            nextTpPosition = i+1;
            headerLine += "x1x";
            break;
           }
         else
            if(position.takeProfit > closestTakeProfit)   // bigger TP exist
              {
               nextTpPosition = i;
               headerLine += "y2y";
               break;
              }
        }
      headerLine += " nextTP: " + closestPosition;

      if(closestPosition == -1)
        {
         headerLine += "SHOULD OPEN";
         openOrder(ORDER_TYPE_BUY, 0, closestTakeProfit);
        }

      if(nextTpPosition == -1 && nextPositionByPoints < sellBufferPoints)
        {
         openOrder(ORDER_TYPE_BUY, 0, closestTakeProfit+nextPositionByPoints);
        }
      else
        {
         //check if there is any TP gap for the buffer
         double nextTp = closestTakeProfit + nextPositionByPoints;
         for(int i=nextTpPosition; i<totalBuyPositions && nextTp <= maxBufferedTp; i++)
           {
            Position position = buyPositionsTp[i];
            if(position.takeProfit > nextTp)
              {
               headerLine += " G1";
               openOrder(ORDER_TYPE_BUY, 0, nextTp);
               return;
              }
            else
               if(position.takeProfit == nextTp)
                 {
                  nextTp = nextTp + nextPositionByPoints;
                 }
           }
         //check np gap but missing at the top
         if(nextTp <= maxBufferedTp)
           {
            headerLine += "G2";
            openOrder(ORDER_TYPE_BUY, 0, nextTp);
            return;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void openOrder(int type, double price = 0, double takeProfit = 0)
  {
   if(positionSize == 0)
     {
      calculatePositionSize();
     }
   if(positionSize == -1)
     {
      return;
     }
   if(type == ORDER_TYPE_BUY)
     {
      m_trade.Buy(positionSize,_Symbol,price,0,NormPrice(takeProfit),expertName + " " + expertId);
     }
   else
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
//|                                                                  |
//+------------------------------------------------------------------+
double calculatePositionSize()
  {
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pointValuePerLot = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double maxAdditionalLoss = 0;
   double totalOpenedLots = 0;
   for(int i=0; i < totalBuyPositions; i++)
     {
      totalOpenedLots = buyPositions[i].lots;
     }
   maxAdditionalLoss = (minBuyPrice-bidPrice) * totalOpenedLots * pointValuePerLot;
   headerLine += " Max additional loss: " + DoubleToString(maxAdditionalLoss,2) + "@" + minBuyPrice;

   double equityAtLowestPrice = AccountInfoDouble(ACCOUNT_EQUITY)+maxAdditionalLoss;
   double marginRequredAtLowestPrice = MarginAtMinBuyPrice(totalOpenedLots, pointValuePerLot);

   headerLine += " equityAtLowestPrice: " + DoubleToString(equityAtLowestPrice,2) + " marginRequredAtLowestPrice: " + DoubleToString(marginRequredAtLowestPrice,2) ;

   double nextOpenPrice = totalBuyPositions > 0 ? buyPositions[0].openPrice - nextPositionByPoints : askPrice;
   int positionsToOpen = MathFloor((nextOpenPrice - minBuyPrice)/nextPositionByPoints + 1);

   headerLine += " positionsToOpen: " + positionsToOpen;

// 9936-2 = margin(0.01*635) + (12352-6000)*0.01*635*1
// 9934 = 0.002*635*1*6000/30 + 6352*0.002*635*1
// (9936-2) / (635*1*6000/30 + 6352*635*1) = 0.02
// equityAtLowestPrice - marginRequredAtLowestPrice = marginRequredAtLowestPrice(newPositionsSize? * positionsToOpen)+ (askPrice-minBuyPrice) * newPositionsSize? * positionsToOpen * pointValuePerLot
// = >
   int leverage = CalculateSymbolLeverage(_Symbol);
   double newPositionsSize = (equityAtLowestPrice - marginRequredAtLowestPrice) / (positionsToOpen * pointValuePerLot * minBuyPrice / leverage + ((askPrice-minBuyPrice)*positionsToOpen*pointValuePerLot));
   newPositionsSize = MathFloor(newPositionsSize / SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)) * SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   positionSize = newPositionsSize == 0 ? -1 : newPositionsSize;
   headerLine += " NewPositionSize: " + DoubleToString(positionSize,2) + " lotstep: " + SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return positionSize;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int CalculateSymbolLeverage(const string symbol)
  {

   int leverage=-1;
   double margin=0.0;
   double lots=1.0;

   if(OrderCalcMargin(ORDER_TYPE_BUY,symbol,lots,SymbolInfoDouble(symbol,SYMBOL_ASK),margin) && margin > 0)
     {
      double tickValue = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      double lotValue = tickValue * SymbolInfoDouble(symbol,SYMBOL_ASK) / tickSize;
      leverage=(int)MathRound(lotValue/margin);
     }

   return leverage;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double MarginAtMinBuyPrice(double lots, double pointValuePerLot)
  {
   return lots * pointValuePerLot * minBuyPrice / CalculateSymbolLeverage(_Symbol);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void stochDoubleSellLogic()
  {
//open SELL orders on SELL signal
   if(sellPositionsToOpen > 0)
     {
      double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double nextSellPrice = totalSellPositions == 0 ? bidPrice : NormPrice(sellPositions[totalSellPositions-1].openPrice + nextSellPositionByPoints);

      headerLine += " NextSell: " + nextSellPrice;
      if(bidPrice >= nextSellPrice && stochSignal() == "sell")
        {
         openOrder(ORDER_TYPE_SELL);
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void updateTakeProfitsGlobally()
  {
// update SELL take profits if owns more SELLs than expected
   if(totalSellPositions > sellPositionsToOpen)
     {

      //canibalize best and close 3rd best
      int bestPositionIdx = totalSellPositions - 1;
      int positionToCloseIdx = totalSellPositions-1-2;

      Position bestPosition = sellPositions[bestPositionIdx];
      Position positionToClose = sellPositions[positionToCloseIdx];

      double totalLots = bestPosition.lots + positionToClose.lots;
      double takeProfitPrice = NormPrice( (bestPosition.lots * bestPosition.openPrice + positionToClose.lots * positionToClose.openPrice)/totalLots );

      m_trade.PositionModify(bestPosition.ticket, 0, takeProfitPrice);
      m_trade.PositionModify(positionToClose.ticket, 0, takeProfitPrice);
      //OrderCommission(); OrderSwap();
      //double profit = (takeProfitPrice - askPrice) / MODE_TICKSIZE * MODE_TICKVALUE * totalLots

      for(int i=0; i<totalSellPositions; i++)
        {
         if(i != bestPositionIdx && i != positionToCloseIdx)
           {
            Position position = sellPositions[i];
            m_trade.PositionModify(position.ticket, 0, 0);
           }
        }
      headerLine += " SellTP: " + takeProfitPrice; //13169
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
   if(!ButtonCreate(0, "SellOne_btn", 0, 002 + 000 + Move_X, 020 + 005 + Move_Y, Button_Width + 000, Button_Height, Corner, "S", Font_Type, Font_Size, Font_Color, clrTeal, clrYellow))
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
