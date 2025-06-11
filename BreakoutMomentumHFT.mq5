//+------------------------------------------------------------------+
//|                                        BreakoutMomentumHFT.mq5 |
//|                                   High Frequency Trading Strategy |
//|                        Breakout Momentum Trading using tick data |
//+------------------------------------------------------------------+
#property copyright "EA Developer"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Risk Management ==="
input double RiskPercent = 2.0;                    // Risk per trade (%)
input double MaxDailyLoss = 5.0;                   // Maximum daily loss (%)
input int MaxPyramidLevels = 3;                    // Maximum pyramid levels
input double PyramidMultiplier = 0.7;              // Pyramid size multiplier

input group "=== Entry Settings ==="
input double VolatilityThreshold = 2.0;            // Volatility spike threshold (multiplier)
input int VolatilityPeriod = 20;                   // Period for volatility calculation
input double MinMoveForPyramid = 10.0;             // Minimum move in points for pyramid entry
input int MaxPositionTime = 300;                   // Maximum position time in seconds

input group "=== Exit Settings ==="
input double TrailingStopPercent = 50.0;           // Trailing stop percentage of move
input double VolatilityStopMultiplier = 2.5;       // Stop loss based on volatility
input bool UseTimeBasedExit = true;                // Enable time-based exit
input double PartialTakeProfit = 30.0;             // Points for partial profit taking

input group "=== Optimization ==="
input int MaxConsecutiveLosses = 5;                // Max consecutive losses before pause
input int PauseAfterLosses = 3600;                 // Pause time in seconds after max losses

//--- Global variables
CTrade trade;
double tickPrices[];
datetime tickTimes[];
int tickCount = 0;
const int MAX_TICKS = 1000;

// Position tracking
struct PositionInfo {
    ulong ticket;
    double entryPrice;
    datetime entryTime;
    int pyramidLevel;
    double highestPrice;
    double lowestPrice;
    bool trailingActive;
};

PositionInfo positions[];
int positionCount = 0;

// Risk management
double dailyPnL = 0.0;
datetime lastDayCheck;
int consecutiveLosses = 0;
datetime pauseUntil = 0;

// Volatility calculation
double recentVolatility = 0.0;
double averageVolatility = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize arrays
    ArrayResize(tickPrices, MAX_TICKS);
    ArrayResize(tickTimes, MAX_TICKS);
    ArrayResize(positions, 100);
    
    // Reset variables
    tickCount = 0;
    positionCount = 0;
    dailyPnL = 0.0;
    lastDayCheck = TimeCurrent();
    consecutiveLosses = 0;
    pauseUntil = 0;
    
    // Set trade parameters
    trade.SetExpertMagicNumber(123456);
    trade.SetDeviationInPoints(3);
    trade.SetTypeFilling(ORDER_FILLING_IOC);
    
    Print("BreakoutMomentumHFT EA initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("BreakoutMomentumHFT EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check daily loss limit and consecutive losses
    if(!CheckRiskControls()) return;
    
    // Store tick data
    StoreTick();
    
    // Calculate volatility if we have enough data
    if(tickCount >= VolatilityPeriod) {
        CalculateVolatility();
        
        // Check for volatility spike and potential entry
        CheckVolatilityBreakout();
        
        // Manage existing positions
        ManagePositions();
    }
}

//+------------------------------------------------------------------+
//| Store current tick data                                          |
//+------------------------------------------------------------------+
void StoreTick()
{
    MqlTick tick;
    if(SymbolInfoTick(_Symbol, tick)) {
        // Shift array if at maximum capacity
        if(tickCount >= MAX_TICKS) {
            for(int i = 0; i < MAX_TICKS - 1; i++) {
                tickPrices[i] = tickPrices[i + 1];
                tickTimes[i] = tickTimes[i + 1];
            }
            tickCount = MAX_TICKS - 1;
        }
        
        // Store new tick
        tickPrices[tickCount] = tick.bid;
        tickTimes[tickCount] = tick.time;
        tickCount++;
    }
}

//+------------------------------------------------------------------+
//| Calculate current volatility                                     |
//+------------------------------------------------------------------+
void CalculateVolatility()
{
    if(tickCount < VolatilityPeriod) return;
    
    // Calculate standard deviation of recent price changes
    double sum = 0.0;
    double sumSq = 0.0;
    int count = 0;
    
    for(int i = tickCount - VolatilityPeriod + 1; i < tickCount; i++) {
        double change = MathAbs(tickPrices[i] - tickPrices[i-1]);
        sum += change;
        sumSq += change * change;
        count++;
    }
    
    if(count > 1) {
        double mean = sum / count;
        recentVolatility = MathSqrt((sumSq - sum * mean) / (count - 1));
        
        // Update average volatility (exponential moving average)
        if(averageVolatility == 0.0) {
            averageVolatility = recentVolatility;
        } else {
            averageVolatility = 0.1 * recentVolatility + 0.9 * averageVolatility;
        }
    }
}

//+------------------------------------------------------------------+
//| Check for volatility breakout and enter trade                   |
//+------------------------------------------------------------------+
void CheckVolatilityBreakout()
{
    if(averageVolatility == 0.0 || recentVolatility <= averageVolatility * VolatilityThreshold) return;
    
    // Don't enter if we already have maximum pyramid levels
    if(positionCount >= MaxPyramidLevels) return;
    
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return;
    
    // Determine direction based on recent price movement
    double currentPrice = tick.bid;
    double previousPrice = tickPrices[tickCount - 2];
    
    ENUM_ORDER_TYPE orderType;
    double entryPrice;
    
    if(currentPrice > previousPrice) {
        // Bullish breakout
        orderType = ORDER_TYPE_BUY;
        entryPrice = tick.ask;
    } else {
        // Bearish breakout
        orderType = ORDER_TYPE_SELL;
        entryPrice = tick.bid;
    }
    
    // Calculate position size
    double lotSize = CalculateLotSize();
    
    // Reduce lot size for pyramid entries
    if(positionCount > 0) {
        lotSize *= MathPow(PyramidMultiplier, positionCount);
    }
    
    // Execute trade
    if(trade.PositionOpen(_Symbol, orderType, lotSize, entryPrice, 0, 0, "BreakoutMomentum")) {
        // Store position information
        if(positionCount < ArraySize(positions)) {
            positions[positionCount].ticket = trade.ResultOrder();
            positions[positionCount].entryPrice = entryPrice;
            positions[positionCount].entryTime = TimeCurrent();
            positions[positionCount].pyramidLevel = positionCount;
            positions[positionCount].highestPrice = entryPrice;
            positions[positionCount].lowestPrice = entryPrice;
            positions[positionCount].trailingActive = false;
            positionCount++;
        }
        
        Print("Volatility breakout entry: ", EnumToString(orderType), " at ", entryPrice, 
              " (Volatility: ", recentVolatility, " vs Avg: ", averageVolatility, ")");
    }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return;
    
    for(int i = positionCount - 1; i >= 0; i--) {
        if(!PositionSelectByTicket(positions[i].ticket)) {
            // Position closed externally, remove from tracking
            RemovePosition(i);
            continue;
        }
        
        double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
        
        // Update price extremes
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            if(currentPrice > positions[i].highestPrice) {
                positions[i].highestPrice = currentPrice;
            }
        } else {
            if(currentPrice < positions[i].lowestPrice) {
                positions[i].lowestPrice = currentPrice;
            }
        }
        
        // Check for pyramid opportunity
        CheckPyramidEntry(i, currentPrice);
        
        // Check trailing stop
        CheckTrailingStop(i, currentPrice);
        
        // Check time-based exit
        if(UseTimeBasedExit && TimeCurrent() - positions[i].entryTime > MaxPositionTime) {
            ClosePosition(i, "Time-based exit");
        }
        
        // Check volatility-based exit
        if(recentVolatility < averageVolatility * 0.5) {
            ClosePosition(i, "Low volatility exit");
        }
    }
}

//+------------------------------------------------------------------+
//| Check for pyramid entry opportunity                             |
//+------------------------------------------------------------------+
void CheckPyramidEntry(int posIndex, double currentPrice)
{
    if(positionCount >= MaxPyramidLevels) return;
    
    double entryPrice = positions[posIndex].entryPrice;
    double minMove = MinMoveForPyramid * _Point;
    
    bool pyramidCondition = false;
    
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
        pyramidCondition = (currentPrice >= entryPrice + minMove);
    } else {
        pyramidCondition = (currentPrice <= entryPrice - minMove);
    }
    
    if(pyramidCondition && recentVolatility > averageVolatility * VolatilityThreshold * 0.8) {
        // Add pyramid position
        ENUM_ORDER_TYPE orderType = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                                   ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        
        double lotSize = CalculateLotSize() * MathPow(PyramidMultiplier, positionCount);
        
        MqlTick tick;
        if(SymbolInfoTick(_Symbol, tick)) {
            double pyramidPrice = (orderType == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
            
            if(trade.PositionOpen(_Symbol, orderType, lotSize, pyramidPrice, 0, 0, "Pyramid")) {
                // Store pyramid position
                if(positionCount < ArraySize(positions)) {
                    positions[positionCount].ticket = trade.ResultOrder();
                    positions[positionCount].entryPrice = pyramidPrice;
                    positions[positionCount].entryTime = TimeCurrent();
                    positions[positionCount].pyramidLevel = positionCount;
                    positions[positionCount].highestPrice = pyramidPrice;
                    positions[positionCount].lowestPrice = pyramidPrice;
                    positions[positionCount].trailingActive = false;
                    positionCount++;
                    
                    Print("Pyramid entry added at level ", positionCount, " price: ", pyramidPrice);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check and apply trailing stop                                   |
//+------------------------------------------------------------------+
void CheckTrailingStop(int posIndex, double currentPrice)
{
    double entryPrice = positions[posIndex].entryPrice;
    bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
    
    // Activate trailing stop after sufficient move
    double minMoveForTrailing = VolatilityStopMultiplier * recentVolatility;
    if(minMoveForTrailing < 10 * _Point) minMoveForTrailing = 10 * _Point;
    
    bool trailingShouldActivate = false;
    if(isBuy) {
        trailingShouldActivate = (currentPrice >= entryPrice + minMoveForTrailing);
    } else {
        trailingShouldActivate = (currentPrice <= entryPrice - minMoveForTrailing);
    }
    
    if(trailingShouldActivate) {
        positions[posIndex].trailingActive = true;
    }
    
    // Apply trailing stop if active
    if(positions[posIndex].trailingActive) {
        double stopLevel = 0.0;
        
        if(isBuy) {
            double totalMove = positions[posIndex].highestPrice - entryPrice;
            stopLevel = positions[posIndex].highestPrice - (totalMove * TrailingStopPercent / 100.0);
            
            if(currentPrice <= stopLevel) {
                ClosePosition(posIndex, "Trailing stop hit");
            }
        } else {
            double totalMove = entryPrice - positions[posIndex].lowestPrice;
            stopLevel = positions[posIndex].lowestPrice + (totalMove * TrailingStopPercent / 100.0);
            
            if(currentPrice >= stopLevel) {
                ClosePosition(posIndex, "Trailing stop hit");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
void ClosePosition(int posIndex, string reason)
{
    if(PositionSelectByTicket(positions[posIndex].ticket)) {
        double profit = PositionGetDouble(POSITION_PROFIT);
        
        if(trade.PositionClose(positions[posIndex].ticket)) {
            Print("Position closed: ", reason, " Profit: ", profit);
            
            // Update daily P&L
            dailyPnL += profit;
            
            // Track consecutive losses
            if(profit < 0) {
                consecutiveLosses++;
            } else {
                consecutiveLosses = 0;
            }
            
            RemovePosition(posIndex);
        }
    }
}

//+------------------------------------------------------------------+
//| Remove position from tracking array                             |
//+------------------------------------------------------------------+
void RemovePosition(int posIndex)
{
    for(int i = posIndex; i < positionCount - 1; i++) {
        positions[i] = positions[i + 1];
    }
    positionCount--;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * RiskPercent / 100.0;
    
    // Use volatility-based stop loss for lot calculation
    double stopLossPoints = VolatilityStopMultiplier * recentVolatility / _Point;
    if(stopLossPoints < 10) stopLossPoints = 10; // Minimum stop
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = riskAmount / (stopLossPoints * tickValue);
    
    // Apply position size limits
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Check risk controls                                              |
//+------------------------------------------------------------------+
bool CheckRiskControls()
{
    // Check if we're in pause period
    if(TimeCurrent() < pauseUntil) return false;
    
    // Check daily loss limit
    datetime currentDay = TimeCurrent() - TimeCurrent() % 86400;
    if(currentDay != lastDayCheck) {
        dailyPnL = 0.0; // Reset daily P&L
        lastDayCheck = currentDay;
    }
    
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double maxDailyLossAmount = accountBalance * MaxDailyLoss / 100.0;
    
    if(dailyPnL <= -maxDailyLossAmount) {
        Print("Daily loss limit reached. Trading suspended.");
        return false;
    }
    
    // Check consecutive losses
    if(consecutiveLosses >= MaxConsecutiveLosses) {
        pauseUntil = TimeCurrent() + PauseAfterLosses;
        Print("Max consecutive losses reached. Trading paused until: ", TimeToString(pauseUntil));
        consecutiveLosses = 0; // Reset counter
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Timer function for periodic checks                              |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Periodic cleanup and monitoring
    CheckRiskControls();
}