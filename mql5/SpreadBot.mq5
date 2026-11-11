//+------------------------------------------------------------------+
//|                                     DE30vsUS100_SpreadEA.mq5     |
//|   EA trades pairs: DE30.pro SHORT + US100.pro LONG               |
//|   Opens additional pairs as the spread DECREASES. The distance   |
//|   between entries is DYNAMIC: InpOpenRangePoints divided by the  |
//|   number of pairs that can still be opened.                      |
//|   Each pair has its own TP expressed in EUR.                     |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "2.10"
#property strict

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Instruments ==="
input string InpSymbol1 = "DE30.pro";      // Symbol 1 - DAX (SHORT) - ALWAYS EXECUTED FIRST
input string InpSymbol2 = "US100.pro";     // Symbol 2 - Nasdaq (LONG) - ALWAYS EXECUTED SECOND

input group "=== Position size ==="
input double InpLots                = 0.006;  // Fixed lot on DE30 (US100 lot is matched dynamically)
input double InpMaxPositionSize     = 0.015;  // Max allowed volume of a single position (hard limit)

input group "=== Take Profit (money based) ==="
input double InpTakeProfitEUR = 5.0;        // TP per pair in money (EUR)

input group "=== Entry logic ==="
input double InpStartGapPoints  = 3000;     // Start threshold: open the 1st pair when spread <= this value
input double InpOpenRangePoints = 2000;     // Open range: step = OpenRange / (pairs still to open); last step = OpenRange / 2
input double InpRangeMin        = 0;        // Lower spread limit for trading (0 = disabled)
input double InpRangeMax        = 0;        // Upper spread limit for trading (0 = disabled)
input int    InpMaxPairs        = 30;       // Max number of simultaneously open pairs

input group "=== Dashboard ==="
input int    InpDashboardPadding = 18;      // Number of empty lines (moves the panel down)

input group "=== Identification ==="
input int    InpMagicBase       = 555000;   // Base magic number (each pair = MagicBase + index)
input string InpCommentPrefix   = "DE30vsUS100"; // Position comment prefix

input group "=== Safety and timing ==="
input int InpStartDelaySec       = 60;      // Delay before opening after the night break (seconds)
input int InpMinTradeIntervalSec = 3;       // Min. pause between trades (seconds)
input int InpMaxQuoteAgeSec      = 120;     // Max quote age (s) for an instrument to be considered tradable
input int InpSlippagePoints      = 50;      // Allowed slippage (points) for market execution
input int InpTimerMS             = 500;     // Timer frequency (ms) for live trading
input int InpOrphanDelaySec      = 5;       // Wait time (s) before a leg is considered orphaned

CTrade trade;

//--- Time control variables
ulong    lastTransactionTime = 0;    // Time of last transaction in milliseconds
datetime tradingAllowedTime  = 0;    // Timestamp from which new positions may be opened
bool     wasSessionBreak     = false;// Flag: was there a trading break

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!SymbolSelect(InpSymbol1,true))
      Print("WARNING: cannot select symbol ",InpSymbol1);
   if(!SymbolSelect(InpSymbol2,true))
      Print("WARNING: cannot select symbol ",InpSymbol2);

   trade.SetTypeFillingBySymbol(InpSymbol1);
   trade.SetDeviationInPoints(InpSlippagePoints);

   // Start the timer for live trading
   EventSetMillisecondTimer(InpTimerMS);

   Print("DE30vsUS100 EA initialized. MagicBase=",InpMagicBase,
         " StartGap=",InpStartGapPoints," OpenRange=",InpOpenRangePoints,
         " TP_EUR=",InpTakeProfitEUR," MaxPairs=",InpMaxPairs,
         " DaxLots=",InpLots," MaxPosSize=",InpMaxPositionSize);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
  }

//+------------------------------------------------------------------+
//| Is the instrument currently tradable                             |
//+------------------------------------------------------------------+
bool IsSymbolTradable(const string sym)
  {
   if(!SymbolSelect(sym,true))
      return false;

   long tm = SymbolInfoInteger(sym,SYMBOL_TRADE_MODE);
   if(tm==SYMBOL_TRADE_MODE_DISABLED)
      return false;

   datetime qt = (datetime)SymbolInfoInteger(sym,SYMBOL_TIME);
   if(TimeCurrent()-qt > InpMaxQuoteAgeSec)
      return false;

   double bid = SymbolInfoDouble(sym,SYMBOL_BID);
   double ask = SymbolInfoDouble(sym,SYMBOL_ASK);
   if(bid<=0 || ask<=0 || ask<bid)
      return false;

   return true;
  }

//+------------------------------------------------------------------+
//| Normalize lot to min/max/step and InpMaxPositionSize             |
//+------------------------------------------------------------------+
double NormalizeLot(const string sym, double lots)
  {
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.001;

   // InpMaxPositionSize acts as an additional upper limit
   if(InpMaxPositionSize > 0 && maxLot > InpMaxPositionSize)
      maxLot = InpMaxPositionSize;

   if(lots < minLot) lots = minLot;

   double norm = MathRound(lots / step) * step;
   if(norm < minLot) norm = minLot;
   if(norm > maxLot) norm = maxLot;

   return norm;
  }

//+------------------------------------------------------------------+
//| Fixed DAX volume (InpLots) + dynamic matching of NQ ONLY         |
//+------------------------------------------------------------------+
void CalculateOptimalPairLots(double &outDaxLots, double &outNqLots)
  {
   // DAX always uses the fixed value defined in InpLots
   outDaxLots = NormalizeLot(InpSymbol1, InpLots);

   double daxPrice = SymbolInfoDouble(InpSymbol1, SYMBOL_BID);
   double nqPrice  = SymbolInfoDouble(InpSymbol2, SYMBOL_ASK);

   double daxContractSize = SymbolInfoDouble(InpSymbol1, SYMBOL_TRADE_CONTRACT_SIZE);
   double nqContractSize  = SymbolInfoDouble(InpSymbol2, SYMBOL_TRADE_CONTRACT_SIZE);

   if(daxContractSize <= 0) daxContractSize = 1.0;
   if(nqContractSize <= 0)  nqContractSize  = 1.0;

   string eurusdSym = "EURUSD.pro";
   if(!SymbolInfoDouble(eurusdSym, SYMBOL_BID)) eurusdSym = "EURUSD";
   double eurusdPrice = SymbolInfoDouble(eurusdSym, SYMBOL_BID);

   // Safety net in case of missing quotes
   if(daxPrice <= 0 || nqPrice <= 0 || eurusdPrice <= 0)
     {
      outNqLots = NormalizeLot(InpSymbol2, InpLots);
      return;
     }

   // DAX position value in EUR
   double daxValueEUR = outDaxLots * daxPrice * daxContractSize;

   // Value of 1 NQ lot in EUR
   double nqOneLotValueEUR = (nqPrice * nqContractSize) / eurusdPrice;

   if(nqOneLotValueEUR <= 0)
     {
      outNqLots = NormalizeLot(InpSymbol2, InpLots);
      return;
     }

   // Ideal NQ volume covering the DAX value, normalized to broker step
   double idealNqLots = daxValueEUR / nqOneLotValueEUR;
   outNqLots = NormalizeLot(InpSymbol2, idealNqLots);
  }

//+------------------------------------------------------------------+
//| Dynamic grid step                                                |
//| step = InpOpenRangePoints / (pairs that can still be opened)     |
//| The divisor is never lower than 2, so the last pair is opened    |
//| after OpenRange / 2 points (e.g. 1000 for a range of 2000).      |
//| Example (range 2000): 40 left -> 50, 39 left -> 51.3, ...,       |
//| 2 left -> 1000, 1 left -> 1000.                                  |
//+------------------------------------------------------------------+
double CalculateDynamicStep(const int activeCount)
  {
   int remaining = InpMaxPairs - activeCount;   // pairs that can still be opened
   if(remaining < 1)
      return 0.0;

   int divisor = (remaining < 2) ? 2 : remaining;
   return InpOpenRangePoints / (double)divisor;
  }

//+------------------------------------------------------------------+
//| Finds an open position on a given symbol with a given magic      |
//+------------------------------------------------------------------+
ulong FindPositionTicket(const string sym,long magic)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
      return ticket;
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| First free pair index (1..InpMaxPairs)                           |
//+------------------------------------------------------------------+
int FindNextFreeIndex()
  {
   for(int idx=1; idx<=InpMaxPairs; idx++)
     {
      long magic = InpMagicBase+idx;
      if(FindPositionTicket(InpSymbol1,magic)==0 &&
         FindPositionTicket(InpSymbol2,magic)==0)
         return idx;
     }
   return -1;
  }

//+------------------------------------------------------------------+
//| Opens a pair: FIRST DE30 SHORT, THEN US100 LONG                  |
//+------------------------------------------------------------------+
bool OpenPair(int idx, double refSpread)
  {
   long   magic = InpMagicBase + idx;
   string cmt   = InpCommentPrefix + " " + IntegerToString(idx);

   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   // Fixed DAX lot and dynamic NQ lot
   double lot1 = 0.0;
   double lot2 = 0.0;
   CalculateOptimalPairLots(lot1, lot2);

   // Make sure lots do not exceed InpMaxPositionSize
   lot1 = NormalizeLot(InpSymbol1, lot1);
   lot2 = NormalizeLot(InpSymbol2, lot2);

   // 1. DAX (DE30) FIRST
   trade.SetTypeFillingBySymbol(InpSymbol1);
   if(!trade.Sell(lot1, InpSymbol1, 0, 0, 0, cmt))
     {
      Print("Failed to open SHORT ", InpSymbol1, " (pair #", idx, ")");
      lastTransactionTime = GetTickCount64();
      return false;
     }

   // 2. NASDAQ (US100) SECOND
   trade.SetTypeFillingBySymbol(InpSymbol2);
   if(!trade.Buy(lot2, InpSymbol2, 0, 0, 0, cmt))
     {
      Print("Failed to open LONG ", InpSymbol2, " (pair #", idx, ") -> closing orphaned ", InpSymbol1);
      ulong t1 = FindPositionTicket(InpSymbol1, magic);
      if(t1 > 0)
        {
         trade.SetTypeFillingBySymbol(InpSymbol1);
         trade.PositionClose(t1);
        }
      lastTransactionTime = GetTickCount64();
      return false;
     }

   Print("Opened pair #", idx, " | spread: ", DoubleToString(refSpread, 1),
         " | DE30: ", lot1, " lots | US100: ", lot2, " lots");
   lastTransactionTime = GetTickCount64();
   return true;
  }

//+------------------------------------------------------------------+
//| Closes both legs of a pair: FIRST DE30, THEN US100               |
//+------------------------------------------------------------------+
bool ClosePair(int idx,const string reason)
  {
   long magic = InpMagicBase+idx;
   ulong t1 = FindPositionTicket(InpSymbol1,magic); // DE30
   ulong t2 = FindPositionTicket(InpSymbol2,magic); // US100
   bool ok = true;

   // 1. ALWAYS CLOSE DE30 (DAX) FIRST
   if(t1 > 0)
     {
      trade.SetTypeFillingBySymbol(InpSymbol1);
      if(!trade.PositionClose(t1))
        {
         ok = false;
         Print("Failed to close leg ", InpSymbol1, " of pair #", idx);
        }
     }

   // 2. ALWAYS CLOSE US100 (NASDAQ) SECOND
   if(t2 > 0)
     {
      trade.SetTypeFillingBySymbol(InpSymbol2);
      if(!trade.PositionClose(t2))
        {
         ok = false;
         Print("Failed to close leg ", InpSymbol2, " of pair #", idx);
        }
     }

   if(ok)
      Print("Closed pair #", idx, " (order: DE30 -> US100) reason: ", reason);

   lastTransactionTime = GetTickCount64();
   return ok;
  }

//+------------------------------------------------------------------+
//| Displays the summary panel on the chart                          |
//+------------------------------------------------------------------+
void UpdateDashboard(int activeCount, double openCostSpread, double closableSpread, double nextStep,
                     double nextTrigger,
                     const bool &isActive[], const double &entrySpread[], const double &pairProfitEUR[])
  {
   string txt = "";

   for(int p = 0; p < InpDashboardPadding; p++)
      txt += "\n";

   txt += "                             === DE30 vs US100 Spread EA ===\n";

   if(TimeCurrent() < tradingAllowedTime)
     {
      int remainingSec = (int)(tradingAllowedTime - TimeCurrent());
      txt += "                             [ STATUS: Waiting after night break: " + IntegerToString(remainingSec) + "s ]\n";
     }

   txt += "                             Active pairs: " + IntegerToString(activeCount) + " / " + IntegerToString(InpMaxPairs) + "\n";
   txt += "                             Spread (open): " + DoubleToString(openCostSpread, 2) + " pts | (close): " + DoubleToString(closableSpread, 2) + " pts\n";

   txt += "                             ---------------------------------------------------\n";
   txt += "                                 #   |   Entry Spread    |    Profit (EUR)\n";
   txt += "                             ---------------------------------------------------\n";

   if(isActive[1])
     {
      txt += "                                #01   |      " + DoubleToString(entrySpread[1], 1) + "        |      " +
             DoubleToString(pairProfitEUR[1], 2) + " EUR\n";
     }

   int activeIndices[];
   int count = 0;
   for(int idx = 2; idx <= InpMaxPairs; idx++)
     {
      if(isActive[idx])
        {
         ArrayResize(activeIndices, count + 1);
         activeIndices[count] = idx;
         count++;
        }
     }

   if(count > 0)
     {
      int startPos = (count > 5) ? (count - 5) : 0;
      for(int i = startPos; i < count; i++)
        {
         int idx = activeIndices[i];
         string pIdx = (idx < 10 ? " #0" : " #") + IntegerToString(idx);

         txt += "                               " + pIdx + "   |      " + DoubleToString(entrySpread[idx], 1) + "        |      " +
                DoubleToString(pairProfitEUR[idx], 2) + " EUR\n";
        }
     }
   else if(!isActive[1])
     {
      txt += "                                            ( No active positions )\n";
     }

   // "#Next" row: spread at which the next pair opens and, in brackets, the required distance (step)
   txt += "                             ---------------------------------------------------\n";
   if(activeCount == 0)
      txt += "                               #Next  |      " + DoubleToString(InpStartGapPoints, 1) + "  (start gap)\n";
   else if(nextStep > 0)
      txt += "                               #Next  |      " + DoubleToString(nextTrigger, 1) + "  (" + DoubleToString(nextStep, 1) + " pts)\n";
   else
      txt += "                               #Next  |      -  (max pairs reached)\n";

   Comment(txt);
  }

//+------------------------------------------------------------------+
//| Main execution function (shared by OnTick and OnTimer)           |
//+------------------------------------------------------------------+
void ProcessLogic()
  {
   // 1. Check whether both instruments are tradable
   bool sym1Tradable = IsSymbolTradable(InpSymbol1);
   bool sym2Tradable = IsSymbolTradable(InpSymbol2);

   // If ANY of them is not tradable (e.g. night break), mark a session break
   if(!sym1Tradable || !sym2Tradable)
     {
      wasSessionBreak = true;
      Comment("DE30vsUS100 EA: waiting - at least one instrument is in a trading break");
      return;
     }

   // 2. If there was a break and BOTH symbols just came back:
   if(wasSessionBreak)
     {
      wasSessionBreak    = false;
      tradingAllowedTime = TimeCurrent() + InpStartDelaySec;
      Print("Trading resumed after break. Opening blocked for ", InpStartDelaySec, " sec.");
     }

   double bid1 = SymbolInfoDouble(InpSymbol1, SYMBOL_BID);
   double ask1 = SymbolInfoDouble(InpSymbol1, SYMBOL_ASK);
   double bid2 = SymbolInfoDouble(InpSymbol2, SYMBOL_BID);
   double ask2 = SymbolInfoDouble(InpSymbol2, SYMBOL_ASK);

   double closableSpread = bid2 - ask1;
   double openCostSpread = ask2 - bid1;

   bool   pairIsActive[];
   double pairEntrySpread[];
   double pairProfitEUR[];

   ArrayResize(pairIsActive, InpMaxPairs + 1);
   ArrayResize(pairEntrySpread, InpMaxPairs + 1);
   ArrayResize(pairProfitEUR, InpMaxPairs + 1);

   ArrayInitialize(pairIsActive, false);
   ArrayInitialize(pairEntrySpread, 0.0);
   ArrayInitialize(pairProfitEUR, 0.0);

   int activeCount = 0;
   double minActiveEntry = 999999.0;

   // Cooldown between trades
   bool canTrade = true;
   if(InpMinTradeIntervalSec > 0)
     {
      ulong elapsedMS = GetTickCount64() - lastTransactionTime;
      if(elapsedMS < (ulong)InpMinTradeIntervalSec * 1000)
         canTrade = false;
     }

   // 3) Check positions, money-based TP and handle orphaned legs
   for(int idx = 1; idx <= InpMaxPairs; idx++)
     {
      long magic = InpMagicBase + idx;
      ulong t1 = FindPositionTicket(InpSymbol1, magic); // DE30
      ulong t2 = FindPositionTicket(InpSymbol2, magic); // US100

      if(t1 > 0 && t2 > 0)
        {
         double moneyProfit = 0.0;
         double daxOpen = 0, nqOpen = 0;

         if(PositionSelectByTicket(t1))
           {
            moneyProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            daxOpen = PositionGetDouble(POSITION_PRICE_OPEN);
           }
         if(PositionSelectByTicket(t2))
           {
            moneyProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            nqOpen = PositionGetDouble(POSITION_PRICE_OPEN);
           }

         // Check profit threshold in EUR
         if(moneyProfit >= InpTakeProfitEUR)
           {
            if(canTrade)
               ClosePair(idx, "TP reached: " + DoubleToString(moneyProfit, 2) + " EUR");
           }
         else
           {
            double entrySpread = nqOpen - daxOpen;
            activeCount++;
            pairIsActive[idx]    = true;
            pairEntrySpread[idx] = entrySpread;
            pairProfitEUR[idx]   = moneyProfit;

            if(entrySpread < minActiveEntry)
               minActiveEntry = entrySpread;
           }
        }
      else if(t1 > 0 && t2 == 0)
        {
         if(PositionSelectByTicket(t1))
           {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(TimeCurrent() - openTime > InpOrphanDelaySec && canTrade)
              {
               Print("Leg ", InpSymbol2, " did not open. Closing orphaned ", InpSymbol1);
               trade.SetTypeFillingBySymbol(InpSymbol1);
               trade.PositionClose(t1);
               lastTransactionTime = GetTickCount64();
              }
           }
        }
      else if(t2 > 0 && t1 == 0)
        {
         if(PositionSelectByTicket(t2))
           {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(TimeCurrent() - openTime > InpOrphanDelaySec && canTrade)
              {
               Print("Leg ", InpSymbol1, " did not open. Closing orphaned ", InpSymbol2);
               trade.SetTypeFillingBySymbol(InpSymbol2);
               trade.PositionClose(t2);
               lastTransactionTime = GetTickCount64();
              }
           }
        }
     }

   // Dynamic step recalculated on every pass from the number of pairs still available
   double nextStep    = (activeCount > 0) ? CalculateDynamicStep(activeCount) : 0.0;
   double nextTrigger = (activeCount > 0) ? (minActiveEntry - nextStep) : InpStartGapPoints;

   // 4) Open new positions (protected after trading resumes)
   if(canTrade && TimeCurrent() >= tradingAllowedTime)
     {
      bool inRange = true;
      if(InpRangeMin != 0 && openCostSpread < InpRangeMin) inRange = false;
      if(InpRangeMax != 0 && openCostSpread > InpRangeMax) inRange = false;

      if(inRange && activeCount < InpMaxPairs)
        {
         int nextIdx = FindNextFreeIndex();
         if(nextIdx != -1)
           {
            if(activeCount == 0)
              {
               if(openCostSpread <= InpStartGapPoints)
                  OpenPair(nextIdx, openCostSpread);
              }
            else
              {
               // Spread must drop by the dynamic step below the lowest active entry
               if(minActiveEntry - openCostSpread >= nextStep)
                  OpenPair(nextIdx, openCostSpread);
              }
           }
        }
     }

   // 5) Update the information panel
   UpdateDashboard(activeCount, openCostSpread, closableSpread, nextStep, nextTrigger,
                   pairIsActive, pairEntrySpread, pairProfitEUR);
  }

//+------------------------------------------------------------------+
//| OnTick (for Strategy Tester)                                     |
//+------------------------------------------------------------------+
void OnTick()
  {
   ProcessLogic();
  }

//+------------------------------------------------------------------+
//| OnTimer (for live trading - refresh every InpTimerMS)            |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ProcessLogic();
  }
//+------------------------------------------------------------------+