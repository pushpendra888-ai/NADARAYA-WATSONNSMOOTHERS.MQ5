#include <Trade/Trade.mqh>
#property strict

input double lotSize     = 0.04;
input int    bandwidth   = 145;     // smoothing bandwidth
input double maxLossUSD  = 20;      // safety stop loss in USD
input long   magicNumber = 1001;

CTrade trade;
int      lastDirection = 0;         // 0 = none, 1 = buy, -1 = sell
datetime lastBarTime   = 0;

// Gaussian kernel
double Gauss(double x, double h) {
   return MathExp(-(x*x)/(2.0*h*h));
}

// Nadaraya–Watson smoothed value (endpoint, non-repainting)
double NadarayaWatson(int shift, double h) {
   int bars = Bars(_Symbol, PERIOD_M15);
   int limit = MathMin(200, bars - shift);
   if(limit <= 0) return 0.0;

   double num = 0.0, den = 0.0;
   for(int i=0; i<limit; i++) {
      double w = Gauss(i, h);
      num += iClose(_Symbol, PERIOD_M15, shift+i) * w;
      den += w;
   }
   return (den>0.0) ? num/den : 0.0;
}

// Close this EA's positions
void CloseAllMyPositions() {
   for(int idx=PositionsTotal()-1; idx>=0; idx--) {
      ulong ticket = PositionGetTicket(idx);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      long   mag = (long)PositionGetInteger(POSITION_MAGIC);
      if(sym==_Symbol && mag==magicNumber) {
         trade.PositionClose(ticket);
         Sleep(50);
      }
   }
}

// Safety max loss per trade
void CheckMyMaxLoss() {
   for(int idx=PositionsTotal()-1; idx>=0; idx--) {
      ulong ticket = PositionGetTicket(idx);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      long   mag = (long)PositionGetInteger(POSITION_MAGIC);
      if(sym==_Symbol && mag==magicNumber) {
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit <= -maxLossUSD) {
            trade.PositionClose(ticket);
            PrintFormat("Trade closed due to max loss (%.2f USD)", profit);
         }
      }
   }
}

int OnInit() {
   trade.SetExpertMagicNumber(magicNumber);
   return INIT_SUCCEEDED;
}

void OnTick() {
   CheckMyMaxLoss();

   datetime t = iTime(_Symbol, PERIOD_M15, 0);
   if(t==lastBarTime) return;
   lastBarTime = t;

   double cur  = NadarayaWatson(1, (double)bandwidth);
   double prev = NadarayaWatson(2, (double)bandwidth);

   if(lastDirection==0) {
      if(cur > prev) {
         if(trade.Buy(lotSize,_Symbol)) {
            Print("First BUY opened with slope up");
            lastDirection=1;
         }
      }
      else if(cur < prev) {
         if(trade.Sell(lotSize,_Symbol)) {
            Print("First SELL opened with slope down");
            lastDirection=-1;
         }
      }
      return;
   }

   if(cur > prev && lastDirection != 1) {
      CloseAllMyPositions();
      if(trade.Buy(lotSize,_Symbol)) {
         Print("BUY opened (slope flip up)");
         lastDirection=1;
      }
   }
   else if(cur < prev && lastDirection != -1) {
      CloseAllMyPositions();
      if(trade.Sell(lotSize,_Symbol)) {
         Print("SELL opened (slope flip down)");
         lastDirection=-1;
      }
   }
}
