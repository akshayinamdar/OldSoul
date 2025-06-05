//+------------------------------------------------------------------+
//|                                           RandomDirectionEA.mq5 |
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
input int       Interval = 15;                 // Market check frequency in minutes
input double    PositionSize = 0.01;            // Fixed lot size
input bool      ExitMode = true;               // Exit mode (true = exit on profit, false = exit on loss)
input int       MinProfitLossPips = 6;        // Minimum profit/loss pips threshold

//--- Global variables
CTrade trade;
datetime lastCheckTime = 0;
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
    if(Interval <= 0)
    {
        Print("Error: Interval must be greater than 0");
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
    
    
    Print("RandomDirectionEA initialized successfully");
    Print("Trading hours: ", StartTime, " - ", EndTime);
    Print("Interval: ", Interval, " minutes");
    Print("Position size: ", PositionSize, " lots");
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
    // Check if it's time for market analysis
    if(!IsTimeForCheck())
        return;
    
    // Check if we're within trading hours
    if(!IsWithinTradingHours())
        return;
    
    // Process existing positions
    bool canTakeNewPosition = ProcessExistingPositions();
    
    // Take new position if allowed
    if(canTakeNewPosition)
        TakeNewPosition();
    
    // Update last check time
    lastCheckTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Check if it's time for market analysis                          |
//+------------------------------------------------------------------+
bool IsTimeForCheck()
{
    datetime currentTime = TimeCurrent();
    
    // First run
    if(lastCheckTime == 0)
        return true;
    
    // Check if interval minutes have passed
    int timeDiff = (int)(currentTime - lastCheckTime) / 60;
    return (timeDiff >= Interval);
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
//| Process existing positions and return if new position allowed   |
//+------------------------------------------------------------------+
bool ProcessExistingPositions()
{
    bool canTakeNewPosition = true;
    
    // Check all positions for EURUSD
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetTicket(i))
        {
            if(PositionGetString(POSITION_SYMBOL) == Symbol())
            {
                double profit = PositionGetDouble(POSITION_PROFIT);
                double profitPips = GetProfitInPips();
                
                bool shouldClose = false;
                  if(ExitMode) // Exit on profit
                {
                    if(profit > 0 && profitPips >= MinProfitLossPips)
                        shouldClose = true;
                    else if(profit > 0 && profitPips < MinProfitLossPips)
                        canTakeNewPosition = false; // Skip new position
                }
                else // Exit on loss
                {
                    if(profit < 0 && MathAbs(profitPips) >= MinProfitLossPips)
                        shouldClose = true;
                    else if(profit < 0 && MathAbs(profitPips) < MinProfitLossPips)
                        canTakeNewPosition = false; // Skip new position
                }
                
                // Additional condition: prevent new positions when profit is negative and small
                if(profit < 0 && MathAbs(profitPips) < MinProfitLossPips)
                    canTakeNewPosition = false;
                
                if(shouldClose)
                {
                    ulong ticket = PositionGetTicket(i);
                    if(trade.PositionClose(ticket))
                    {
                        Print("Position closed: Ticket #", ticket, 
                              ", Profit: ", DoubleToString(profit, 2), 
                              ", Pips: ", DoubleToString(profitPips, 1));
                    }
                }
            }
        }
    }
    
    return canTakeNewPosition;
}

//+------------------------------------------------------------------+
//| Calculate profit in pips for current position                   |
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
    bool isBuy = (MathRand() % 2 == 0);
    
    double price = isBuy ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : 
                          SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    
    if(trade.PositionOpen(Symbol(), orderType, PositionSize, price, 0, 0, 
                         "RandomDirection_" + TimeToString(TimeCurrent())))
    {
        Print("New ", (isBuy ? "BUY" : "SELL"), " position opened: ",
              "Size: ", PositionSize, ", Price: ", DoubleToString(price, Digits()));
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
