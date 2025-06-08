//+------------------------------------------------------------------+
//|                                                RandomTimerEA.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input string    StartTime = "06:00";           // Daily trading start time (HH:MM)
input string    EndTime = "18:00";             // Daily trading end time (HH:MM)
input int       DailyTrades = 3;              // Number of trades per day
input double    PositionSize = 0.01;          // Fixed lot size
input int       StopLossPoints = 150;          // Stop loss in points
input int       TakeProfitPoints = 24;        // Take profit in points

//--- Global variables
CTrade trade;
datetime tradingTimes[];                       // Array to store randomized trading times
int currentTradeIndex = 0;                     // Index of next trade to execute
datetime lastTradeDate = 0;                   // Last date when trades were generated
int startHour, startMinute, endHour, endMinute;

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
      if(StopLossPoints <= 0)
    {
        Print("Error: Stop loss points must be greater than 0");
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
    ArrayResize(tradingTimes, DailyTrades);
      Print("RandomTimerEA initialized successfully");
    Print("Trading hours: ", StartTime, " - ", EndTime);
    Print("Daily trades: ", DailyTrades);
    Print("Position size: ", PositionSize, " lots");
    Print("Stop Loss: ", StopLossPoints, " points");
    Print("Take Profit: ", TakeProfitPoints, " points");
    
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
            int randomMinute;
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
        }
        else
        {
            // Skip this trade if outside trading hours and move to next
            Print("Skipping trade outside trading hours at: ", TimeToString(currentTime));
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
//| Take new random direction position                               |
//+------------------------------------------------------------------+
void TakeNewPosition()
{
    bool isBuy = (MathRand() % 2 == 0);
    
    double price = isBuy ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : 
                          SymbolInfoDouble(Symbol(), SYMBOL_BID);
      ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    
    // Calculate SL and TP prices using points
    double pointValue = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    
    double stopLoss = 0, takeProfit = 0;
    
    if(isBuy)
    {
        stopLoss = price - (StopLossPoints * pointValue);
        takeProfit = price + (TakeProfitPoints * pointValue);
    }
    else
    {
        stopLoss = price + (StopLossPoints * pointValue);
        takeProfit = price - (TakeProfitPoints * pointValue);
    }
    
    // Normalize prices
    stopLoss = NormalizeDouble(stopLoss, Digits());
    takeProfit = NormalizeDouble(takeProfit, Digits());
    
    if(trade.PositionOpen(Symbol(), orderType, PositionSize, price, stopLoss, takeProfit, 
                         "RandomTimer_" + TimeToString(TimeCurrent())))
    {
        Print("New ", (isBuy ? "BUY" : "SELL"), " position opened: ",
              "Size: ", PositionSize, 
              ", Price: ", DoubleToString(price, Digits()),
              ", SL: ", DoubleToString(stopLoss, Digits()),
              ", TP: ", DoubleToString(takeProfit, Digits()));
    }
    else
    {
        Print("Failed to open position. Error: ", trade.ResultRetcode());
    }
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
