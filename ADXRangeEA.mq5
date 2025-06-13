//+------------------------------------------------------------------+
//|                                                   ADXRangeEA.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

// Trade direction enumeration
enum ENUM_TRADE_DIRECTION
{
    TRADE_RANDOM = 0,    // Random direction (50/50)
    TRADE_BUY_ONLY = 1,  // Buy only
    TRADE_SELL_ONLY = 2  // Sell only
};

// Trading mode enumeration
enum ENUM_TRADING_MODE
{
    MODE_SCHEDULED = 0,  // Pre-decided random times
    MODE_INTERVAL = 1    // Check market every X minutes
};

//--- Input parameters
input string    StartTime = "06:00";           // Daily trading start time (HH:MM)
input string    EndTime = "18:00";             // Daily trading end time (HH:MM)
input ENUM_TRADING_MODE TradingMode = MODE_SCHEDULED; // Trading mode
input int       DailyTrades = 6;              // Number of trades per day (for scheduled mode)
input int       CheckInterval = 15;           // Check market every X minutes (for interval mode)
input double    PositionSize = 0.01;           // Fixed lot size
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_RANDOM; // Trade direction mode
input int       ADXPeriod = 15;               // ADX period
input double    ADXThreshold = 25.0;          // ADX threshold for ranging market (trade only when ADX < this value)
input int       StopLossPoints = 150;           // Stop loss in points (0 = no stop loss)
input int       TakeProfitPoints = 24;         // Take profit in points (0 = no take profit)

//--- Global variables
CTrade trade;
datetime tradingTimes[];                       // Array to store randomized trading times
int currentTradeIndex = 0;                     // Index of next trade to execute
datetime lastTradeDate = 0;                   // Last date when trades were generated
datetime lastCheckTime = 0;                    // Last time market was checked (for interval mode)
int startHour, startMinute, endHour, endMinute;
int adxHandle;                                 // ADX indicator handle

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
    
    if(CheckInterval <= 0 || CheckInterval > 1440)
    {
        Print("Error: Check interval must be between 1 and 1440 minutes");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if(PositionSize <= 0)
    {
        Print("Error: Position size must be greater than 0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if(ADXPeriod <= 0)
    {
        Print("Error: ADX period must be greater than 0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if(ADXThreshold <= 0)
    {
        Print("Error: ADX threshold must be greater than 0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if(StopLossPoints < 0 || TakeProfitPoints < 0)
    {
        Print("Error: Stop loss and take profit points cannot be negative");
        return INIT_PARAMETERS_INCORRECT;
    }

    // Initialize ADX indicator
    adxHandle = iADX(Symbol(), PERIOD_CURRENT, ADXPeriod);
    if(adxHandle == INVALID_HANDLE)
    {
        Print("Error: Failed to create ADX indicator handle");
        return INIT_FAILED;
    }

    // Initialize random seed with conditional approach
    if(MQLInfoInteger(MQL_TESTER)) {
        // Backtest-friendly random seed
        MathSrand((int)TimeCurrent() + (int)(SymbolInfoDouble(_Symbol, SYMBOL_BID)*1000));
    } else {
        // Live trading seed
        MathSrand(GetTickCount());
    }
    
    // Resize the trading times array
    ArrayResize(tradingTimes, DailyTrades);
      Print("ADXRangeEA initialized successfully");
    Print("Trading hours: ", StartTime, " - ", EndTime);
    Print("Trading mode: ", (TradingMode == MODE_SCHEDULED ? "Scheduled" : "Interval"));
    if(TradingMode == MODE_SCHEDULED)
        Print("Daily trades: ", DailyTrades);
    else
        Print("Check interval: ", CheckInterval, " minutes");
    Print("Position size: ", PositionSize, " lots");
    Print("Trade direction: ", (TradeDirection == TRADE_RANDOM ? "Random" : 
                                TradeDirection == TRADE_BUY_ONLY ? "Buy Only" : "Sell Only"));
    Print("ADX period: ", ADXPeriod, " | ADX threshold: ", ADXThreshold);
    Print("Stop loss: ", (StopLossPoints > 0 ? IntegerToString(StopLossPoints) + " points" : "Disabled"));
    Print("Take profit: ", (TakeProfitPoints > 0 ? IntegerToString(TakeProfitPoints) + " points" : "Disabled"));
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release ADX indicator handle
    if(adxHandle != INVALID_HANDLE)
        IndicatorRelease(adxHandle);
        
    Print("ADXRangeEA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(TradingMode == MODE_SCHEDULED)
    {
        // Check if we need to generate new trading times for today
        GenerateDailyTradingTimes();
        
        // Check if it's time to execute a trade
        CheckAndExecuteTrade();
    }
    else
    {
        // Check market at regular intervals
        CheckMarketAtInterval();
    }
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
                    if(MathAbs(usedTimes[j] - randomMinute) < 15) // 15 minute minimum gap
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
//| Check market at regular intervals                               |
//+------------------------------------------------------------------+
void CheckMarketAtInterval()
{
    datetime currentTime = TimeCurrent();
    
    // Check if we're within trading hours
    if(!IsWithinTradingHours())
        return;
    
    // Check if enough time has passed since last check
    if(currentTime - lastCheckTime < CheckInterval * 60)
        return;
    
    lastCheckTime = currentTime;
    
    // Check ADX condition
    if(!IsRangingMarket())
    {
        Print("Market check - Market is trending (ADX >= ", ADXThreshold, ") at: ", TimeToString(currentTime));
        return;
    }
    
    // Take a new position if ranging market conditions are met
    TakeNewPosition();
}

//+------------------------------------------------------------------+
//| Check if it's time to execute a trade or close positions        |
//+------------------------------------------------------------------+
void CheckAndExecuteTrade()
{
    datetime currentTime = TimeCurrent();
    
    // Check if we're within trading hours for any action
    if(!IsWithinTradingHours())
        return;
    
    // Check if we have more trades to execute today
    if(currentTradeIndex >= DailyTrades)
        return; // All trades for today executed
    
    // Check if it's time for the next scheduled trade
    if(currentTime >= tradingTimes[currentTradeIndex])
    {
        // Check ADX condition first
        if(!IsRangingMarket())
        {
            Print("Skipping trade - Market is trending (ADX >= ", ADXThreshold, ") at: ", TimeToString(currentTime));
            currentTradeIndex++;
            return;
        }
        
        TakeNewPosition();
        currentTradeIndex++;
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
//| Check if market is ranging (ADX < threshold)                    |
//+------------------------------------------------------------------+
bool IsRangingMarket()
{
    double adxValue[1];
    
    // Copy ADX value
    if(CopyBuffer(adxHandle, 0, 0, 1, adxValue) <= 0)
    {
        Print("Error: Failed to get ADX value: ", GetLastError());
        return false; // Skip trade if can't get ADX
    }
    
    bool isRanging = adxValue[0] < ADXThreshold;
    
    Print("ADX Check: ", DoubleToString(adxValue[0], 2), 
          " | Threshold: ", DoubleToString(ADXThreshold, 2),
          " | Market condition: ", (isRanging ? "RANGING" : "TRENDING"));
    
    return isRanging;
}

//+------------------------------------------------------------------+
//| Calculate stop loss and take profit prices                      |
//+------------------------------------------------------------------+
void CalculateStopLossTakeProfit(bool isBuy, double openPrice, double &stopLoss, double &takeProfit)
{
    double pointValue = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    
    // Initialize to 0 (no SL/TP)
    stopLoss = 0;
    takeProfit = 0;
    
    if(StopLossPoints > 0)
    {
        if(isBuy)
            stopLoss = openPrice - (StopLossPoints * pointValue);
        else
            stopLoss = openPrice + (StopLossPoints * pointValue);
    }
    
    if(TakeProfitPoints > 0)
    {
        if(isBuy)
            takeProfit = openPrice + (TakeProfitPoints * pointValue);
        else
            takeProfit = openPrice - (TakeProfitPoints * pointValue);
    }
}

//+------------------------------------------------------------------+
//| Take new random direction position                               |
//+------------------------------------------------------------------+
void TakeNewPosition()
{
    bool isBuy = DetermineTradeDirection();
    
    double price = isBuy ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : 
                          SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    // Calculate stop loss and take profit
    double stopLoss, takeProfit;
    CalculateStopLossTakeProfit(isBuy, price, stopLoss, takeProfit);
    
    ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    
    if(trade.PositionOpen(Symbol(), orderType, PositionSize, price, stopLoss, takeProfit, 
                         "ADXRange_" + TimeToString(TimeCurrent())))
    {
        Print("New ", (isBuy ? "BUY" : "SELL"), " position opened: ",
              "Size: ", PositionSize, ", Price: ", DoubleToString(price, Digits()),
              ", SL: ", (stopLoss > 0 ? DoubleToString(stopLoss, Digits()) : "None"),
              ", TP: ", (takeProfit > 0 ? DoubleToString(takeProfit, Digits()) : "None"),
              " (Trade ", currentTradeIndex, " of ", DailyTrades, ")");
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
