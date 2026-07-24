//+------------------------------------------------------------------+
//|                                        DE30vsUS100_SpreadEA.mq5  |
//|  EA handluje parami: DE30.pro SHORT + US100.pro LONG             |
//|  Otwiera kolejne pary gdy spread MALEJE (co InpGridStepPoints),  |
//|  kazda para ma wlasny TP wyrażony w kwocie EUR.                  |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "1.50"
#property strict

#include <Trade\Trade.mqh>

//--- Parametry wejsciowe
input group "=== Instrumenty ==="
input string InpSymbol1 = "DE30.pro";       // Symbol 1 - DAX (SHORT)
input string InpSymbol2 = "US100.pro";      // Symbol 2 - Nasdaq (LONG)

input group "=== Wielkosc pozycji ==="
input double InpLots = 0.004;               // Baza: Lot na DE30 (US100 dopasuje sie dynamicznie)

input group "=== Take Profit (Kwotowy) ==="
input double InpTakeProfitEUR = 5.0;        // TP na pare w kwocie (EUR)

input group "=== Logika wejscia ==="
input double InpStartGapPoints  = 3000;     // Prog startowy: otwieramy 1. pare gdy spread <= ta wartosc
input double InpGridStepPoints  = 50;       // Co ile punktow SPADKU spreadu dokladamy kolejna pare
input double InpRangeMin        = 0;        // Dolna granica spreadu do handlu (0 = wylaczone)
input double InpRangeMax        = 0;        // Gorna granica spreadu do handlu (0 = wylaczone)
input int    InpMaxPairs        = 30;       // Maksymalna liczba jednoczesnie otwartych par

input group "=== Identyfikacja ==="
input int    InpMagicBase       = 555000;   // Bazowy magic number (kazda para = MagicBase + index)
input string InpCommentPrefix   = "DE30vsUS100"; // Prefiks komentarza pozycji

input group "=== Inne ==="
input int    InpMaxQuoteAgeSec  = 120;      // Maks. wiek kwotowania (s), zeby uznac instrument za "tradowalny"
input int    InpSlippagePoints  = 50;       // Dozwolony poslizg (w punktach) przy market execution
input int    InpTimerMS         = 500;      // Czestotliwosc timera (ms) dla Live Trading
input int    InpOrphanDelaySec  = 5;        // Czas oczekiwania (s) przed uznaniem nogi za osierocona

CTrade trade;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!SymbolSelect(InpSymbol1,true))
      Print("UWAGA: nie mozna wybrac symbolu ",InpSymbol1);
   if(!SymbolSelect(InpSymbol2,true))
      Print("UWAGA: nie mozna wybrac symbolu ",InpSymbol2);

   trade.SetTypeFillingBySymbol(InpSymbol1);
   trade.SetDeviationInPoints(InpSlippagePoints);

   // Uruchomienie timera dla handlu na zywo
   EventSetMillisecondTimer(InpTimerMS);

   Print("DE30vsUS100 EA zainicjowany. MagicBase=",InpMagicBase,
         " StartGap=",InpStartGapPoints," GridStep=",InpGridStepPoints,
         " TP_EUR=",InpTakeProfitEUR, " MaxPairs=",InpMaxPairs);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
  }

//+------------------------------------------------------------------+
//| Czy instrument jest w tej chwili tradowalny                      |
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
//| Zwraca łączny zysk finansowy (Profit + Swap) w EUR dla danej pary|
//+------------------------------------------------------------------+
double GetPairMoneyProfit(int idx)
  {
   long magic = InpMagicBase + idx;
   double totalProfit = 0.0;
   bool foundLegs = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetInteger(POSITION_MAGIC) == magic)
           {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
            totalProfit += PositionGetDouble(POSITION_SWAP);
            foundLegs = true;
           }
        }
     }

   return foundLegs ? totalProfit : -99999.0;
  }

//+------------------------------------------------------------------+
//| Normalizacja lota do min/max/step danego symbolu                 |
//+------------------------------------------------------------------+
double NormalizeLot(const string sym,double lots)
  {
   double minLot = SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   if(step<=0) step=0.001;

   if(lots < minLot) lots = minLot;

   double norm = MathRound(lots/step)*step;
   if(norm<minLot) norm=minLot;
   if(norm>maxLot) norm=maxLot;
   return norm;
  }

//+------------------------------------------------------------------+
//| Wylicza zbalansowany lot dla US100 na podstawie pozycji na DE30  |
//+------------------------------------------------------------------+
double CalculateBalancedUS100Lot(double daxLots)
  {
   double daxPrice = SymbolInfoDouble(InpSymbol1, SYMBOL_BID);
   double nqPrice  = SymbolInfoDouble(InpSymbol2, SYMBOL_ASK);

   string eurusdSym = "EURUSD.pro";
   if(!SymbolInfoDouble(eurusdSym, SYMBOL_BID)) eurusdSym = "EURUSD";
   double eurusdPrice = SymbolInfoDouble(eurusdSym, SYMBOL_BID);

   if(daxPrice <= 0 || nqPrice <= 0 || eurusdPrice <= 0)
     {
      return daxLots;
     }

   double daxValueEUR = daxLots * daxPrice;
   double nqOneLotValueEUR = nqPrice / eurusdPrice;
   double targetNqLots = daxValueEUR / nqOneLotValueEUR;

   return NormalizeLot(InpSymbol2, targetNqLots);
  }

//+------------------------------------------------------------------+
//| Szuka otwartej pozycji na danym symbolu z danym magic            |
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
//| Pierwszy wolny indeks pary (1..InpMaxPairs)                      |
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
//| Otwiera pare: DE30 SHORT + US100 LONG                            |
//+------------------------------------------------------------------+
bool OpenPair(int idx, double refSpread)
  {
   long   magic = InpMagicBase + idx;
   string cmt   = InpCommentPrefix + " " + IntegerToString(idx);

   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   double lot1 = NormalizeLot(InpSymbol1, InpLots);
   double lot2 = CalculateBalancedUS100Lot(lot1);

   if(!trade.Sell(lot1, InpSymbol1, 0, 0, 0, cmt))
     {
      Print("Blad otwarcia SHORT ", InpSymbol1, " (para #", idx, ")");
      return false;
     }

   if(!trade.Buy(lot2, InpSymbol2, 0, 0, 0, cmt))
     {
      Print("Blad otwarcia LONG ", InpSymbol2, " (para #", idx, ") -> zamykam osierocona noge");
      ulong t1 = FindPositionTicket(InpSymbol1, magic);
      if(t1 > 0) trade.PositionClose(t1);
      return false;
     }

   Print("Otwarto pare #", idx, " | DE30: ", lot1, " lota | US100: ", lot2, " lota");
   return true;
  }

//+------------------------------------------------------------------+
//| Zamyka obie nogi danej pary                                      |
//+------------------------------------------------------------------+
bool ClosePair(int idx,const string reason)
  {
   long magic = InpMagicBase+idx;
   ulong t1 = FindPositionTicket(InpSymbol1,magic);
   ulong t2 = FindPositionTicket(InpSymbol2,magic);
   bool ok = true;

   if(t1>0 && !trade.PositionClose(t1))
     { ok=false; Print("Blad zamkniecia nogi ",InpSymbol1," pary #",idx); }

   if(t2>0 && !trade.PositionClose(t2))
     { ok=false; Print("Blad zamkniecia nogi ",InpSymbol2," pary #",idx); }

   if(ok)
      Print("Zamknieto pare #",idx," powod: ",reason);

   return ok;
  }

//+------------------------------------------------------------------+
//| Wyswietlanie podsumowania na wykresie                            |
//+------------------------------------------------------------------+
void UpdateDashboard(int activeCount, double openCostSpread, double closableSpread,
                     const bool &isActive[], const double &entrySpread[], const double &pairProfitEUR[])
  {
   string txt = "=== DE30 vs US100 Spread EA ===\n";
   txt += "Aktywne pary: " + IntegerToString(activeCount) + " / " + IntegerToString(InpMaxPairs) + "\n";
   txt += "Spread (otwarcie/koszt): " + DoubleToString(openCostSpread, 2) + " pkt\n";
   txt += "Spread (zamkniecie):     " + DoubleToString(closableSpread, 2) + " pkt\n";
   txt += "---------------------------------------------------\n";
   txt += "Para  | Stan       | Spread Wejscia | Profit (EUR) / Cel\n";
   txt += "---------------------------------------------------\n";

   // Zawsze wyświetlamy Parę #1
   string pIdx1 = " #01";
   if(isActive[1])
     {
      double diff = InpTakeProfitEUR - pairProfitEUR[1];
      string targetStr = (diff <= 0) ? "ZAMYKANIE..." : "do TP: " + DoubleToString(diff, 2) + " EUR";
      txt += "Para" + pIdx1 + " | AKTYWNA    | " + DoubleToString(entrySpread[1], 1) + "         | " +
             DoubleToString(pairProfitEUR[1], 2) + " EUR (" + targetStr + ")\n";
     }
   else
     {
      txt += "Para" + pIdx1 + " | WOLNA      | ---            | ---\n";
     }

   txt += "--- Ostatnie aktywne (max 5) ---\n";

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

   if(count == 0)
     {
      txt += " (Brak innych aktywnych par w rynku)\n";
     }
   else
     {
      int startPos = (count > 5) ? (count - 5) : 0;
      for(int i = startPos; i < count; i++)
        {
         int idx = activeIndices[i];
         string pIdx = (idx < 10 ? " #0" : " #") + IntegerToString(idx);
         double diff = InpTakeProfitEUR - pairProfitEUR[idx];
         string targetStr = (diff <= 0) ? "ZAMYKANIE..." : "do TP: " + DoubleToString(diff, 2) + " EUR";

         txt += "Para" + pIdx + " | AKTYWNA    | " + DoubleToString(entrySpread[idx], 1) + "         | " +
                DoubleToString(pairProfitEUR[idx], 2) + " EUR (" + targetStr + ")\n";
        }
     }

   Comment(txt);
  }

//+------------------------------------------------------------------+
//| Główna funkcja wykonawcza (wspólna dla OnTick i OnTimer)         |
//+------------------------------------------------------------------+
void ProcessLogic()
  {
   if(!IsSymbolTradable(InpSymbol1) || !IsSymbolTradable(InpSymbol2))
     {
      Comment("DE30vsUS100 EA: czekam - jeden z instrumentow nie jest tradowalny");
      return;
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

   // 1) Sprawdzanie pozycji, TP kwotowego oraz obsługa osieroconych nóg
   for(int idx = 1; idx <= InpMaxPairs; idx++)
     {
      long magic = InpMagicBase + idx;
      ulong t1 = FindPositionTicket(InpSymbol1, magic);
      ulong t2 = FindPositionTicket(InpSymbol2, magic);

      if(t1 > 0 && t2 > 0)
        {
         double moneyProfit = GetPairMoneyProfit(idx);

         // Sprawdzenie progu zysku w EUR
         if(moneyProfit >= InpTakeProfitEUR)
           {
            ClosePair(idx, "TP osiągnięty: " + DoubleToString(moneyProfit, 2) + " EUR (wymagane: " +
                      DoubleToString(InpTakeProfitEUR, 2) + " EUR)");
           }
         else
           {
            // Para wciąż w grze
            double daxOpen = 0, nqOpen = 0;
            if(PositionSelectByTicket(t1)) daxOpen = PositionGetDouble(POSITION_PRICE_OPEN);
            if(PositionSelectByTicket(t2)) nqOpen  = PositionGetDouble(POSITION_PRICE_OPEN);

            double entrySpread = nqOpen - daxOpen;

            activeCount++;
            pairIsActive[idx]     = true;
            pairEntrySpread[idx] = entrySpread;
            pairProfitEUR[idx]    = moneyProfit;

            if(entrySpread < minActiveEntry)
               minActiveEntry = entrySpread;
           }
        }
      else if(t1 > 0 && t2 == 0)
        {
         // Pobieramy czas otwarcia leg 1, aby uniknąć usuwania w trakcie realizacji leg 2 przez brokera
         if(PositionSelectByTicket(t1))
           {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(TimeCurrent() - openTime > InpOrphanDelaySec)
              {
               Print("Noga ", InpSymbol2, " nie otworzyla sie w ciagu ", InpOrphanDelaySec, "s. Zamykam osierocony ", InpSymbol1);
               trade.PositionClose(t1);
              }
           }
        }
      else if(t2 > 0 && t1 == 0)
        {
         if(PositionSelectByTicket(t2))
           {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(TimeCurrent() - openTime > InpOrphanDelaySec)
              {
               Print("Noga ", InpSymbol1, " nie otworzyla sie w ciagu ", InpOrphanDelaySec, "s. Zamykam osierocony ", InpSymbol2);
               trade.PositionClose(t2);
              }
           }
        }
     }

   // 2) Filtr zakresu dla nowych otwarć
   bool inRange = true;
   if(InpRangeMin != 0 && openCostSpread < InpRangeMin) inRange = false;
   if(InpRangeMax != 0 && openCostSpread > InpRangeMax) inRange = false;

   if(!inRange || activeCount >= InpMaxPairs)
     {
      UpdateDashboard(activeCount, openCostSpread, closableSpread, pairIsActive, pairEntrySpread, pairProfitEUR);
      return;
     }

   int nextIdx = FindNextFreeIndex();
   if(nextIdx == -1)
     {
      UpdateDashboard(activeCount, openCostSpread, closableSpread, pairIsActive, pairEntrySpread, pairProfitEUR);
      return;
     }

   // 3) Logika otwierania kolejnych par (Grid)
   if(activeCount == 0)
     {
      if(openCostSpread <= InpStartGapPoints)
         OpenPair(nextIdx, openCostSpread);
     }
   else
     {
      if(minActiveEntry - openCostSpread >= InpGridStepPoints)
         OpenPair(nextIdx, openCostSpread);
     }

   UpdateDashboard(activeCount, openCostSpread, closableSpread, pairIsActive, pairEntrySpread, pairProfitEUR);
  }

//+------------------------------------------------------------------+
//| OnTick (dla Testera Strategii)                                   |
//+------------------------------------------------------------------+
void OnTick()
  {
   ProcessLogic();
  }

//+------------------------------------------------------------------+
//| OnTimer (dla Handlu na Żywo - odświeżanie co InpTimerMS)         |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ProcessLogic();
  }
//+------------------------------------------------------------------+