//+------------------------------------------------------------------+
//|                                                RandomTimerEA.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

// Stop loss mode enumeration
enum ENUM_STOPLOSS_MODE
{
    SL_DYNAMIC = 0,      // Dynamic stop loss based on range
    SL_FIXED = 1         // Fixed stop loss in points
};

// Trade direction enumeration
enum ENUM_TRADE_DIRECTION
{
    TRADE_RANDOM = 0,    // Random direction (50/50)
    TRADE_BUY_ONLY = 1,  // Buy only
    TRADE_SELL_ONLY = 2  // Sell only
};

//--- Input parameters
input string    StartTime = "06:00";           // Daily trading start time (HH:MM)
input string    EndTime = "18:00";             // Daily trading end time (HH:MM)
input int       DailyTrades = 3;              // Number of trades per day
input double    PositionSize = 0.01;          // Fixed lot size
input ENUM_STOPLOSS_MODE StopLossMode = SL_DYNAMIC; // Stop loss calculation mode
input int       FixedStopLossPoints = 20;     // Fixed stop loss in points (used when mode is Fixed)
input int       RangePeriodMinutes = 24;      // Period in minutes to calculate range (for dynamic SL)
input double    RangeMultiplier = 1.5;        // Multiplier for range-based stop loss (for dynamic SL)
input int       TakeProfitPoints = 24;        // Take profit in points
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_RANDOM; // Trade direction mode

//--- Global variables
CTrade trade;
datetime tradingTimes[];                       // Array to store randomized trading times
int currentTradeIndex = 0;                     // Index of next trade to execute
datetime lastTradeDate = 0;                   // Last date when trades were generated
int startHour, startMinute, endHour, endMinute;

//+------------------------------------------------------------------+
//| Send push notification                                           |
//+------------------------------------------------------------------+
bool SendPushAlert(string message)
{
    if(!SendNotification(message))
    {
        Print("Error sending push notification: ", GetLastError());
        return false;
    }
    
    Print("Push notification sent successfully");
    return true;
}

//+------------------------------------------------------------------+
//| Send formatted trade notification                                |
//+------------------------------------------------------------------+
void SendTradeNotification(string direction, double lots, double price, double sl, double tp)
{
    string message = Symbol() + ": New " + direction + " @ " +
                    DoubleToString(price, Digits()) + " | " +
                    DoubleToString(lots, 2) + " lots | " +
                    "SL: " + DoubleToString(sl, Digits()) + " | " +
                    "TP: " + DoubleToString(tp, Digits());
    
    SendPushAlert(message);
}

//+------------------------------------------------------------------+
//| Send formatted trade notification with dynamic SL info          |
//+------------------------------------------------------------------+
void SendTradeNotificationWithRange(string direction, double lots, double price, double sl, double tp, double range)
{
    string message = Symbol() + ": New " + direction + " @ " +
                    DoubleToString(price, Digits()) + " | " +
                    DoubleToString(lots, 2) + " lots | " +
                    "SL: " + DoubleToString(sl, Digits()) + " | " +
                    "TP: " + DoubleToString(tp, Digits()) + " | " +
                    "Range: " + DoubleToString(range, Digits());
    
    SendPushAlert(message);
}

//+------------------------------------------------------------------+
//| Send formatted trade notification with stop loss mode info     |
//+------------------------------------------------------------------+
void SendTradeNotificationWithSL(string direction, double lots, double price, double sl, double tp, string slMode, double slDistance)
{
    string message = Symbol() + ": New " + direction + " @ " +
                    DoubleToString(price, Digits()) + " | " +
                    DoubleToString(lots, 2) + " lots | " +
                    "SL: " + DoubleToString(sl, Digits()) + " (" + slMode + ") | " +
                    "TP: " + DoubleToString(tp, Digits()) + " | " +
                    "Distance: " + DoubleToString(slDistance, Digits());
    
    SendPushAlert(message);
}

//+------------------------------------------------------------------+
//| Send daily schedule notification                                 |
//+------------------------------------------------------------------+
void SendScheduleNotification(int trades, datetime date)
{
    string message = Symbol() + ": " + IntegerToString(trades) + 
                    " trades scheduled for " + TimeToString(date, TIME_DATE);
    
    SendPushAlert(message);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Parse start and end times
    if(!ParseTimeString(StartTime, startHour, startMinute) || 
       !ParseTimeString(EndTime, endHour, endMinute))
    {
        Print("Error: Invalid time format. Use HH:MM format.");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // Validate inputs
    if(DailyTrades <= 0 || DailyTrades > 100)
    {
        Print("Error: Daily trades must be between 1 and 100");
        return INIT_PARAMETERS_INCORRECT;
    }
      if(PositionSize <= 0)
    {
        Print("Error: Position size must be greater than 0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if(RangePeriodMinutes <= 0)
    {
        Print("Error: Range period minutes must be greater than 0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if(RangeMultiplier <= 0)
    {
        Print("Error: Range multiplier must be greater than 0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if(TakeProfitPoints <= 0)
    {
        Print("Error: Take profit points must be greater than 0");
        return INIT_PARAMETERS_INCORRECT;
    }

    // Initialize random seed
    if(MQLInfoInteger(MQL_TESTER)) {
        // Backtest-friendly random seed
        MathSrand((int)TimeCurrent() + (int)(SymbolInfoDouble(_Symbol, SYMBOL_BID)*1000));
    } else {
        // Live trading seed
        MathSrand(GetTickCount());
    }
    
    // Resize the trading times array
    ArrayResize(tradingTimes, DailyTrades);    Print("RandomTimerEA initialized successfully");
    Print("Trading hours: ", StartTime, " - ", EndTime);
    Print("Daily trades: ", DailyTrades);
    Print("Position size: ", PositionSize, " lots");
    Print("Range period: ", RangePeriodMinutes, " minutes");
    Print("Range multiplier: ", RangeMultiplier);
    Print("Take Profit: ", TakeProfitPoints, " points");
    Print("Trade direction: ", (TradeDirection == TRADE_RANDOM ? "Random" : 
                                TradeDirection == TRADE_BUY_ONLY ? "Buy Only" : "Sell Only"));
    
    // Send initialization notification
    string directionText = (TradeDirection == TRADE_RANDOM ? "Random" : 
                           TradeDirection == TRADE_BUY_ONLY ? "BuyOnly" : "SellOnly");
    string initMessage = Symbol() + " RandomTimerEA initialized | " +
                        "Hours: " + StartTime + "-" + EndTime + " | " +
                        IntegerToString(DailyTrades) + " trades/day | " +
                        DoubleToString(PositionSize, 2) + " lots | " +
                        "Range: " + IntegerToString(RangePeriodMinutes) + "min x" + 
                        DoubleToString(RangeMultiplier, 1) + " | " +
                        "Direction: " + directionText;
    SendPushAlert(initMessage);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("RandomTimerEA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if we need to generate new trading times for today
    GenerateDailyTradingTimes();
    
    // Check if it's time to execute a trade
    CheckAndExecuteTrade();
}

//+------------------------------------------------------------------+
//| Generate random trading times for the current day               |
//+------------------------------------------------------------------+
void GenerateDailyTradingTimes()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Create date without time
    datetime currentDate = StringToTime(IntegerToString(dt.year) + "." + 
                                       IntegerToString(dt.mon) + "." + 
                                       IntegerToString(dt.day) + " 00:00");
    
    // Check if we need to generate new times for today
    if(currentDate != lastTradeDate)
    {
        lastTradeDate = currentDate;
        currentTradeIndex = 0;
        
        // Calculate trading window in minutes
        int startMinutes = startHour * 60 + startMinute;
        int endMinutes = endHour * 60 + endMinute;
        
        // Handle overnight sessions
        int tradingWindowMinutes;
        if(startMinutes > endMinutes)
        {
            tradingWindowMinutes = (24 * 60 - startMinutes) + endMinutes;
        }
        else
        {
            tradingWindowMinutes = endMinutes - startMinutes;
        }
        
        // Generate random times within the trading window
        int usedTimes[];
        ArrayResize(usedTimes, DailyTrades);
          for(int i = 0; i < DailyTrades; i++)
        {
            int randomMinute = 0;  // Initialize the variable
            bool isUnique = false;
            
            // Ensure unique times
            while(!isUnique)
            {
                randomMinute = MathRand() % tradingWindowMinutes;
                isUnique = true;
                
                // Check if this minute is already used
                for(int j = 0; j < i; j++)
                {
                    if(MathAbs(usedTimes[j] - randomMinute) < 6) // 6 minute minimum gap
                    {
                        isUnique = false;
                        break;
                    }
                }
            }
            
            usedTimes[i] = randomMinute;
            
            // Convert to actual time
            int actualMinutes = startMinutes + randomMinute;
            
            // Handle day overflow for overnight sessions
            datetime tradeDate = currentDate;
            if(actualMinutes >= 24 * 60)
            {
                actualMinutes -= 24 * 60;
                tradeDate += 24 * 3600; // Add one day
            }
            
            int tradeHour = actualMinutes / 60;
            int tradeMinute = actualMinutes % 60;
            
            tradingTimes[i] = tradeDate + tradeHour * 3600 + tradeMinute * 60;
        }
        
        // Sort the trading times
        ArraySort(tradingTimes);
          Print("Generated ", DailyTrades, " random trading times for ", TimeToString(currentDate, TIME_DATE));
        for(int i = 0; i < DailyTrades; i++)
        {
            Print("Trade ", i+1, " scheduled at: ", TimeToString(tradingTimes[i], TIME_MINUTES));
        }
        
        // Send schedule notification
        SendScheduleNotification(DailyTrades, currentDate);
    }
}

//+------------------------------------------------------------------+
//| Check if it's time to execute a trade                           |
//+------------------------------------------------------------------+
void CheckAndExecuteTrade()
{
    if(currentTradeIndex >= DailyTrades)
        return; // All trades for today executed
    
    datetime currentTime = TimeCurrent();
    
    // Check if it's time for the next trade
    if(currentTime >= tradingTimes[currentTradeIndex])
    {
        // Check if we're within trading hours (additional safety check)
        if(IsWithinTradingHours())
        {
            TakeNewPosition();
            currentTradeIndex++;
        }        else
        {
            // Skip this trade if outside trading hours and move to next
            Print("Skipping trade outside trading hours at: ", TimeToString(currentTime));
            
            // Send skip notification
            string skipMessage = Symbol() + ": Trade skipped (outside hours) at " + 
                               TimeToString(currentTime, TIME_MINUTES);
            SendPushAlert(skipMessage);
            
            currentTradeIndex++;
        }
    }
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                   |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    int currentMinutes = dt.hour * 60 + dt.min;
    int startMinutes = startHour * 60 + startMinute;
    int endMinutes = endHour * 60 + endMinute;
    
    // Handle overnight sessions
    if(startMinutes > endMinutes)
    {
        return (currentMinutes >= startMinutes || currentMinutes <= endMinutes);
    }
    else
    {
        return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
    }
}

//+------------------------------------------------------------------+
//| Take new position with configurable direction                   |
//+------------------------------------------------------------------+
void TakeNewPosition()
{
    bool isBuy = DetermineTradeDirection();
    
    double price = isBuy ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : 
                          SymbolInfoDouble(Symbol(), SYMBOL_BID);
    ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    
    // Calculate dynamic stop loss based on recent range
    double stopLoss = CalculateStopLoss(isBuy, price);
    
    // Calculate TP prices using points
    double pointValue = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double takeProfit = 0;
    
    if(isBuy)
    {
        takeProfit = price + (TakeProfitPoints * pointValue);
    }
    else
    {
        takeProfit = price - (TakeProfitPoints * pointValue);
    }
      // Normalize prices
    takeProfit = NormalizeDouble(takeProfit, Digits());
    
    // Calculate information for notification based on stop loss mode
    double slDistance = MathAbs(price - stopLoss);
    string slModeStr = (StopLossMode == SL_FIXED) ? "Fixed" : "Dynamic";
    
    if(trade.PositionOpen(Symbol(), orderType, PositionSize, price, stopLoss, takeProfit, 
                         "RandomTimer_" + TimeToString(TimeCurrent())))
    {
        Print("New ", (isBuy ? "BUY" : "SELL"), " position opened: ",
              "Size: ", PositionSize, 
              ", Price: ", DoubleToString(price, Digits()),
              ", SL: ", DoubleToString(stopLoss, Digits()),
              ", TP: ", DoubleToString(takeProfit, Digits()),
              ", SL Mode: ", slModeStr,
              ", SL Distance: ", DoubleToString(slDistance, Digits()));
              
        // Send trade notification with stop loss info
        SendTradeNotificationWithSL((isBuy ? "BUY" : "SELL"), PositionSize, price, stopLoss, takeProfit, slModeStr, slDistance);
    }
    else
    {
        Print("Failed to open position. Error: ", trade.ResultRetcode());
        
        // Send error notification
        string errorMessage = Symbol() + ": Failed to open position. Error: " + 
                             IntegerToString(trade.ResultRetcode());
        SendPushAlert(errorMessage);
    }
}

//+------------------------------------------------------------------+
//| Calculate stop loss based on selected mode                      |
//+------------------------------------------------------------------+
double CalculateStopLoss(bool isBuy, double entryPrice)
{
    if(StopLossMode == SL_FIXED)
    {
        double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
        double stopDistance = FixedStopLossPoints * point;
        
        // Adjust for 5-digit brokers
        if(SymbolInfoInteger(Symbol(), SYMBOL_DIGITS) == 5 || 
           SymbolInfoInteger(Symbol(), SYMBOL_DIGITS) == 3)
            stopDistance *= 10;
            
        double stopLoss;
        if(isBuy)
            stopLoss = entryPrice - stopDistance;
        else
            stopLoss = entryPrice + stopDistance;
            
        Print("Fixed Stop Loss - Entry: ", DoubleToString(entryPrice, Digits()),
              ", Direction: ", (isBuy ? "BUY" : "SELL"),
              ", Points: ", FixedStopLossPoints,
              ", Stop Loss: ", DoubleToString(stopLoss, Digits()));
              
        return NormalizeDouble(stopLoss, Digits());
    }
    else
    {
        return CalculateDynamicStopLoss(isBuy, entryPrice);
    }
}

//+------------------------------------------------------------------+
//| Calculate dynamic stop loss based on recent price range         |
//+------------------------------------------------------------------+
double CalculateDynamicStopLoss(bool isBuy, double entryPrice)
{
    // Get M1 data for the last X minutes
    MqlRates rates[];
    int copied = CopyRates(Symbol(), PERIOD_M1, 0, RangePeriodMinutes, rates);
    
    if(copied < RangePeriodMinutes)
    {
        Print("Warning: Not enough historical data for range calculation. Using minimum range.");
        // Fallback to a minimum range if not enough data
        double minRange = 20 * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
        if(SymbolInfoInteger(Symbol(), SYMBOL_DIGITS) == 5 || 
           SymbolInfoInteger(Symbol(), SYMBOL_DIGITS) == 3)
            minRange *= 10; // Adjust for 5-digit brokers
        
        return isBuy ? entryPrice - (minRange * RangeMultiplier) : 
                      entryPrice + (minRange * RangeMultiplier);
    }
    
    // Find the highest high and lowest low in the period
    double highestHigh = rates[0].high;
    double lowestLow = rates[0].low;
    
    for(int i = 1; i < copied; i++)
    {
        if(rates[i].high > highestHigh)
            highestHigh = rates[i].high;
        if(rates[i].low < lowestLow)
            lowestLow = rates[i].low;
    }
      // Calculate the range
    double range = highestHigh - lowestLow;
    
    // Apply multiplier to the range
    double stopDistance = range * RangeMultiplier;
    
    // Print range and stop distance information
    Print("Dynamic Range calculation - Period: ", RangePeriodMinutes, " minutes, ",
          "High: ", DoubleToString(highestHigh, Digits()), 
          ", Low: ", DoubleToString(lowestLow, Digits()),
          ", Range: ", DoubleToString(range, Digits()),
          ", Multiplier: ", RangeMultiplier,
          ", Stop Distance: ", DoubleToString(stopDistance, Digits()));
    
    // Calculate stop loss price
    double stopLoss;
    if(isBuy)
        stopLoss = entryPrice - stopDistance;
    else
        stopLoss = entryPrice + stopDistance;
    
    Print("Dynamic Stop Loss calculated - Entry: ", DoubleToString(entryPrice, Digits()),
          ", Direction: ", (isBuy ? "BUY" : "SELL"),
          ", Stop Loss: ", DoubleToString(stopLoss, Digits()));
    
    // Normalize and return
    return NormalizeDouble(stopLoss, Digits());
}

//+------------------------------------------------------------------+
//| Parse time string in HH:MM format                               |
//+------------------------------------------------------------------+
bool ParseTimeString(string timeStr, int &hour, int &minute)
{
    string parts[];
    if(StringSplit(timeStr, ':', parts) != 2)
        return false;
    
    hour = (int)StringToInteger(parts[0]);
    minute = (int)StringToInteger(parts[1]);
    
    if(hour < 0 || hour > 23 || minute < 0 || minute > 59)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Determine trade direction based on input mode                   |
//+------------------------------------------------------------------+
bool DetermineTradeDirection()
{
    switch(TradeDirection)
    {
        case TRADE_RANDOM:
            return (MathRand() % 2 == 0); // Random 50/50
            
        case TRADE_BUY_ONLY:
            return true; // Always buy
            
        case TRADE_SELL_ONLY:
            return false; // Always sell
            
        default:
            Print("Warning: Invalid trade direction mode, defaulting to random");
            return (MathRand() % 2 == 0);
    }
}
