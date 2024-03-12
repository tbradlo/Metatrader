//+------------------------------------------------------------------+
//|                                                   KowalskiIB.mq5 |
//|                                  Copyright 2024, Tomasz Bradlo   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Tomasz Bradlo Ltd."
#property version   "1.001"
#property strict

int startHour = 9;  // Start time for the period
int endHour   = 10;  // End time for the period

double highLine;
double lowLine;

int OnInit()
  {
   DrawHighLine();
   return(INIT_SUCCEEDED);
  }

   //+------------------------------------------------------------------+
   //| Function to draw the highest point line                         |
   //+------------------------------------------------------------------+
   void DrawHighLine()
   {
      MqlDateTime barTimeStruct;
      double lastHigh;
      double lastLow;

      for (int i = 0; i < iBars(_Symbol, PERIOD_H1); i++)
      {
         datetime currentBarTime = iTime(_Symbol, PERIOD_H1, i);
         TimeToStruct(currentBarTime, barTimeStruct);

         if (barTimeStruct.hour == startHour){
            lastHigh    = iHigh(_Symbol, PERIOD_H1, i);
            lastLow    = iLow(_Symbol, PERIOD_H1, i);
            break;
         }
      }

      if (highLine != lastHigh){
         Print("HIGH " + lastHigh);
      }

      if (lowLine != lastLow){
         Print("LOW " + lastLow);
      }

      // Draw a horizontal line at the highest price
      //ObjectCreate(0, "HighLine", OBJ_TREND, 0, highestTime, highestPrice, TimeCurrent(), highestPrice);
      ObjectSetInteger(0, "HighLine", OBJPROP_COLOR, clrRed);  // Set line color to red
      ObjectSetInteger(0, "HighLine", OBJPROP_RAY_RIGHT, false);  // Make the line extend to the left
      ObjectSetInteger(0, "HighLine", OBJPROP_RAY_LEFT, true);    // Make the line extend to the right
   }




void OnDeinit(const int reason)
  {

  }

void OnTick()
  {

  }

double NormPrice(double price)
  {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return(MathRound(price/tickSize)*tickSize);
  }