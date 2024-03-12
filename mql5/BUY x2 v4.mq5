#property strict

#include <ArraySortStruct.mqh>
#include <Trade\Trade.mqh>
CTrade         m_trade;

input string expertName = "buy*2";
input int expertId = 34;

input double positionsSize = 0.01; //how big positions to open
input int initialPositions = 2;
input int positionsToOpen = 4;
input int maxPositions = 8;
input double inNextPositionByPoints = 0.;
input double inAccumulateFromPrice = 0.;
input double stopLoss = 0;
input bool piramide = false;

static datetime expiration=D'2030.01.05 11:01:01';

/// BETA version MT5 compatible !!!, no warranty */

string comment = "";

class Position
  {
public:
   int ticket;
   double lots;
   double profit;
   double openPrice;
   double stopLoss;
   //--- Default constructor
                     Position(){ ticket = -1; lots = 0.; profit = 0.; openPrice = 0.; stopLoss = 0.;};
   //--- Parametric constructor
   Position(int p_ticket, double p_lots, double p_profit, double p_openPrice, double p_stopLoss){
      ticket = p_ticket;
      lots = p_lots;
      profit = p_profit;
      openPrice = p_openPrice;
      stopLoss = p_stopLoss;
   }
};

Position openPositions[]; //sorted by openPrice Asc
Position limitPositions[];

int totalOpenedPositions = 0;
int totalLimitPositions = 0;

double nextPositionByPoints = 0.;
double accumulateFromPrice = 0.;
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
     m_trade.SetExpertMagicNumber(expertId);
     m_trade.SetMarginMode();
     m_trade.SetTypeFillingBySymbol(Symbol());
     m_trade.SetDeviationInPoints(2);

     CreateButtons();
     ToolTips_Text ("CloseALL_btn");
     ToolTips_Text ("CloseHalf_btn");
     ObjectCreate (0,"SL_Edit", OBJ_EDIT, ChartWindowFind(), 0, 0);
     ObjectSetInteger (0,"SL_Edit", OBJPROP_CORNER, Corner);
     ObjectSetInteger (0,"SL_Edit", OBJPROP_XSIZE, Button_Width + 020);
     ObjectSetInteger (0,"SL_Edit", OBJPROP_YSIZE, Font_Size*2.8);
     ObjectSetInteger (0,"SL_Edit", OBJPROP_XDISTANCE, 140);
     ObjectSetInteger (0,"SL_Edit", OBJPROP_YDISTANCE, 025);
     ObjectSetInteger (0,"SL_Edit", OBJPROP_ALIGN, ALIGN_CENTER);
     double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

     ObjectSetString (0,"SL_Edit", OBJPROP_TEXT, askPrice);
     accumulateFromPrice = inAccumulateFromPrice != 0.? inAccumulateFromPrice : askPrice;

     if (inNextPositionByPoints == 0. && stopLoss != 0.) {
        double range = MathAbs(accumulateFromPrice - stopLoss) * 0.8;
        nextPositionByPoints = range / maxPositions;
     } else {
        nextPositionByPoints = inNextPositionByPoints;
     }

   OnTick();
  }

void OnDeinit(const int reason)
  {
   DeleteButtons();
   ObjectDelete (0,"SL_Edit");
  }


//+------------------------------------------------------------------+

//|
//+------------------------------------------------------------------+
void OnTick(void)
  {
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if ((stopLoss > 0 && bidPrice <= stopLoss) || inactive){
      inactive = true;
      comment = "stopLoss executed: " + stopLoss;
      return;
   }

    comment = "";
    readPositions();

    calculate();

    Comment(comment);
}

void readPositions(){
    ArrayFree(openPositions);
    ArrayFree(limitPositions);

   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      long ticket = OrderGetTicket(i);
      if (OrderSelect(ticket) && (expertId == OrderGetInteger(ORDER_MAGIC) || expertId == 0) && _Symbol == OrderGetString(ORDER_SYMBOL)) {
         if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT) {
            Position* p = new Position(ticket, OrderGetDouble(ORDER_VOLUME_CURRENT), 0, OrderGetDouble(ORDER_PRICE_OPEN), NormPrice(OrderGetDouble(ORDER_SL)));
            ArrayAppend(limitPositions, p);
            delete p;
         }
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      long ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && (expertId == PositionGetInteger(POSITION_MAGIC) || expertId == 0) && _Symbol == PositionGetString(POSITION_SYMBOL))
        {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
              Position* p = new Position(ticket, PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PROFIT), PositionGetDouble(POSITION_PRICE_OPEN), NormPrice(PositionGetDouble(POSITION_SL)));
              ArrayAppend(openPositions, p);
              delete p;
           }

        }
     }

   ArraySortStruct(openPositions, openPrice);
   ArraySortStruct(limitPositions, openPrice);

   totalOpenedPositions = ArraySize(openPositions);
   totalLimitPositions = ArraySize(limitPositions);
}

void OnTrade(){
   if (totalOpenedPositions > positionsToOpen){ //if opened more than expected
      double totalLots = 0.0;
      double totalWagedOpenPrice = 0.0;
      for (int i=positionsToOpen; i<totalOpenedPositions; i++){
         Position position = openPositions[i];
         totalLots += position.lots;
         totalWagedOpenPrice += position.openPrice * position.lots;
      }

      //OrderCommission(); OrderSwap();
      //double profit = (takeProfitPrice - askPrice) / MODE_TICKSIZE * MODE_TICKVALUE * totalLots

      double takeProfitPrice = NormPrice(totalWagedOpenPrice / totalLots);
      for (int i=positionsToOpen; i<totalOpenedPositions; i++){
         Position position = openPositions[i];
         m_trade.PositionModify(position.ticket, stopLoss, takeProfitPrice);
      }
   }
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
   openOrdersLogic();
}

void openOrdersLogic(){
   double totalProfit = 0.;

   for (int i=totalOpenedPositions-1; i>=0; i--){
      totalProfit += openPositions[i].profit;
   }

   comment += ", BUY: " + totalOpenedPositions + ", Pending BUY: " + totalLimitPositions + ", Profit: " + DoubleToString(totalProfit,2);

   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   // Place initial Orders
   if (totalOpenedPositions + totalLimitPositions  == 0) {
      if (askPrice <= accumulateFromPrice){
        for(int i=0; i<initialPositions; i++){
            openOrder(ORDER_TYPE_BUY);
        }
      } else {
         openOrder(ORDER_TYPE_BUY_LIMIT, accumulateFromPrice);
      }
   } else if (totalOpenedPositions + totalLimitPositions < maxPositions) { // must be in next cycle to refresh positions

      double nextOpenPrice;
      // Append new Open Limits if missing
      if (totalLimitPositions > 0){
         nextOpenPrice = NormPrice(limitPositions[0].openPrice - nextPositionByPoints);
      } else {
         nextOpenPrice = NormPrice(openPositions[0].openPrice - nextPositionByPoints);
      }

      nextOpenPrice = MathMin(nextOpenPrice, askPrice);

      for (int j=totalOpenedPositions + totalLimitPositions; j < maxPositions; j++) {
         openOrder(ORDER_TYPE_BUY_LIMIT, nextOpenPrice);
         nextOpenPrice = NormPrice(nextOpenPrice - nextPositionByPoints);
      }
   } else if (piramide && totalOpenedPositions > 0 && totalOpenedPositions < positionsToOpen && totalLimitPositions > 0) {
      // Price goes in profitable dicection (piramide) scenario, open opposite orders as well if too few of them

      double nextPiramideOpenPrice = NormPrice(openPositions[totalOpenedPositions-1].openPrice + nextPositionByPoints);
      if (askPrice >= nextPiramideOpenPrice) {
         openOrder(ORDER_TYPE_BUY);
         m_trade.OrderDelete(limitPositions[0].ticket);
      }
   }
}

void openOrder(int type, double price = 0){
   if (type == ORDER_TYPE_BUY){
      if (price == 0) price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      m_trade.Buy(positionsSize, _Symbol,  price, stopLoss, 0, expertName + " " + expertId);
   } else if (type == ORDER_TYPE_BUY_LIMIT){
      m_trade.BuyLimit(positionsSize, price, _Symbol, stopLoss, 0, ORDER_TIME_GTC, expiration, expertName + " " + expertId);
   }
}

double NormPrice(double price)
  {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return(MathRound(price/tickSize)*tickSize);
  }


void OnChartEvent (const int id, const long &lparam, const double &dparam, const string &action)
    {
     ResetLastError();
     if (id == CHARTEVENT_OBJECT_CLICK) {if (ObjectGetInteger(0, action, OBJPROP_TYPE) == OBJ_BUTTON) {ButtonPressed (0, action);}}
    }


void ButtonPressed (const long chartID, const string action)
    {
     ObjectSetInteger (chartID, action, OBJPROP_BORDER_COLOR, clrBlack); // button pressed
     if (action == "CloseALL_btn") CloseAll_Button (action);
     if (action == "CloseHalf_btn") CloseHalf_Button (action);
     if (action == "ClearAll_btn") ClearAll_Button (action);
     //if (action == "Delete___btn") Delete___Button (action);
     //if (action == "SLplusOnebtn") SLplus1__Button (action);
     //if (action == "DeleteSL_btn") DeleteSL_Button (action);
     if (action == "BreakEven_btn") BreakEven_Button (action);
     if (action == "ChangeSL_btn") ChangeSL_Button (action);
     if (action == "Open_btn") Open_Button(action);
     Sleep (2000);
     ObjectSetInteger (chartID, action, OBJPROP_BORDER_COLOR, clrYellow); // button unpressed
     ObjectSetInteger (chartID, action, OBJPROP_STATE, false); // button unpressed
     ChartRedraw();
    }

int CloseAll_Button (const string action)
  {
   int ticket;
   readPositions();
   for (int i=0; i< totalOpenedPositions; i++){
      Position position = openPositions[i];
      ticket = m_trade.PositionClose(position.ticket);
      openOrder(ORDER_TYPE_BUY_LIMIT, position.openPrice);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", position.ticket ," closed");
   }

   return(0);
  }

int ClearAll_Button (const string action)
  {
   inactive = true;
   int ticket;
   readPositions();
   for (int i=0; i<totalOpenedPositions; i++){
      Position position = openPositions[i];
      ticket = m_trade.PositionClose(position.ticket);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", position.ticket ," closed");
   }
   for (int i=0; i<totalLimitPositions; i++){
      Position position = limitPositions[i];
      ticket = m_trade.OrderDelete(position.ticket);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", position.ticket ," closed");
   }

   return(0);
  }


int CloseHalf_Button (const string action)
  {
   int ticket;
   readPositions();
   int toCloseCnt = MathFloor(totalOpenedPositions/2);
   for (int i=totalOpenedPositions-1; i> toCloseCnt; i--){
      Position position = openPositions[i];
      ticket = m_trade.PositionClose(position.ticket);
      openOrder(ORDER_TYPE_BUY_LIMIT, position.openPrice);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", position.ticket ," closed");
   }

   return(0);
}

int ChangeSL_Button (const string action)
  {
   double SL_Extract = StringToDouble (ObjectGetString (0, "SL_Edit", OBJPROP_TEXT, 0));
   int ticket;

   readPositions();
   for (int i=0; i<totalOpenedPositions; i++){
     Position position = openPositions[i];
     ticket = m_trade.PositionModify(position.ticket, SL_Extract, 0);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", position.ticket ," closed");
   }
   for (int i=0; i<totalLimitPositions; i++){
     Position position = limitPositions[i];
     ticket = m_trade.OrderModify(position.ticket, position.openPrice, SL_Extract, 0, ORDER_TIME_GTC,expiration);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", position.ticket ," closed");
   }
   return(0);
  }

int BreakEven_Button (const string action)
  {
   double SL_Extract = StringToDouble (ObjectGetString (0, "SL_Edit", OBJPROP_TEXT, 0));
   int ticket;

   readPositions();

   double totalLots = 0.0;
   double totalWagedOpenPrice = 0.0;
   for (int i=positionsToOpen; i<totalOpenedPositions; i++){
      Position position = openPositions[i];
      totalLots += position.lots;
      totalWagedOpenPrice += position.openPrice * position.lots;
   }

   for (int i=0; i<totalOpenedPositions; i++){
     Position position = openPositions[i];
     ticket = m_trade.OrderModify(position.ticket, 0, position.stopLoss, totalWagedOpenPrice, ORDER_TIME_GTC, expiration);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", position.ticket ," closed");
   }

   return(0);
  }

int Open_Button (const string action)
  {
   openOrder(ORDER_TYPE_BUY);
   return(0);
  }

void CreateButtons()
    {
     int Button_Height = (int)(Font_Size*2.8);
     if (!ButtonCreate (0, "CloseALL_btn", 0, 002 + 000 + Move_X, 020 + 005 + Move_Y, Button_Width + 000, Button_Height, Corner, "0", Font_Type, Font_Size, Font_Color, clrTeal, clrYellow)) return;
     if (!ButtonCreate (0, "CloseHalf_btn", 0, 002 + 035 + Move_X, 020 + 005 + Move_Y, Button_Width + 000, Button_Height, Corner, "1/2", Font_Type, Font_Size, Font_Color, clrTeal, clrYellow)) return;
     if (!ButtonCreate (0, "BreakEven_btn", 0, 002 + 070 + Move_X, 020 + 005 + Move_Y, Button_Width + 000, Button_Height, Corner, "BE", Font_Type, Font_Size, Font_Color, clrTeal, clrYellow)) return;

     //if (!ButtonCreate (0, "Delete___btn", 0, 002 + 075 + Move_X, 020 + 005 + Move_Y, Button_Width + 000, Button_Height, Corner, "Delete All",Font_Type, Font_Size, Font_Color, clrTeal, clrYellow)) return;
     if (!ButtonCreate (0, "ChangeSL_btn", 0, 002 + 105 + Move_X, 020 + 005 + Move_Y, Button_Width + 000, Button_Height, Corner, "SL:",Font_Type, Font_Size, Font_Color, clrDeepPink, clrYellow)) return;
     if (!ButtonCreate (0, "Open_btn", 0, 002 + 190 + Move_X, 020 + 005 + Move_Y, Button_Width + 000, Button_Height, Corner, "-1",Font_Type, Font_Size, Font_Color, clrTeal, clrYellow)) return;
     if (!ButtonCreate (0, "ClearALL_btn", 0, 002 + 225 + Move_X, 020 + 005 + Move_Y, Button_Width + 000, Button_Height, Corner, "CLR", Font_Type, Font_Size, Font_Color, clrTeal, clrYellow)) return;

     ChartRedraw();
    }

void ToolTips_Text (const string action)
  {
   if (action == "CloseALL_btn") {ObjectSetString (0, action, OBJPROP_TOOLTIP, "Close ALL Order(s) opened by **Current Expert Advisor** and Chart ONLY");}
   if (action == "CloseHalf_btn") {ObjectSetString (0, action, OBJPROP_TOOLTIP, "Close HALF of the Order(s) opened by **Current Expert Advisor** and Chart ONLY");}
   if (action == "BreakEven_btn") {ObjectSetString (0, action, OBJPROP_TOOLTIP, "Set positions to Break Even");}
   //if (action == "Delete___btn") {ObjectSetString (0, action, OBJPROP_TOOLTIP, "Delete Pending Order(s) for **Current Chart** ONLY");}
   //if (action == "SLplusOnebtn") {ObjectSetString (0, action, OBJPROP_TOOLTIP, "Add 1.0 pip to SL for ALL Open Order(s) on **Current Chart** ONLY");}
   //if (action == "DeleteSL_btn") {ObjectSetString (0, action, OBJPROP_TOOLTIP, "Remove current SL value for ALL Open Order(s) on **Current Chart** ONLY");}
   if (action == "ChangeSL_btn") {ObjectSetString (0, action, OBJPROP_TOOLTIP, "Change SL value for ALL Open Order(s) on **Current Chart** ONLY");}
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
     ButtonDelete (0, "CloseALL_btn");
     ButtonDelete (0, "CloseHalf_btn");
     ButtonDelete (0, "BreakEven_btn");
     //ButtonDelete (0, "Delete___btn");
     //ButtonDelete (0, "SLplusOnebtn");
     //ButtonDelete (0, "DeleteSL_btn");
     ButtonDelete (0, "ChangeSL_btn");
     ButtonDelete(0, "Open_btn");
     ButtonDelete(0, "ClearALL_btn");
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