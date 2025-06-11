//+------------------------------------------------------------------+
//|                                     RandomEntryTimeTrailing.mq5   |
//|                                                                   |
//|     Random entry with time-based trailing stop relaxation         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property version   "1.00"
#property strict

// Input Parameters
input string   StartTime         = "06:00";    // Daily trading start time (HH:MM)
input string   EndTime           = "18:00";    // Daily trading end time (HH:MM)
input int      DailyTrades       = 5;          // Number of trades per day
input double   PositionSize      = 0.01;       // Fixed lot size
input int      InpATRPeriod      = 14;         // ATR Period
input double   InpATRMultiplier  = 2.0;        // ATR Multiplier for stop loss
input double   InpTrailStart     = 30;         // Trailing start in points
input double   InpRelaxFactor    = 0.1;        // Relaxation factor (points per minute)
input int      InpMaxRelaxation  = 200;        // Maximum relaxation in points

// Global variables
double g_point;
int g_digits;
int g_atrHandle;
int g_tradesOpenedToday = 0;
datetime g_lastTradingDay = 0;
datetime g_lastTradeTime = 0;
int g_startTimeSeconds = 0;
int g_endTimeSeconds = 0;
bool g_tradingAllowed = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Initialize ATR indicator
   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE) {
      Print("Error creating ATR indicator");
      return INIT_FAILED;
   }
   
   // Parse start and end times
   string startTimeParts[], endTimeParts[];
   StringSplit(StartTime, ':', startTimeParts);
   StringSplit(EndTime, ':', endTimeParts);
   
   if(ArraySize(startTimeParts) < 2 || ArraySize(endTimeParts) < 2) {
      Print("Invalid time format. Use HH:MM format.");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   g_startTimeSeconds = (int)StringToInteger(startTimeParts[0]) * 3600 + 
                       (int)StringToInteger(startTimeParts[1]) * 60;
   g_endTimeSeconds = (int)StringToInteger(endTimeParts[0]) * 3600 + 
                     (int)StringToInteger(endTimeParts[1]) * 60;
   
   // Initialize random seed differently for backtest vs. live trading
   if(MQLInfoInteger(MQL_TESTER)) {
      // Backtest-friendly random seed
      MathSrand((int)TimeCurrent() + (int)(SymbolInfoDouble(_Symbol, SYMBOL_BID)*1000));
   } else {
      // Live trading seed
      MathSrand(GetTickCount());
   }
   
   Print("Random Entry with Time-Based Trailing EA initialized");
   Print("Trading Hours: ", StartTime, " - ", EndTime);
   Print("Daily Trades Limit: ", DailyTrades);
   Print("ATR Period: ", InpATRPeriod, " | ATR Multiplier: ", InpATRMultiplier);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE) {
      IndicatorRelease(g_atrHandle);
   }
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if it's a new trading day
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   datetime currentDay = StringToTime(StringFormat("%04d.%02d.%02d", 
                                      timeStruct.year, timeStruct.mon, timeStruct.day));
   
   if(currentDay != g_lastTradingDay) {
      g_lastTradingDay = currentDay;
      g_tradesOpenedToday = 0;
      Print("New trading day started. Trades counter reset.");
   }
   
   // Calculate current time in seconds
   int currentTimeSeconds = timeStruct.hour * 3600 + timeStruct.min * 60 + timeStruct.sec;
   
   // Check if we're in trading hours
   g_tradingAllowed = (currentTimeSeconds >= g_startTimeSeconds && 
                      currentTimeSeconds <= g_endTimeSeconds);   // Update trailing stops with time-based relaxation
   ManageTrailingStops();
   
   // Attempt random entry if in trading hours and haven't exceeded daily trade limit
   if(g_tradingAllowed && g_tradesOpenedToday < DailyTrades) {
      AttemptRandomEntry();
   }
}

//+------------------------------------------------------------------+
//| Attempt to enter a random position                               |
//+------------------------------------------------------------------+
void AttemptRandomEntry()
{
   // Check if we already have an open position
   if(CountOurOpenPositions() > 0) return;
   
   // Calculate probability to distribute trades across trading session
   int tradingSessionLength = g_endTimeSeconds - g_startTimeSeconds;
   if(tradingSessionLength <= 0) return;
   
   double tradeFrequency = DailyTrades / (double)tradingSessionLength;
   double entryProb = tradeFrequency * 10; // Scaling factor for tick-based probability
   
   // Random entry with calculated probability
   if(MathRand() < entryProb * 32767) {
      // Don't open multiple trades at once (minimum 60 seconds between trades)
      if(TimeCurrent() - g_lastTradeTime < 60) return;
      
      // Random direction (buy or sell)
      bool buy = (MathRand() % 2 == 0);
      
      // Get current price
      double price = buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // Get ATR value for stop loss calculation
      double atrBuffer[];
      ArraySetAsSeries(atrBuffer, true);
      
      if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuffer) <= 0) {
         Print("Error getting ATR data");
         return;
      }
      
      double atrValue = atrBuffer[0];
      double stopDistance = atrValue * InpATRMultiplier;
      
      // Calculate stop loss price
      double stopLoss = buy ? price - stopDistance : price + stopDistance;
      
      // Execute trade
      if(OpenPosition(buy, PositionSize, stopLoss, atrValue)) {
         g_tradesOpenedToday++;
         g_lastTradeTime = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| Open a position                                                  |
//+------------------------------------------------------------------+
bool OpenPosition(bool buy, double lots, double stopLoss, double atrValue)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = stopLoss;
   request.tp = 0; // No take profit, we'll use trailing stop
   request.deviation = 10;
   request.comment = StringFormat("Random-%s-ATR:%.1f", buy ? "BUY" : "SELL", atrValue/g_point);
   request.type_filling = ORDER_FILLING_FOK;
   
   bool success = OrderSend(request, result);
   
   if(!success) {
      Print("Error opening position: ", GetLastError());
      return false;
   }
   
   Print("Position opened: ", buy ? "BUY" : "SELL", " at ", DoubleToString(request.price, g_digits), 
         " | SL: ", DoubleToString(stopLoss, g_digits), " | ATR: ", DoubleToString(atrValue/g_point, 1), " points");
     return true;
}

//+------------------------------------------------------------------+
//| Count our open positions                                         |
//+------------------------------------------------------------------+
int CountOurOpenPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(!PositionSelectByTicket(ticket)) continue;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      string comment = PositionGetString(POSITION_COMMENT);
      
      if(symbol == _Symbol && StringFind(comment, "Random-") == 0) {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Manage trailing stops with time-based relaxation                 |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(!PositionSelectByTicket(ticket)) continue;
      
      // Get position details
      string symbol = PositionGetString(POSITION_SYMBOL);
      if(symbol != _Symbol) continue;
      
      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "Random-") != 0) continue; // Only manage our trades
      
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentStop = PositionGetDouble(POSITION_SL);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      
      // Calculate minutes in trade
      int minutesInTrade = (int)((TimeCurrent() - openTime) / 60);
      
      // Calculate trailing stop with relaxation based on time
      double relaxation = MathMin(minutesInTrade * InpRelaxFactor, InpMaxRelaxation) * g_point;
      double trailDistance = InpTrailStart * g_point + relaxation;
      
      // Calculate new stop loss level
      double newStop;
      if(isBuy) {
         newStop = currentPrice - trailDistance;
         // Only move stop if it's in profit and higher than current stop
         if(currentPrice > openPrice + InpTrailStart * g_point && newStop > currentStop) {
            ModifyPositionStopLoss(ticket, newStop);
         }
      } else {
         newStop = currentPrice + trailDistance;
         // Only move stop if it's in profit and lower than current stop
         if(currentPrice < openPrice - InpTrailStart * g_point && (newStop < currentStop || currentStop == 0)) {
            ModifyPositionStopLoss(ticket, newStop);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify position stop loss                                        |
//+------------------------------------------------------------------+
bool ModifyPositionStopLoss(ulong ticket, double newStopLoss)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.sl = newStopLoss;
     bool success = OrderSend(request, result);
   
   if(!success) {
      Print("Error modifying stop loss for ticket ", ticket, ": ", GetLastError());
      return false;
   }
   
   // Log successful stop loss modification
   if(!PositionSelectByTicket(ticket)) return true;
   
   Print("Stop loss updated for ticket ", ticket, " | New SL: ", DoubleToString(newStopLoss, g_digits), 
         " | Type: ", (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL"),
         " | P&L: ", DoubleToString(PositionGetDouble(POSITION_PROFIT), 2));
   
   return true;
}

