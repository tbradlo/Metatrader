//+------------------------------------------------------------------+
//|                                     DE30vsUS100_SpreadEA_v4.mq5  |
//|  EA handluje parami: DE30.pro LONG + US100.pro SHORT             |
//|  (gramy na ZMNIEJSZENIE spreadu NQ - DAX).                       |
//|  Otwiera pary gdy spread >= InpStartGapPoints (6000)             |
//|  i dokladnie co InpGridStepPoints (100) dalszego WZROSTU spreadu.|
//|  Brak TP na pare. Gdy jest >= InpMinPairsForExit par, NAJGORSZA  |
//|  POLOWA (najnizszy spread wejscia) jest zamykana, gdy dana para  |
//|  osiagnie >= 0 EUR (z swapem). Sprawdzane na kazdym ticku/timerze|
//|  Najlepsze pozycje (najwyzszy spread wejscia) sa gromadzone.     |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "0.01"
#property strict

#include <Trade\Trade.mqh>

//--- Parametry wejsciowe
input group "=== Instrumenty ==="
input string InpSymbol1 = "DE30.pro";       // Symbol 1 - DAX (LONG) - ZAWSZE WYKONYWANY PIERWSZY
input string InpSymbol2 = "US100.pro";      // Symbol 2 - Nasdaq (SHORT) - ZAWSZE WYKONYWANY DRUGI

input group "=== Wielkosc pozycji ==="
input double InpLots                 = 0.006;  // Baza: Lot na DE30 (US100 dopasuje sie dynamicznie)
input double InpDaxPositionTolerance = 0.001;  // Tolerancja lota DE30 (+/-) dla min. tracking error
input double InpMaxPositionSize      = 0.03;   // Maksymalny dozwolony wolumen pojedynczej pozycji (Hard Limit)

input group "=== Wyjscie (wymiana najgorszych pozycji) ==="
input int    InpMinPairsForExit = 3;        // Min. liczba otwartych par, od ktorej dzialaja zamkniecia
input double InpExitProfitEUR   = 0.0;      // Zamykaj najgorsza polowe (najnizszy spread wejscia) gdy zysk pary (z swapem) >= tej kwoty (EUR)

input group "=== Logika wejscia ==="
input double InpStartGapPoints  = 6000;     // Prog startowy: otwieramy 1. pare gdy spread (NQ-DAX) >= ta wartosc
input double InpGridStepPoints  = 100;      // Co ile punktow WZROSTU spreadu dokladamy kolejna pare
input double InpRangeMin        = 0;        // Dolna granica spreadu do handlu (0 = wylaczone)
input double InpRangeMax        = 0;        // Gorna granica spreadu do handlu (0 = wylaczone)
input int    InpMaxPairs        = 30;       // Maksymalna liczba jednoczesnie otwartych par

input group "=== Wyglad Panelu ==="
input int    InpDashboardPadding = 18;      // Liczba pustych wierszy (przesun panel w dol)

input group "=== Identyfikacja ==="
input int    InpMagicBase       = 555000;   // Bazowy magic number (kazda para = MagicBase + index)
input string InpCommentPrefix   = "DE30vsUS100"; // Prefiks komentarza pozycji

input group "=== Zabezpieczenia i Czas ==="
input int    InpStartDelaySec       = 60;   // Opuznienie otwarcia po przerwie nocnej (sekundy)
input int    InpMinTradeIntervalSec = 3;    // Min. czas przerwy miedzy transakcjami (sekundy)
input int    InpMaxQuoteAgeSec      = 120;  // Maks. wiek kwotowania (s), zeby uznac instrument za "tradowalny"
input int    InpSlippagePoints      = 50;   // Dozwolony poslizg (w punktach) przy market execution
input int    InpTimerMS             = 500;  // Czestotliwosc timera (ms) dla Live Trading
input int    InpOrphanDelaySec      = 5;    // Czas oczekiwania (s) przed uznaniem nogi za osierocona

CTrade trade;

//--- Zmienne kontroli czasu
ulong    lastTransactionTime = 0;    // Czas ostatniej transakcji w milisekundach
datetime tradingAllowedTime  = 0;    // Czas (timestamp), od ktorego mozna otwierac nowe pozycje
bool     wasSessionBreak     = false;// Flaga informująca, czy wystąpiła przerwa handlowa

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
         " MinPairsForExit=",InpMinPairsForExit," ExitProfitEUR=",InpExitProfitEUR,
         " MaxPairs=",InpMaxPairs,
         " DaxTolerance=",InpDaxPositionTolerance, " MaxPosSize=",InpMaxPositionSize);
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
//| Normalizacja lota do min/max/step oraz InpMaxPositionSize        |
//+------------------------------------------------------------------+
double NormalizeLot(const string sym, double lots)
  {
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.001;

   // Uwzględnienie InpMaxPositionSize jako dodatkowego limitu górnego
   if(InpMaxPositionSize > 0 && maxLot > InpMaxPositionSize)
      maxLot = InpMaxPositionSize;

   if(lots < minLot) lots = minLot;

   double norm = MathRound(lots / step) * step;
   if(norm < minLot) norm = minLot;
   if(norm > maxLot) norm = maxLot;

   return norm;
  }

//+------------------------------------------------------------------+
//| Szuka optymalnych wolumenow (DE30 i US100) minimalizujacych      |
//| Tracking Error w zakresie InpLots +/- InpDaxPositionTolerance    |
//+------------------------------------------------------------------+
void CalculateOptimalPairLots(double &outDaxLots, double &outNqLots)
  {
   double daxPrice = SymbolInfoDouble(InpSymbol1, SYMBOL_ASK);
   double nqPrice  = SymbolInfoDouble(InpSymbol2, SYMBOL_BID);

   double daxContractSize = SymbolInfoDouble(InpSymbol1, SYMBOL_TRADE_CONTRACT_SIZE);
   double nqContractSize  = SymbolInfoDouble(InpSymbol2, SYMBOL_TRADE_CONTRACT_SIZE);

   if(daxContractSize <= 0) daxContractSize = 1.0;
   if(nqContractSize <= 0)  nqContractSize  = 1.0;

   string eurusdSym = "EURUSD.pro";
   if(!SymbolInfoDouble(eurusdSym, SYMBOL_BID)) eurusdSym = "EURUSD";
   double eurusdPrice = SymbolInfoDouble(eurusdSym, SYMBOL_BID);

   // Zabezpieczenie na przypadek braku kwotowań
   if(daxPrice <= 0 || nqPrice <= 0 || eurusdPrice <= 0)
     {
      outDaxLots = NormalizeLot(InpSymbol1, InpLots);
      outNqLots  = NormalizeLot(InpSymbol2, InpLots);
      return;
     }

   double daxStep = SymbolInfoDouble(InpSymbol1, SYMBOL_VOLUME_STEP);
   if(daxStep <= 0) daxStep = 0.001;

   double minDax = NormalizeLot(InpSymbol1, InpLots - InpDaxPositionTolerance);
   double maxDax = NormalizeLot(InpSymbol1, InpLots + InpDaxPositionTolerance);

   double nqOneLotValueEUR = (nqPrice * nqContractSize) / eurusdPrice;

   double bestDaxLots         = NormalizeLot(InpSymbol1, InpLots);
   double bestNqLots          = NormalizeLot(InpSymbol2, (bestDaxLots * daxPrice * daxContractSize) / nqOneLotValueEUR);
   double minTrackingErrorEUR = 9999999.0;

   // Pętla przechodząca przez wszystkie akceptowalne wolumeny DAX
   for(double candDax = minDax; candDax <= maxDax + 0.000001; candDax += daxStep)
     {
      candDax = NormalizeLot(InpSymbol1, candDax);

      double daxValueEUR      = candDax * daxPrice * daxContractSize;
      double idealNqLots     = daxValueEUR / nqOneLotValueEUR;
      double normNqLots      = NormalizeLot(InpSymbol2, idealNqLots);

      double actualNqValueEUR = normNqLots * nqOneLotValueEUR;
      double trackingErrorEUR = MathAbs(daxValueEUR - actualNqValueEUR);

      // Wybieramy kombinację o najmniejszym błędzie dopasowania (EUR)
      if(trackingErrorEUR < minTrackingErrorEUR)
        {
         minTrackingErrorEUR = trackingErrorEUR;
         bestDaxLots         = candDax;
         bestNqLots          = normNqLots;
        }
     }

   outDaxLots = bestDaxLots;
   outNqLots  = bestNqLots;
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
//| Otwiera pare: NAJPIERW DE30 LONG, NASTEPNIE US100 SHORT          |
//+------------------------------------------------------------------+
bool OpenPair(int idx, double refSpread)
  {
   long   magic = InpMagicBase + idx;
   string cmt   = InpCommentPrefix + " " + IntegerToString(idx);

   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   // Dynamiczne wyliczenie zoptymalizowanych wolumenow z minimalnym tracking error
   double lot1 = 0.0;
   double lot2 = 0.0;
   CalculateOptimalPairLots(lot1, lot2);

   // Zabezpieczające upewnienie się, że loty nie przekraczają InpMaxPositionSize
   lot1 = NormalizeLot(InpSymbol1, lot1);
   lot2 = NormalizeLot(InpSymbol2, lot2);

   // 1. NAJPIERW DAX (DE30)
   trade.SetTypeFillingBySymbol(InpSymbol1);
   if(!trade.Buy(lot1, InpSymbol1, 0, 0, 0, cmt))
     {
      Print("Blad otwarcia LONG ", InpSymbol1, " (para #", idx, ")");
      lastTransactionTime = GetTickCount64();
      return false;
     }

   // 2. NASTEPNIE NASDAQ (US100)
   trade.SetTypeFillingBySymbol(InpSymbol2);
   if(!trade.Sell(lot2, InpSymbol2, 0, 0, 0, cmt))
     {
      Print("Blad otwarcia SHORT ", InpSymbol2, " (para #", idx, ") -> zamykam osierocony ", InpSymbol1);
      ulong t1 = FindPositionTicket(InpSymbol1, magic);
      if(t1 > 0)
        {
         trade.SetTypeFillingBySymbol(InpSymbol1);
         trade.PositionClose(t1);
        }
      lastTransactionTime = GetTickCount64();
      return false;
     }

   Print("Otwarto pare #", idx, " | spread: ", DoubleToString(refSpread, 1),
         " | DE30: ", lot1, " lota | US100: ", lot2, " lota");
   lastTransactionTime = GetTickCount64();
   return true;
  }

//+------------------------------------------------------------------+
//| Zamyka obie nogi danej pary: NAJPIERW DE30, NASTEPNIE US100      |
//+------------------------------------------------------------------+
bool ClosePair(int idx,const string reason)
  {
   long magic = InpMagicBase+idx;
   ulong t1 = FindPositionTicket(InpSymbol1,magic); // DE30
   ulong t2 = FindPositionTicket(InpSymbol2,magic); // US100
   bool ok = true;

   // 1. ZAWSZE NAJPIERW ZAMYKAMY DE30 (DAX)
   if(t1 > 0)
     {
      trade.SetTypeFillingBySymbol(InpSymbol1);
      if(!trade.PositionClose(t1))
        {
         ok = false;
         Print("Blad zamkniecia nogi ", InpSymbol1, " pary #", idx);
        }
     }

   // 2. ZAWSZE DRUGI ZAMYKAMY US100 (NASDAQ)
   if(t2 > 0)
     {
      trade.SetTypeFillingBySymbol(InpSymbol2);
      if(!trade.PositionClose(t2))
        {
         ok = false;
         Print("Blad zamkniecia nogi ", InpSymbol2, " pary #", idx);
        }
     }

   if(ok)
      Print("Zamknieto pare #", idx, " (Kolejnosc: DE30 -> US100) powod: ", reason);

   lastTransactionTime = GetTickCount64();
   return ok;
  }

//+------------------------------------------------------------------+
//| Wyswietlanie podsumowania w wybranym miejscu okna                |
//+------------------------------------------------------------------+
void UpdateDashboard(int activeCount, double openCostSpread, double closableSpread,
                     const bool &isActive[], const double &entrySpread[], const double &pairProfitEUR[])
  {
   string txt = "";

   for(int p = 0; p < InpDashboardPadding; p++)
      txt += "\n";

   txt += "                              === DE30 vs US100 Spread EA v4 ===\n";

   if(TimeCurrent() < tradingAllowedTime)
     {
      int remainingSec = (int)(tradingAllowedTime - TimeCurrent());
      txt += "                              [ STATUS: Oczekiwanie po przerwie nocnej: " + IntegerToString(remainingSec) + "s ]\n";
     }

   txt += "                              Aktywne pary: " + IntegerToString(activeCount) + " / " + IntegerToString(InpMaxPairs) + "\n";
   txt += "                              Spread (otwarcie): " + DoubleToString(openCostSpread, 2) + " pkt | (zamkniecie): " + DoubleToString(closableSpread, 2) + " pkt\n";
   txt += "                              Wejscie: >= " + DoubleToString(InpStartGapPoints, 0) + " pkt, krok +" + DoubleToString(InpGridStepPoints, 0) + " pkt (gramy na spadek spreadu)\n";
   txt += "                              Wymiana: najgorsza polowa przy >= " + IntegerToString(InpMinPairsForExit) + " par, zamkniecie gdy >= " + DoubleToString(InpExitProfitEUR, 2) + " EUR\n";
   txt += "                              ---------------------------------------------------\n";
   txt += "                                  #   |  Spread Wejscia  |    Profit (EUR)\n";
   txt += "                              ---------------------------------------------------\n";

   int activeIndices[];
   int count = 0;
   for(int idx = 1; idx <= InpMaxPairs; idx++)
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
      int startPos = (count > 6) ? (count - 6) : 0;
      for(int i = startPos; i < count; i++)
        {
         int idx = activeIndices[i];
         string pIdx = (idx < 10 ? " #0" : " #") + IntegerToString(idx);

         txt += "                               " + pIdx + "   |      " + DoubleToString(entrySpread[idx], 1) + "       |     " +
                DoubleToString(pairProfitEUR[idx], 2) + " EUR\n";
        }
     }
   else
     {
      txt += "                                       ( Brak aktywnych pozycji )\n";
     }

   Comment(txt);
  }

//+------------------------------------------------------------------+
//| Główna funkcja wykonawcza (wspólna dla OnTick i OnTimer)         |
//+------------------------------------------------------------------+
void ProcessLogic()
  {
   // 1. Sprawdzamy, czy oba instrumenty są tradowalne
   bool sym1Tradable = IsSymbolTradable(InpSymbol1);
   bool sym2Tradable = IsSymbolTradable(InpSymbol2);

   // Jeśli KTÓRYKOLWIEK jest nietradowalny (np. przerwa nocna), oznaczamy przerwę w sesji
   if(!sym1Tradable || !sym2Tradable)
     {
      wasSessionBreak = true;
      Comment("DE30vsUS100 EA: czekam - co najmniej jeden z instrumentow w przerwie handlowej");
      return;
     }

   // 2. Jeśli wystąpiła przerwa w tradowaniu i OBA symbole właśnie wróciły do gry:
   if(wasSessionBreak)
     {
      wasSessionBreak    = false;
      tradingAllowedTime = TimeCurrent() + InpStartDelaySec;
      Print("Wznowienie handlu po przerwie nocnej. Blokada otwarcia pozycji na ", InpStartDelaySec, " sek.");
     }

   double bid1 = SymbolInfoDouble(InpSymbol1, SYMBOL_BID);
   double ask1 = SymbolInfoDouble(InpSymbol1, SYMBOL_ASK);
   double bid2 = SymbolInfoDouble(InpSymbol2, SYMBOL_BID);
   double ask2 = SymbolInfoDouble(InpSymbol2, SYMBOL_ASK);

   // DAX LONG (kupno po ask1) + NQ SHORT (sprzedaz po bid2)
   double openCostSpread = bid2 - ask1;   // spread po ktorym otwieramy pare
   double closableSpread = ask2 - bid1;   // spread po ktorym zamykamy pare

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
   double maxActiveEntry = -999999.0;

   // Sprawdzanie czasu dla transakcji handlowych (Cooldown)
   bool canTrade = true;
   if(InpMinTradeIntervalSec > 0)
     {
      ulong elapsedMS = GetTickCount64() - lastTransactionTime;
      if(elapsedMS < (ulong)InpMinTradeIntervalSec * 1000)
         canTrade = false;
     }

   // 3) Zbieranie danych o parach oraz obsługa osieroconych nóg
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

         double entrySpread = nqOpen - daxOpen;
         activeCount++;
         pairIsActive[idx]    = true;
         pairEntrySpread[idx] = entrySpread;
         pairProfitEUR[idx]   = moneyProfit;

         if(entrySpread > maxActiveEntry)
            maxActiveEntry = entrySpread;
        }
      else if(t1 > 0 && t2 == 0)
        {
         if(PositionSelectByTicket(t1))
           {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(TimeCurrent() - openTime > InpOrphanDelaySec && canTrade)
              {
               Print("Noga ", InpSymbol2, " nie otworzyla sie. Zamykam osierocony ", InpSymbol1);
               trade.SetTypeFillingBySymbol(InpSymbol1);
               trade.PositionClose(t1);
               lastTransactionTime = GetTickCount64();
               canTrade = false;
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
               Print("Noga ", InpSymbol1, " nie otworzyla sie. Zamykam osierocony ", InpSymbol2);
               trade.SetTypeFillingBySymbol(InpSymbol2);
               trade.PositionClose(t2);
               lastTransactionTime = GetTickCount64();
               canTrade = false;
              }
           }
        }
     }

   // 3b) Wymiana pozycji: gdy jest >= InpMinPairsForExit par, najgorsza polowa
   //     (najnizszy spread wejscia) jest zamykana gdy para wyjdzie >= InpExitProfitEUR
   if(canTrade && activeCount >= InpMinPairsForExit && activeCount > 0)
     {
      int list[];
      int n = 0;
      for(int idx = 1; idx <= InpMaxPairs; idx++)
        {
         if(pairIsActive[idx])
           {
            ArrayResize(list, n + 1);
            list[n] = idx;
            n++;
           }
        }

      // Sortowanie rosnaco po spreadzie wejscia (najgorsze = najnizszy spread wejscia na poczatku)
      for(int a = 0; a < n - 1; a++)
         for(int b = 0; b < n - 1 - a; b++)
            if(pairEntrySpread[list[b]] > pairEntrySpread[list[b + 1]])
              {
               int tmp     = list[b];
               list[b]     = list[b + 1];
               list[b + 1] = tmp;
              }

      int worstCount = n / 2;
      if(worstCount < 1) worstCount = 1;

      for(int k = 0; k < worstCount; k++)
        {
         int widx = list[k];
         if(pairProfitEUR[widx] >= InpExitProfitEUR)
           {
            if(ClosePair(widx, "Wymiana najgorszej pozycji, profit: " + DoubleToString(pairProfitEUR[widx], 2) + " EUR"))
              {
               pairIsActive[widx] = false;
               activeCount--;
              }
            canTrade = false;   // jedna operacja na cykl (cooldown)
            break;
           }
        }
     }

   // 4) Otwieranie nowych pozycji (Zabezpieczenie po wznowieniu handlu)
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
               if(openCostSpread >= InpStartGapPoints)
                  OpenPair(nextIdx, openCostSpread);
              }
            else
              {
               // Kolejna para tylko gdy spread wzrosl o >= GridStep powyzej NAJWYZSZEGO spreadu wejscia
               if(openCostSpread - maxActiveEntry >= InpGridStepPoints)
                  OpenPair(nextIdx, openCostSpread);
              }
           }
        }
     }

   // 5) Aktualizacja panelu informacyjnego
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