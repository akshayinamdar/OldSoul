# Random Direction Trading Strategy

## Strategy Overview
A random-direction trading approach for EURUSD that takes trades at regular intervals with no directional bias.

## Input Parameters
- **Start Time**: Daily trading start time (input parameter)
- **End Time**: Daily trading end time (input parameter)
- **Interval**: Market check frequency in minutes (input parameter)
- **Position Size**: Fixed lot size (input parameter)
- **Exit Mode**: Boolean to select exit rule (true = exit on profit, false = exit on loss)
- **Minimum Profit/Loss Pips**: Threshold for trade closure (input parameter)

## Entry Conditions
1. **Trading Hours Check**: Verify current time is within daily start and end times
2. **Market Check Schedule**: Only analyze market at every x minutes of interval
3. **Position Availability**: Only take new position if no existing position prevents it

## Position Management
- **Profit Target**: No take profit level set
- **Stop Loss**: No stop loss level set
- **Position Size**: Fixed lot size (input parameter)
- **Trade Direction**: Random (50% buy, 50% sell) - no directional bias
- **Multiple Positions**: Can have multiple open positions simultaneously

## Exit Rules
Two mutually exclusive exit strategies (selected by boolean parameter):

### Option 1: Exit on Profit
- After taking a trade, at the next interval check if the trade is in profit
- If profit ≥ minimum profit/loss pips threshold: close the trade
- If profit < minimum profit/loss pips threshold: keep trade open, skip taking new position

### Option 2: Exit on Loss
- After taking a trade, at the next interval check if the trade is in loss
- If loss ≥ minimum profit/loss pips threshold: close the trade
- If loss < minimum profit/loss pips threshold: keep trade open, skip taking new position

## Position Flow Logic
1. At each interval, check for existing positions that need evaluation
2. Apply selected exit rule to eligible positions
3. If no new position was prevented by existing trades, take a new random direction trade
4. Repeat at next interval