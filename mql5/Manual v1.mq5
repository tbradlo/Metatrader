//+------------------------------------------------------------------+
//|                                              Manual V1.mq5 |
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
    v0.1, 28 Nov 2023
    Manual trading
*/


//--- input parameters
input string expertName = "Manual";
input int expertId = 21;

input double positionSize = 0.01;

// Stoch params
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


bool inactive = false;

int Corner = 2;
int Move_X = 0;
int Move_Y = 0;
string B00001 = "============================";
int Button_Width = 30;
string Font_Type = "Arial Bold";
color Font_Color = clrWhite;
int Font_Size = 8;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnInit(void)
  {
   CreateLabel("btmComment", 10, 15);
   CreateLabel("btmOwns", 10, 30);
   int D_Period = 3;
   int Slowing = 3;
   m_trade.SetExpertMagicNumber(expertId);
   m_trade.SetMarginMode();
   m_trade.SetTypeFillingBySymbol(Symbol());
   m_trade.SetDeviationInPoints(2);

   CreateButtons();

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
            existingTakeProfits.Add(p.takeProfit);
           }
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            ArrayAppend(sellPositions, p);
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
void openOrder(int type, double price = 0, double takeProfit = 0)
  {
   if(type == ORDER_TYPE_BUY)
     {
      m_trade.Buy(positionSize,_Symbol,price,0,NormPrice(takeProfit),expertName + " " + expertId);
     }
   else if(type == ORDER_TYPE_SELL)
        {
         m_trade.Sell(positionSize,_Symbol,price,0,NormPrice(takeProfit),expertName + " " + expertId);
        }
   else if(type == ORDER_TYPE_SELL_LIMIT)
        {
         m_trade.SellLimit(positionSize,price,_Symbol,0,NormPrice(takeProfit),0,0,expertName + " " + expertId);
        }
   else if(type == ORDER_TYPE_BUY_LIMIT)
        {
         m_trade.BuyLimit(positionSize, price,_Symbol,0,NormPrice(takeProfit),0,0,expertName + " " + expertId);
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &action)
  {
   ResetLastError();
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(action == "SellOne_btn" || action == "SellLimit_btn" || action == "BuyLimit_btn" || action == "BuyOne_btn" || action == "CloseAll_btn")
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
   if(action == "SellLimit_btn")
      SellLimit_Button(action);
   if(action == "BuyOne_btn")
      BuyOne_Button(action);
   if(action == "BuyLimit_btn")
      BuyLimit_Button(action);
   if (action == "CloseAll_btn")
      CloseAll_Button(action);
   Sleep(1000);
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

int BuyOne_Button(const string action)
  {
   openOrder(ORDER_TYPE_BUY);
   return(0);
  }

int SellLimit_Button(const string action)
  {
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double limitPrice = NormPrice(askPrice * 1.01);
   openOrder(ORDER_TYPE_SELL_LIMIT, limitPrice);
   return(0);
  }

int BuyLimit_Button(const string action)
  {
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double limitPrice = NormPrice(bidPrice * 0.99);
   openOrder(ORDER_TYPE_BUY_LIMIT, limitPrice);
   Alert(limitPrice);
   return(0);
  }

int CloseAll_Button(const string action)
  {
   for(int i=totalBuyPositions-1; i>=0; i--)
     {
         m_trade.PositionClose(buyPositions[i].ticket);
     }
   for(int i=totalSellPositions-1; i>=0; i--)
     {
         m_trade.PositionClose(sellPositions[i].ticket);
     }
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
   if(!ButtonCreate(0, "SellLimit_btn", 0, 10 + 40 + Move_X, 55 + Move_Y, Button_Width + 000, Button_Height, CORNER_LEFT_LOWER, "SL", Font_Type, Font_Size, Font_Color, clrTeal, clrYellow))
      return;
   if(!ButtonCreate(0, "BuyOne_btn", 0, 10 + 80 + Move_X, 55 + Move_Y, Button_Width + 000, Button_Height, CORNER_LEFT_LOWER, "B", Font_Type, Font_Size, Font_Color, clrTeal, clrYellow))
      return;
   if(!ButtonCreate(0, "BuyLimit_btn", 0, 10 + 120 + Move_X, 55 + Move_Y, Button_Width + 000, Button_Height, CORNER_LEFT_LOWER, "BL", Font_Type, Font_Size, Font_Color, clrTeal, clrYellow))
      return;
   if(!ButtonCreate(0, "CloseAll_btn", 0, 10 + 160 + Move_X, 55 + Move_Y, Button_Width + 000, Button_Height, CORNER_LEFT_LOWER, "END", Font_Type, Font_Size, Font_Color, clrRed, clrWhite))
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
   ButtonDelete(0, "SellLimit_btn");
   ButtonDelete(0, "BuyOne_btn");
   ButtonDelete(0, "BuyLimit_btn");
   ButtonDelete(0, "CloseAll_btn");
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
