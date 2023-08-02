#property strict

#include <stdlib.mqh>
#include <ArraySortStruct.mqh>

input string expertName = "sell*2";
input int expertId = 34;

input double positionsSize = 0.01; //how big positions to open
input int initialPositions = 2;
input int positionsToOpen = 4;
input int maxPositions = 8;
input double inNextPositionByPoints = 0.;
input double inAccumulateFromPrice = 0.;
input double stopLoss = 0;
input bool piramide = false;


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
     ToolTips_Text ("CloseALL_btn");
     ToolTips_Text ("CloseHalf_btn");
     ObjectCreate ("SL_Edit", OBJ_EDIT, ChartWindowFind(), 0, 0);
     ObjectSet ("SL_Edit", OBJPROP_CORNER, Corner);
     ObjectSet ("SL_Edit", OBJPROP_XSIZE, Button_Width + 020);
     ObjectSet ("SL_Edit", OBJPROP_YSIZE, Font_Size*2.8);
     ObjectSet ("SL_Edit", OBJPROP_XDISTANCE, 140);
     ObjectSet ("SL_Edit", OBJPROP_YDISTANCE, 025);
     ObjectSet ("SL_Edit", OBJPROP_ALIGN, ALIGN_CENTER);
     ObjectSetText ("SL_Edit", Bid, 13, Font_Type, Font_Color);

     double bidPrice = MarketInfo(Symbol(), MODE_BID);
     accumulateFromPrice = inAccumulateFromPrice != 0.? inAccumulateFromPrice : bidPrice;

     if (inNextPositionByPoints == 0. && stopLoss != 0.) {
        double range = MathAbs(stopLoss - accumulateFromPrice) * 0.8;
        nextPositionByPoints = range / maxPositions;
     } else {
        nextPositionByPoints = inNextPositionByPoints;
     }

   OnTick();
  }

void OnDeinit(const int reason)
  {
   DeleteButtons();
   ObjectDelete ("SL_Edit");
  }


//+------------------------------------------------------------------+

//|
//+------------------------------------------------------------------+
void OnTick(void)
  {
   double askPrice = MarketInfo(Symbol(), MODE_ASK);
   if ((stopLoss > 0 && askPrice >= stopLoss) || inactive){
      inactive = true;
      comment = "stopLoss executed: " + stopLoss;
      return;
   }

    comment = inactive ? "INACTIVE " : "";
    readPositions();

    calculate();

    if (ordersTotal != totalOpenedPositions){
      OnTrade();
      ordersTotal = totalOpenedPositions;
    }

    Comment(comment);
}

void readPositions(){
    ArrayFree(openPositions);
    ArrayFree(limitPositions);

   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && (expertId == OrderMagicNumber() || expertId == 0) && _Symbol == OrderSymbol()) {
         Position* p = new Position(OrderTicket(), OrderLots(), OrderProfit(), OrderOpenPrice(), OrderStopLoss());
         if (OrderType() == OP_SELL) {
            ArrayAppend(openPositions, p);
         } else if (OrderType() == OP_SELLLIMIT){
            ArrayAppend(limitPositions, p);
         }
         delete p;
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
      for (int i=0; i<totalOpenedPositions - positionsToOpen; i++){
         Position position = openPositions[i];
         totalLots += position.lots;
         totalWagedOpenPrice += position.openPrice * position.lots;
      }

      //OrderCommission(); OrderSwap();
      //double profit = (takeProfitPrice - askPrice) / MODE_TICKSIZE * MODE_TICKVALUE * totalLots

      double takeProfitPrice = NormPrice(totalWagedOpenPrice / totalLots);
      for (int i=0; i<totalOpenedPositions - positionsToOpen; i++){
         Position position = openPositions[i];
         OrderModify(position.ticket, 0., stopLoss, takeProfitPrice, 0);
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

   comment += ", SELL: " + totalOpenedPositions + ", Pending SELL: " + totalLimitPositions + ", Profit: " + DoubleToStr(totalProfit,2);

   double bidPrice = MarketInfo(Symbol(), MODE_BID);
   // Place initial Orders
   if (totalOpenedPositions + totalLimitPositions  == 0) {
      if (bidPrice >= accumulateFromPrice){
        for(int i=0; i<initialPositions; i++){
            openOrder(OP_SELL);
        }
      } else {
         openOrder(OP_SELLLIMIT, accumulateFromPrice);
      }
   } else if (totalOpenedPositions + totalLimitPositions < maxPositions) { // must be in next cycle to refresh positions

      double nextOpenPrice;
      // Append new Open Limits if missing
      if (totalLimitPositions > 0){
         nextOpenPrice = NormPrice(limitPositions[totalLimitPositions-1].openPrice + nextPositionByPoints);
      } else {
         nextOpenPrice = NormPrice(openPositions[totalOpenedPositions-1].openPrice + nextPositionByPoints);
      }

      nextOpenPrice = MathMax(nextOpenPrice, bidPrice);

      for (int j=totalOpenedPositions + totalLimitPositions; j < maxPositions; j++) {
         openOrder(OP_SELLLIMIT, nextOpenPrice);
         nextOpenPrice = NormPrice(nextOpenPrice + nextPositionByPoints);
      }
   } else if (piramide && totalOpenedPositions > 0 && totalOpenedPositions < positionsToOpen && totalLimitPositions > 0) {
      // Price goes in profitable dicection (piramide) scenario, open opposite orders as well if too few of them

      double nextPiramideOpenPrice = NormPrice(openPositions[0].openPrice - nextPositionByPoints);
      if (bidPrice <= nextPiramideOpenPrice) {
         openOrder(OP_SELL);
         OrderDelete(limitPositions[totalLimitPositions-1].ticket);
      }
   }
}

void openOrder(int type, double price = 0){
      if (type == OP_BUY || type == OP_BUYLIMIT){
         if (price == 0) price = Ask;
         OrderSend(_Symbol, type, positionsSize, price, 0.001*Ask, stopLoss, 0, expertName + " " + expertId, expertId, 0, Green);
      } else if (type == OP_SELL || type == OP_SELLLIMIT) {
         if (price == 0) price = Bid;
         OrderSend(_Symbol, type, positionsSize, price, 0.01*Bid, stopLoss, 0, expertName + " " + expertId, expertId, 0, Red);
      }
}

void openSellOrder() {
   OrderSend(_Symbol, OP_SELL, positionsSize, Bid, 0.001*Bid, stopLoss, 0, expertName + " " + expertId , expertId, 0, Red);
}


double NormPrice(double price) {
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   return( MathRound(price/tickSize)*tickSize );
}


void OnChartEvent (const int id, const long &lparam, const double &dparam, const string &action)
    {
     ResetLastError();
     if (id == CHARTEVENT_OBJECT_CLICK) {if (ObjectType (action) == OBJ_BUTTON) {ButtonPressed (0, action);}}
    }


void ButtonPressed (const long chartID, const string action)
    {
     ObjectSetInteger (chartID, action, OBJPROP_BORDER_COLOR, clrBlack); // button pressed
     if (action == "CloseALL_btn") CloseAll_Button (action);
     if (action == "CloseHalf_btn") CloseHalf_Button (action);
     if (action == "ClearALL_btn") ClearAll_Button (action);
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
      ticket = OrderClose (position.ticket, position.lots, MarketInfo (OrderSymbol(), MODE_ASK), 0.01*Ask, clrNONE);
      openOrder(OP_SELLLIMIT, position.openPrice);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", OrderTicket() ," closed");
   }

   return(0);
  }

int ClearAll_Button (const string action)
  {
   inactive = true;
   int ticket;
   readPositions();
   double bidPrice = MarketInfo(OrderSymbol(), MODE_BID);
   for (int i=0; i<totalOpenedPositions; i++){
      Position position = openPositions[i];
      ticket = OrderClose (position.ticket, position.lots, bidPrice, 0.01*Bid, clrNONE);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", OrderTicket() ," closed");
   }
   for (int i=0; i<totalLimitPositions; i++){
      Position position = limitPositions[i];
      ticket = OrderDelete(position.ticket);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", OrderTicket() ," closed");
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
      ticket = OrderClose (position.ticket, position.lots, MarketInfo (OrderSymbol(), MODE_BID), 0.01*Bid, clrNONE);
      openOrder(OP_BUYLIMIT, position.openPrice);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", OrderTicket() ," closed");
   }

   return(0);
}

int ChangeSL_Button (const string action)
  {
   double SL_Extract = StrToDouble (ObjectGetString (0, "SL_Edit", OBJPROP_TEXT, 0));
   int ticket;

   readPositions();
   for (int i=0; i<totalOpenedPositions; i++){
     Position position = openPositions[i];
     ticket = OrderModify(position.ticket, 0, SL_Extract, 0, 0, clrNONE);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", OrderTicket() ," closed");
   }
   for (int i=0; i<totalLimitPositions; i++){
     Position position = limitPositions[i];
     ticket = OrderModify(position.ticket, position.openPrice, SL_Extract, 0, 0, clrNONE);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", OrderTicket() ," closed");
   }
   return(0);
  }

int BreakEven_Button (const string action)
  {
   double SL_Extract = StrToDouble (ObjectGetString (0, "SL_Edit", OBJPROP_TEXT, 0));
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
     ticket = OrderModify(position.ticket, 0, position.stopLoss, totalWagedOpenPrice, 0, clrNONE);
     if (ticket == -1) Print ("Error : ",  GetLastError());
     if (ticket >   0) Print ("Position ", OrderTicket() ," closed");
   }

   return(0);
  }

int Open_Button (const string action)
  {
   openOrder(OP_SELL);
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