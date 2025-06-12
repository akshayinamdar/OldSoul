//+------------------------------------------------------------------+
//|                                           RandomDirectionEA.mq5 |
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

//--- Input parameters
input string    StartTime = "06:00";           // Daily trading start time (HH:MM)
input string    EndTime = "18:00";             // Daily trading end time (HH:MM)
input int       DailyTrades = 3;              // Number of trades per day
input double    PositionSize = 0.01;            // Fixed lot size
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_RANDOM; // Trade direction mode
input bool      ExitMode = true;               // Exit mode (true = exit on profit, false = exit on loss)
input int       MinProfitLossPips = 6;        // Minimum profit/loss pips threshold

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
    
    if(MinProfitLossPips <= 0)
    {
        Print("Error: Minimum profit/loss pips must be greater than 0");
        return INIT_PARAMETERS_INCORRECT;
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
      Print("RandomDirectionEA initialized successfully");
    Print("Trading hours: ", StartTime, " - ", EndTime);
    Print("Daily trades: ", DailyTrades);
    Print("Position size: ", PositionSize, " lots");
    Print("Trade direction: ", (TradeDirection == TRADE_RANDOM ? "Random" : 
                                TradeDirection == TRADE_BUY_ONLY ? "Buy Only" : "Sell Only"));
    Print("Exit mode: ", (ExitMode ? "Exit on Profit" : "Exit on Loss"));
    Print("Min profit/loss pips: ", MinProfitLossPips);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("RandomDirectionEA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if we need to generate new trading times for today
    GenerateDailyTradingTimes();
    
    // Check if it's time to execute a trade (includes position closing checks)
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
                    if(MathAbs(usedTimes[j] - randomMinute) < 10) // 10 minute minimum gap
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
//| Check if it's time to execute a trade or close positions        |
//+------------------------------------------------------------------+
void CheckAndExecuteTrade()
{
    datetime currentTime = TimeCurrent();
    
    // Check if we're within trading hours for any action
    if(!IsWithinTradingHours())
        return;
    
    // Process existing positions first (check for closing at any scheduled time)
    ProcessExistingPositions();
    
    // Check if we have more trades to execute today
    if(currentTradeIndex >= DailyTrades)
        return; // All trades for today executed    // Check if it's time for the next scheduled trade
    if(currentTime >= tradingTimes[currentTradeIndex])
    {        // Check if we can take a new position based on existing position criteria
        bool canTakeNewPosition = true;
        
        // Find the most recent position (last executed trade)
        datetime lastPositionTime = 0;
        ulong lastPositionTicket = 0;
        
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionGetTicket(i))
            {
                if(PositionGetString(POSITION_SYMBOL) == Symbol())
                {
                    datetime positionTime = (datetime)PositionGetInteger(POSITION_TIME);
                    if(positionTime > lastPositionTime)
                    {
                        lastPositionTime = positionTime;
                        lastPositionTicket = PositionGetTicket(i);
                    }
                }
            }
        }
        
        // Check only the last position if it exists
        if(lastPositionTicket > 0)
        {
            if(PositionSelectByTicket(lastPositionTicket))
            {
                // Check if last position's absolute profit pips is less than threshold
                double profitPips = GetProfitInPips();
                if(MathAbs(profitPips) < MinProfitLossPips)
                {
                    canTakeNewPosition = false;
                    Print("Skipping trade - last position profit (", 
                          DoubleToString(profitPips, 1), " pips) below threshold of ", 
                          MinProfitLossPips, " pips at: ", TimeToString(currentTime),
                          " | Last position opened at: ", TimeToString(lastPositionTime));
                }
            }
        }
        
        if(canTakeNewPosition)
        {
            TakeNewPosition();
        }
        
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
//| Process existing positions and close if criteria met at scheduled times |
//+------------------------------------------------------------------+
void ProcessExistingPositions()
{
    datetime currentTime = TimeCurrent();
    bool isScheduledTime = false;
    
    // Check if current time matches any of the scheduled trading times
    for(int t = 0; t < DailyTrades; t++)
    {
        // Allow a 1-minute window around each scheduled time for position evaluation
        if(MathAbs(currentTime - tradingTimes[t]) <= 60)
        {
            isScheduledTime = true;
            break;
        }
    }
    
    // Only process position closing at scheduled times
    if(!isScheduledTime)
        return;
      // Check all positions for this symbol
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetTicket(i))
        {
            if(PositionGetString(POSITION_SYMBOL) == Symbol())
            {
                ulong positionTicket = PositionGetTicket(i);
                if(PositionSelectByTicket(positionTicket))
                {
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    double profitPips = GetProfitInPips();
                    
                    bool shouldClose = false;
                    
                    if(ExitMode) // Exit on profit
                    {
                        if(profit > 0 && profitPips >= MinProfitLossPips)
                            shouldClose = true;
                    }
                    else // Exit on loss
                    {
                        if(profit < 0 && MathAbs(profitPips) >= MinProfitLossPips)
                            shouldClose = true;
                    }
                    
                    if(shouldClose)
                    {
                        if(trade.PositionClose(positionTicket))
                        {
                            Print("Position closed at scheduled time: Ticket #", positionTicket, 
                                  ", Profit: ", DoubleToString(profit, 2), 
                                  ", Pips: ", DoubleToString(profitPips, 1),
                                  ", Time: ", TimeToString(currentTime, TIME_MINUTES));
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate profit in pips for currently selected position        |
//+------------------------------------------------------------------+
double GetProfitInPips()
{
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                         SymbolInfoDouble(Symbol(), SYMBOL_BID) : 
                         SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    
    double pipValue = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    if(SymbolInfoInteger(Symbol(), SYMBOL_DIGITS) == 5 || 
       SymbolInfoInteger(Symbol(), SYMBOL_DIGITS) == 3)
        pipValue *= 10;
    
    double pips = 0;
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        pips = (currentPrice - openPrice) / pipValue;
    else
        pips = (openPrice - currentPrice) / pipValue;
    return pips;
}

//+------------------------------------------------------------------+
//| Take new random direction position                               |
//+------------------------------------------------------------------+
void TakeNewPosition()
{
    bool isBuy = DetermineTradeDirection();
    
    double price = isBuy ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : 
                          SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(trade.PositionOpen(Symbol(), orderType, PositionSize, price, 0, 0, 
                         "RandomDirection_" + TimeToString(TimeCurrent())))
    {
        Print("New ", (isBuy ? "BUY" : "SELL"), " position opened: ",
              "Size: ", PositionSize, ", Price: ", DoubleToString(price, Digits()),
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
