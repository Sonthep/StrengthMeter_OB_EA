//+------------------------------------------------------------------+
//|                                   StrengthMeter_OB_EA_v2_Working.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "2.01"
#property description "Working Strength Meter + Order Block EA v2.0"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Input parameters
input group "=== TRADING SETTINGS ==="
input double   RiskPercent = 1.0;           // Risk per trade (% of balance)
input double   RiskReward = 2.0;            // Risk to Reward ratio
input int      StopLossPips = 15;           // Stop Loss in pips beyond OB
input int      MaxTradesPerPair = 2;        // Max trades per pair per day
input bool     AutoTradingInput = true;     // Auto Trading ON/OFF

input group "=== STRENGTH METER ==="
input double   MinStrengthDiff = 3.0;       // Minimum strength difference (reduced from 4.0)
input int      StrengthPeriod = 14;         // Period for strength calculation

input group "=== ORDER BLOCK ==="
input int      OB_LookbackBars = 30;        // Lookback bars for OB detection
input int      BOS_LookbackBars = 15;       // Lookback bars for BOS detection
input double   OB_MinSize = 5.0;            // Minimum OB size in pips (reduced from 8.0)
input double   OB_MinStrengthScore = 40.0;  // Minimum OB strength score (reduced from 60.0)

input group "=== DASHBOARD ==="
input int      DashboardX = 20;             // Dashboard X position
input int      DashboardY = 50;             // Dashboard Y position
input bool     DebugMode = true;            // Enable debug messages

//--- Global variables
CTrade trade;
CPositionInfo position;
COrderInfo order;

bool AutoTrading = true;

// Symbols to trade
string Symbols[] = {"XAUUSD.iux", "EURUSD.iux", "GBPUSD.iux", "USDJPY.iux", "GBPJPY.iux", "EURJPY.iux"};

// Pairs for strength calculation
string StrengthPairs[] = {
   "EURUSD.iux", "GBPUSD.iux", "USDJPY.iux", "USDCHF.iux", "USDCAD.iux", "AUDUSD.iux",
   "EURGBP.iux", "EURJPY.iux", "GBPJPY.iux", "CHFJPY.iux", "CADJPY.iux", "AUDJPY.iux"
};

struct StrengthData
{
   double USD, EUR, GBP, JPY, CHF, CAD, AUD, NZD;
   datetime last_update;
};

struct OrderBlockV2
{
   double high, low, open, close;
   datetime time;
   bool is_bullish;
   bool valid;
   double strength_score;
   ENUM_TIMEFRAMES timeframe;
   int touch_count;
};

struct TradeSignalV2
{
   string symbol;
   int signal_type;            // 1 = BUY, -1 = SELL, 0 = NONE
   double entry_price;
   double stop_loss;
   double take_profit;
   string reason;
   double confidence_score;
   OrderBlockV2 ob;
};

struct SMCData
{
   bool bullish_bos;
   bool bearish_bos;
   bool displacement_up;
   bool displacement_down;
   double inducement_high;
   double inducement_low;
};

//--- Global data
StrengthData CurrentStrength;
OrderBlockV2 OBData[];
TradeSignalV2 Signals[];
SMCData SMCAnalysis[];
int DailyTrades[][2];

//--- Dashboard objects
string PanelName = "StrengthOB_Panel_v2";
string ButtonAutoTrade = "AutoTradeBtn_v2";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   AutoTrading = AutoTradingInput;
   
   // Initialize arrays
   ArrayResize(OBData, ArraySize(Symbols));
   ArrayResize(Signals, ArraySize(Symbols));
   ArrayResize(SMCAnalysis, ArraySize(Symbols));
   ArrayResize(DailyTrades, ArraySize(Symbols));
   
   for(int i = 0; i < ArraySize(Symbols); i++)
   {
      DailyTrades[i][0] = 0;
      DailyTrades[i][1] = 0;
   }
   
   CreateDashboard();
   EventSetTimer(1);
   
   Print("Working Strength Meter + OB EA v2.0 initialized");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   RemoveDashboard();
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update strength meter
   CalculateCurrencyStrength();
   
   // Analyze SMC
   AnalyzeSMC();
   
   // Scan for signals
   ScanForSignals();
   
   // Update dashboard
   UpdateDashboard();
   
   // Execute trades
   if(AutoTrading)
   {
      ExecuteSignals();
   }
}

//+------------------------------------------------------------------+
//| Calculate currency strength                                      |
//+------------------------------------------------------------------+
void CalculateCurrencyStrength()
{
   double usd=0, eur=0, gbp=0, jpy=0, chf=0, cad=0, aud=0, nzd=0;
   int count = 0;
   
   for(int i = 0; i < ArraySize(StrengthPairs); i++)
   {
      string symbol = StrengthPairs[i];
      if(!SymbolSelect(symbol, true)) continue;
      
      double price_change = GetPriceChange(symbol, StrengthPeriod);
      if(price_change == 0) continue;
      
      string base = GetBaseCurrency(symbol);
      string quote = GetQuoteCurrency(symbol);
      
      // Add to base currency
      if(base == "USD") usd += price_change;
      else if(base == "EUR") eur += price_change;
      else if(base == "GBP") gbp += price_change;
      else if(base == "JPY") jpy += price_change;
      else if(base == "CHF") chf += price_change;
      else if(base == "CAD") cad += price_change;
      else if(base == "AUD") aud += price_change;
      else if(base == "NZD") nzd += price_change;
      
      // Subtract from quote currency
      if(quote == "USD") usd -= price_change;
      else if(quote == "EUR") eur -= price_change;
      else if(quote == "GBP") gbp -= price_change;
      else if(quote == "JPY") jpy -= price_change;
      else if(quote == "CHF") chf -= price_change;
      else if(quote == "CAD") cad -= price_change;
      else if(quote == "AUD") aud -= price_change;
      else if(quote == "NZD") nzd -= price_change;
      
      count++;
   }
   
   if(count > 0)
   {
      CurrentStrength.USD = usd / count * 100;
      CurrentStrength.EUR = eur / count * 100;
      CurrentStrength.GBP = gbp / count * 100;
      CurrentStrength.JPY = jpy / count * 100;
      CurrentStrength.CHF = chf / count * 100;
      CurrentStrength.CAD = cad / count * 100;
      CurrentStrength.AUD = aud / count * 100;
      CurrentStrength.NZD = nzd / count * 100;
      CurrentStrength.last_update = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Analyze Smart Money Concepts                                    |
//+------------------------------------------------------------------+
void AnalyzeSMC()
{
   for(int i = 0; i < ArraySize(Symbols); i++)
   {
      string symbol = Symbols[i];
      if(!SymbolSelect(symbol, true)) continue;
      
      SMCAnalysis[i].bullish_bos = false;
      SMCAnalysis[i].bearish_bos = false;
      SMCAnalysis[i].displacement_up = false;
      SMCAnalysis[i].displacement_down = false;
      
      // Check for Break of Structure
      double recent_high = 0, recent_low = DBL_MAX;
      for(int j = 1; j <= BOS_LookbackBars; j++)
      {
         double high = iHigh(symbol, PERIOD_M5, j);
         double low = iLow(symbol, PERIOD_M5, j);
         if(high > recent_high) recent_high = high;
         if(low < recent_low) recent_low = low;
      }
      
      double current_high = iHigh(symbol, PERIOD_M5, 0);
      double current_low = iLow(symbol, PERIOD_M5, 0);
      
      if(current_high > recent_high) SMCAnalysis[i].bullish_bos = true;
      if(current_low < recent_low) SMCAnalysis[i].bearish_bos = true;
      
      // Check for displacement
      double candle_size = (iHigh(symbol, PERIOD_M5, 0) - iLow(symbol, PERIOD_M5, 0)) / GetPipValue(symbol);
      if(candle_size >= 15.0)
      {
         if(iClose(symbol, PERIOD_M5, 0) > iOpen(symbol, PERIOD_M5, 0))
            SMCAnalysis[i].displacement_up = true;
         else
            SMCAnalysis[i].displacement_down = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Scan for trading signals                                         |
//+------------------------------------------------------------------+
void ScanForSignals()
{
   static datetime last_debug = 0;
   bool should_debug = (DebugMode && TimeCurrent() - last_debug > 60); // Debug every minute
   
   if(should_debug)
   {
      Print("🔍 === SIGNAL SCAN DEBUG ===");
      last_debug = TimeCurrent();
   }
   
   for(int i = 0; i < ArraySize(Symbols); i++)
   {
      string symbol = Symbols[i];
      if(!SymbolSelect(symbol, true)) continue;
      
      // Reset signal
      Signals[i].symbol = symbol;
      Signals[i].signal_type = 0;
      Signals[i].confidence_score = 0;
      Signals[i].reason = "";
      
      // Check daily trade limit
      if(DailyTrades[i][0] + DailyTrades[i][1] >= MaxTradesPerPair) 
      {
         if(should_debug) Print("❌ ", symbol, " - Daily trade limit reached");
         continue;
      }
      
      // Get currency strengths
      string base = GetBaseCurrency(symbol);
      string quote = GetQuoteCurrency(symbol);
      if(base == "" || quote == "") 
      {
         if(should_debug) Print("❌ ", symbol, " - Invalid currency pair");
         continue;
      }
      
      double base_strength = GetCurrencyStrength(base);
      double quote_strength = GetCurrencyStrength(quote);
      double strength_diff = base_strength - quote_strength;
      
      if(should_debug)
      {
         Print("📊 ", symbol, " - ", base, "(", DoubleToString(base_strength, 1), ") vs ", 
               quote, "(", DoubleToString(quote_strength, 1), ") = Diff: ", DoubleToString(strength_diff, 1));
      }
      
      // Check strength condition
      if(MathAbs(strength_diff) < MinStrengthDiff) 
      {
         if(should_debug) Print("❌ ", symbol, " - Strength diff too small: ", DoubleToString(MathAbs(strength_diff), 1), " < ", MinStrengthDiff);
         continue;
      }
      
      // Detect order block with relaxed conditions
      OrderBlockV2 ob = DetectOrderBlockRelaxed(symbol);
      if(!ob.valid) 
      {
         if(should_debug) Print("❌ ", symbol, " - No valid Order Block found");
         continue;
      }
      
      if(ob.strength_score < OB_MinStrengthScore) 
      {
         if(should_debug) Print("❌ ", symbol, " - OB strength too low: ", DoubleToString(ob.strength_score, 1), " < ", OB_MinStrengthScore);
         continue;
      }
      
      double current_price = SymbolInfoDouble(symbol, SYMBOL_BID);
      double confidence = 50.0;
      
      if(should_debug)
      {
         Print("✅ ", symbol, " - Found OB: ", ob.is_bullish ? "BULLISH" : "BEARISH", 
               " Score: ", DoubleToString(ob.strength_score, 1),
               " Range: ", DoubleToString(ob.low, 5), " - ", DoubleToString(ob.high, 5),
               " Current: ", DoubleToString(current_price, 5));
      }
      
      // BUY signal (relaxed conditions)
      if(strength_diff >= MinStrengthDiff && ob.is_bullish && 
         current_price >= (ob.low - GetPipValue(symbol) * 5) && 
         current_price <= (ob.high + GetPipValue(symbol) * 5))
      {
         if(DailyTrades[i][0] < MaxTradesPerPair)
         {
            Signals[i].signal_type = 1;
            Signals[i].entry_price = SymbolInfoDouble(symbol, SYMBOL_ASK);
            Signals[i].stop_loss = ob.low - StopLossPips * GetPipValue(symbol);
            Signals[i].take_profit = Signals[i].entry_price + (Signals[i].entry_price - Signals[i].stop_loss) * RiskReward;
            
            confidence += MathMin(30.0, strength_diff * 3.0);
            confidence += MathMin(20.0, ob.strength_score / 3.0);
            if(SMCAnalysis[i].bullish_bos || SMCAnalysis[i].displacement_up) confidence += 15.0;
            
            Signals[i].confidence_score = MathMin(100.0, confidence);
            Signals[i].reason = StringFormat("BUY: %s(%.1f) vs %s(%.1f), OB:%.0f", 
                                           base, base_strength, quote, quote_strength, ob.strength_score);
            Signals[i].ob = ob;
            
            if(should_debug) Print("🟢 ", symbol, " - BUY SIGNAL Generated! Confidence: ", DoubleToString(confidence, 1), "%");
         }
      }
      
      // SELL signal (relaxed conditions)
      else if(strength_diff <= -MinStrengthDiff && !ob.is_bullish && 
              current_price >= (ob.low - GetPipValue(symbol) * 5) && 
              current_price <= (ob.high + GetPipValue(symbol) * 5))
      {
         if(DailyTrades[i][1] < MaxTradesPerPair)
         {
            Signals[i].signal_type = -1;
            Signals[i].entry_price = SymbolInfoDouble(symbol, SYMBOL_BID);
            Signals[i].stop_loss = ob.high + StopLossPips * GetPipValue(symbol);
            Signals[i].take_profit = Signals[i].entry_price - (Signals[i].stop_loss - Signals[i].entry_price) * RiskReward;
            
            confidence += MathMin(30.0, MathAbs(strength_diff) * 3.0);
            confidence += MathMin(20.0, ob.strength_score / 3.0);
            if(SMCAnalysis[i].bearish_bos || SMCAnalysis[i].displacement_down) confidence += 15.0;
            
            Signals[i].confidence_score = MathMin(100.0, confidence);
            Signals[i].reason = StringFormat("SELL: %s(%.1f) vs %s(%.1f), OB:%.0f", 
                                           base, base_strength, quote, quote_strength, ob.strength_score);
            Signals[i].ob = ob;
            
            if(should_debug) Print("🔴 ", symbol, " - SELL SIGNAL Generated! Confidence: ", DoubleToString(confidence, 1), "%");
         }
      }
      else if(should_debug)
      {
         Print("❌ ", symbol, " - Signal conditions not met. Price not in OB range or direction mismatch");
      }
   }
   
   if(should_debug) Print("🔍 === END SIGNAL SCAN ===");
}

//+------------------------------------------------------------------+
//| Execute trading signals                                          |
//+------------------------------------------------------------------+
void ExecuteSignals()
{
   for(int i = 0; i < ArraySize(Signals); i++)
   {
      if(Signals[i].signal_type == 0) continue;
      if(Signals[i].confidence_score < 50.0) continue; // Reduced from 65.0
      
      string symbol = Signals[i].symbol;
      
      // Check M1 confirmation (more relaxed)
      if(!HasM1ConfirmationRelaxed(symbol, Signals[i].signal_type)) continue;
      
      // Calculate position size
      double lot_size = CalculatePositionSize(symbol, Signals[i].entry_price, Signals[i].stop_loss);
      if(lot_size <= 0) continue;
      
      // Execute trade
      bool success = false;
      if(Signals[i].signal_type == 1) // BUY
      {
         success = trade.Buy(lot_size, symbol, Signals[i].entry_price, Signals[i].stop_loss, Signals[i].take_profit, 
                           "StrengthOB_v2_BUY: " + Signals[i].reason);
         if(success) DailyTrades[i][0]++;
      }
      else if(Signals[i].signal_type == -1) // SELL
      {
         success = trade.Sell(lot_size, symbol, Signals[i].entry_price, Signals[i].stop_loss, Signals[i].take_profit, 
                            "StrengthOB_v2_SELL: " + Signals[i].reason);
         if(success) DailyTrades[i][1]++;
      }
      
      if(success)
      {
         Print("✅ Trade executed: ", Signals[i].reason, " | Confidence: ", Signals[i].confidence_score, "%");
      }
      else if(DebugMode)
      {
         Print("❌ Trade failed: ", trade.ResultComment(), " | ", Signals[i].reason);
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Order Block with relaxed conditions                      |
//+------------------------------------------------------------------+
OrderBlockV2 DetectOrderBlockRelaxed(string symbol)
{
   OrderBlockV2 ob;
   ob.valid = false;
   ob.strength_score = 0;
   
   ENUM_TIMEFRAMES timeframes[] = {PERIOD_M5, PERIOD_M15};
   
   for(int tf = 0; tf < 2; tf++)
   {
      ENUM_TIMEFRAMES timeframe = timeframes[tf];
      
      // More relaxed BOS check
      bool has_bos = HasBreakOfStructureRelaxed(symbol, timeframe);
      
      for(int i = 1; i < OB_LookbackBars; i++)
      {
         double high = iHigh(symbol, timeframe, i);
         double low = iLow(symbol, timeframe, i);
         double open = iOpen(symbol, timeframe, i);
         double close = iClose(symbol, timeframe, i);
         
         double candle_size = (high - low) / GetPipValue(symbol);
         if(candle_size < OB_MinSize) continue;
         
         // Calculate strength score (more generous)
         double score = 40.0; // Base score
         score += MathMin(30.0, candle_size / OB_MinSize * 15.0); // Size bonus
         score += 20.0; // Volume bonus (simplified)
         if(timeframe == PERIOD_M15) score += 10.0; // Timeframe bonus
         if(has_bos) score += 15.0; // BOS bonus
         
         // Bullish OB (more relaxed conditions)
         if(close > open)
         {
            // Check for any price interaction with this level
            bool has_interaction = false;
            for(int j = 0; j < i && j < 10; j++)
            {
               double test_low = iLow(symbol, timeframe, j);
               double test_high = iHigh(symbol, timeframe, j);
               if(test_low <= high && test_high >= low)
               {
                  has_interaction = true;
                  break;
               }
            }
            
            if(has_interaction || !has_bos) // Accept even without BOS if there's interaction
            {
               ob.high = high;
               ob.low = low;
               ob.open = open;
               ob.close = close;
               ob.time = iTime(symbol, timeframe, i);
               ob.is_bullish = true;
               ob.valid = true;
               ob.strength_score = score;
               ob.timeframe = timeframe;
               ob.touch_count = 1;
               return ob;
            }
         }
         
         // Bearish OB (more relaxed conditions)
         if(close < open)
         {
            // Check for any price interaction with this level
            bool has_interaction = false;
            for(int j = 0; j < i && j < 10; j++)
            {
               double test_low = iLow(symbol, timeframe, j);
               double test_high = iHigh(symbol, timeframe, j);
               if(test_low <= high && test_high >= low)
               {
                  has_interaction = true;
                  break;
               }
            }
            
            if(has_interaction || !has_bos) // Accept even without BOS if there's interaction
            {
               ob.high = high;
               ob.low = low;
               ob.open = open;
               ob.close = close;
               ob.time = iTime(symbol, timeframe, i);
               ob.is_bullish = false;
               ob.valid = true;
               ob.strength_score = score;
               ob.timeframe = timeframe;
               ob.touch_count = 1;
               return ob;
            }
         }
      }
   }
   
   return ob;
}

//+------------------------------------------------------------------+
//| More relaxed Break of Structure detection                       |
//+------------------------------------------------------------------+
bool HasBreakOfStructureRelaxed(string symbol, ENUM_TIMEFRAMES timeframe)
{
   double recent_high = 0, recent_low = DBL_MAX;
   for(int i = 1; i <= BOS_LookbackBars; i++)
   {
      double high = iHigh(symbol, timeframe, i);
      double low = iLow(symbol, timeframe, i);
      if(high > recent_high) recent_high = high;
      if(low < recent_low) recent_low = low;
   }
   
   double current_high = iHigh(symbol, timeframe, 0);
   double current_low = iLow(symbol, timeframe, 0);
   double current_close = iClose(symbol, timeframe, 0);
   
   // More relaxed BOS - accept if close is near the highs/lows
   double pip_tolerance = GetPipValue(symbol) * 3.0;
   
   return (current_high > recent_high || 
           current_low < recent_low || 
           current_close > (recent_high - pip_tolerance) ||
           current_close < (recent_low + pip_tolerance));
}

//+------------------------------------------------------------------+
//| More relaxed M1 confirmation                                    |
//+------------------------------------------------------------------+
bool HasM1ConfirmationRelaxed(string symbol, int signal_type)
{
   // Check last 3 M1 candles instead of just 1
   for(int i = 1; i <= 3; i++)
   {
      double close = iClose(symbol, PERIOD_M1, i);
      double open = iOpen(symbol, PERIOD_M1, i);
      
      if(signal_type == 1 && close > open) return true; // Any bullish M1 candle
      if(signal_type == -1 && close < open) return true; // Any bearish M1 candle
   }
   
   // If no clear direction, check overall M1 trend using simple price comparison
   double current_close = iClose(symbol, PERIOD_M1, 1);
   double past_close = iClose(symbol, PERIOD_M1, 6); // 5 candles ago
   
   if(signal_type == 1) return (current_close > past_close);
   if(signal_type == -1) return (current_close < past_close);
   
   return true; // Accept by default if no clear signal
}

//+------------------------------------------------------------------+
//| Helper functions                                                 |
//+------------------------------------------------------------------+
double GetPriceChange(string symbol, int period)
{
   double current = SymbolInfoDouble(symbol, SYMBOL_BID);
   double past = iClose(symbol, PERIOD_H1, period);
   if(past == 0) return 0;
   return (current - past) / past * 100;
}

string GetBaseCurrency(string symbol)
{
   string clean = symbol;
   if(StringFind(symbol, ".iux") >= 0)
      clean = StringSubstr(symbol, 0, StringFind(symbol, ".iux"));
   if(StringLen(clean) >= 6)
      return StringSubstr(clean, 0, 3);
   return "";
}

string GetQuoteCurrency(string symbol)
{
   string clean = symbol;
   if(StringFind(symbol, ".iux") >= 0)
      clean = StringSubstr(symbol, 0, StringFind(symbol, ".iux"));
   if(StringLen(clean) >= 6)
      return StringSubstr(clean, 3, 3);
   return "";
}

double GetCurrencyStrength(string currency)
{
   if(currency == "USD") return CurrentStrength.USD;
   else if(currency == "EUR") return CurrentStrength.EUR;
   else if(currency == "GBP") return CurrentStrength.GBP;
   else if(currency == "JPY") return CurrentStrength.JPY;
   else if(currency == "CHF") return CurrentStrength.CHF;
   else if(currency == "CAD") return CurrentStrength.CAD;
   else if(currency == "AUD") return CurrentStrength.AUD;
   else if(currency == "NZD") return CurrentStrength.NZD;
   return 0;
}

double GetPipValue(string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits == 5 || digits == 3) return point * 10;
   return point * 100;
}

bool HasBreakOfStructure(string symbol, ENUM_TIMEFRAMES timeframe)
{
   double recent_high = 0, recent_low = DBL_MAX;
   for(int i = 1; i <= BOS_LookbackBars; i++)
   {
      double high = iHigh(symbol, timeframe, i);
      double low = iLow(symbol, timeframe, i);
      if(high > recent_high) recent_high = high;
      if(low < recent_low) recent_low = low;
   }
   
   double current = SymbolInfoDouble(symbol, SYMBOL_BID);
   return (current > recent_high || current < recent_low);
}

bool IsPullbackAfterBullishCandle(string symbol, ENUM_TIMEFRAMES timeframe, int index)
{
   for(int i = 0; i < index; i++)
   {
      double low = iLow(symbol, timeframe, i);
      double high = iHigh(symbol, timeframe, i);
      double ob_low = iLow(symbol, timeframe, index);
      double ob_high = iHigh(symbol, timeframe, index);
      if(low <= ob_high && high >= ob_low) return true;
   }
   return false;
}

bool IsPullbackAfterBearishCandle(string symbol, ENUM_TIMEFRAMES timeframe, int index)
{
   for(int i = 0; i < index; i++)
   {
      double low = iLow(symbol, timeframe, i);
      double high = iHigh(symbol, timeframe, i);
      double ob_low = iLow(symbol, timeframe, index);
      double ob_high = iHigh(symbol, timeframe, index);
      if(low <= ob_high && high >= ob_low) return true;
   }
   return false;
}

bool HasM1Confirmation(string symbol, int signal_type)
{
   double close1 = iClose(symbol, PERIOD_M1, 1);
   double open1 = iOpen(symbol, PERIOD_M1, 1);
   
   if(signal_type == 1) return (close1 > open1);
   else if(signal_type == -1) return (close1 < open1);
   return false;
}

double CalculatePositionSize(string symbol, double entry, double stop_loss)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * RiskPercent / 100.0;
   double stop_distance = MathAbs(entry - stop_loss);
   double pip_distance = stop_distance / GetPipValue(symbol);
   
   if(pip_distance <= 0) return 0;
   
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot_size = risk_amount / (pip_distance * tick_value);
   
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
   lot_size = MathFloor(lot_size / lot_step) * lot_step;
   
   return lot_size;
}

//+------------------------------------------------------------------+
//| Dashboard functions                                              |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   // Main panel with gradient effect
   ObjectCreate(0, PanelName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PanelName, OBJPROP_XDISTANCE, DashboardX);
   ObjectSetInteger(0, PanelName, OBJPROP_YDISTANCE, DashboardY);
   ObjectSetInteger(0, PanelName, OBJPROP_XSIZE, 450);
   ObjectSetInteger(0, PanelName, OBJPROP_YSIZE, 650);
   ObjectSetInteger(0, PanelName, OBJPROP_BGCOLOR, C'25,25,35');
   ObjectSetInteger(0, PanelName, OBJPROP_BORDER_COLOR, C'70,130,180');
   ObjectSetInteger(0, PanelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, PanelName, OBJPROP_WIDTH, 2);
   
   // Header background
   ObjectCreate(0, "HeaderBG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "HeaderBG", OBJPROP_XDISTANCE, DashboardX + 2);
   ObjectSetInteger(0, "HeaderBG", OBJPROP_YDISTANCE, DashboardY + 2);
   ObjectSetInteger(0, "HeaderBG", OBJPROP_XSIZE, 446);
   ObjectSetInteger(0, "HeaderBG", OBJPROP_YSIZE, 45);
   ObjectSetInteger(0, "HeaderBG", OBJPROP_BGCOLOR, C'70,130,180');
   ObjectSetInteger(0, "HeaderBG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   
   // Title with better styling
   ObjectCreate(0, "Title_v2", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "Title_v2", OBJPROP_XDISTANCE, DashboardX + 15);
   ObjectSetInteger(0, "Title_v2", OBJPROP_YDISTANCE, DashboardY + 15);
   ObjectSetString(0, "Title_v2", OBJPROP_TEXT, "🚀 STRENGTH METER + ORDER BLOCK EA v2.0");
   ObjectSetInteger(0, "Title_v2", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "Title_v2", OBJPROP_FONTSIZE, 12);
   ObjectSetString(0, "Title_v2", OBJPROP_FONT, "Arial Bold");
   
   // Status indicator
   ObjectCreate(0, "StatusIndicator", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "StatusIndicator", OBJPROP_XDISTANCE, DashboardX + 400);
   ObjectSetInteger(0, "StatusIndicator", OBJPROP_YDISTANCE, DashboardY + 15);
   ObjectSetString(0, "StatusIndicator", OBJPROP_TEXT, "🟢 LIVE");
   ObjectSetInteger(0, "StatusIndicator", OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, "StatusIndicator", OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, "StatusIndicator", OBJPROP_FONT, "Arial Bold");
   
   // Strength section header
   ObjectCreate(0, "StrengthHeader", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "StrengthHeader", OBJPROP_XDISTANCE, DashboardX + 15);
   ObjectSetInteger(0, "StrengthHeader", OBJPROP_YDISTANCE, DashboardY + 60);
   ObjectSetString(0, "StrengthHeader", OBJPROP_TEXT, "📊 CURRENCY STRENGTH ANALYSIS");
   ObjectSetInteger(0, "StrengthHeader", OBJPROP_COLOR, C'255,215,0');
   ObjectSetInteger(0, "StrengthHeader", OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, "StrengthHeader", OBJPROP_FONT, "Arial Bold");
   
   // Currency strength bars and values
   string currencies[] = {"USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD"};
   for(int i = 0; i < 8; i++)
   {
      int x = DashboardX + 15 + (i % 2) * 210;
      int y = DashboardY + 85 + (i / 2) * 35;
      
      // Currency label
      ObjectCreate(0, "Currency_" + currencies[i], OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "Currency_" + currencies[i], OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, "Currency_" + currencies[i], OBJPROP_YDISTANCE, y);
      ObjectSetString(0, "Currency_" + currencies[i], OBJPROP_TEXT, currencies[i] + ":");
      ObjectSetInteger(0, "Currency_" + currencies[i], OBJPROP_COLOR, clrSilver);
      ObjectSetInteger(0, "Currency_" + currencies[i], OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, "Currency_" + currencies[i], OBJPROP_FONT, "Arial Bold");
      
      // Strength value
      ObjectCreate(0, "Strength_" + currencies[i], OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "Strength_" + currencies[i], OBJPROP_XDISTANCE, x + 45);
      ObjectSetInteger(0, "Strength_" + currencies[i], OBJPROP_YDISTANCE, y);
      ObjectSetString(0, "Strength_" + currencies[i], OBJPROP_TEXT, "0.0");
      ObjectSetInteger(0, "Strength_" + currencies[i], OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, "Strength_" + currencies[i], OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, "Strength_" + currencies[i], OBJPROP_FONT, "Arial Bold");
      
      // Strength bar background
      ObjectCreate(0, "BarBG_" + currencies[i], OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "BarBG_" + currencies[i], OBJPROP_XDISTANCE, x + 85);
      ObjectSetInteger(0, "BarBG_" + currencies[i], OBJPROP_YDISTANCE, y + 3);
      ObjectSetInteger(0, "BarBG_" + currencies[i], OBJPROP_XSIZE, 100);
      ObjectSetInteger(0, "BarBG_" + currencies[i], OBJPROP_YSIZE, 12);
      ObjectSetInteger(0, "BarBG_" + currencies[i], OBJPROP_BGCOLOR, C'40,40,50');
      ObjectSetInteger(0, "BarBG_" + currencies[i], OBJPROP_BORDER_TYPE, BORDER_FLAT);
      
      // Strength bar
      ObjectCreate(0, "Bar_" + currencies[i], OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "Bar_" + currencies[i], OBJPROP_XDISTANCE, x + 85);
      ObjectSetInteger(0, "Bar_" + currencies[i], OBJPROP_YDISTANCE, y + 3);
      ObjectSetInteger(0, "Bar_" + currencies[i], OBJPROP_XSIZE, 50);
      ObjectSetInteger(0, "Bar_" + currencies[i], OBJPROP_YSIZE, 12);
      ObjectSetInteger(0, "Bar_" + currencies[i], OBJPROP_BGCOLOR, clrGray);
      ObjectSetInteger(0, "Bar_" + currencies[i], OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }
   
   // Trading section
   ObjectCreate(0, "TradingSection", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TradingSection", OBJPROP_XDISTANCE, DashboardX + 10);
   ObjectSetInteger(0, "TradingSection", OBJPROP_YDISTANCE, DashboardY + 230);
   ObjectSetInteger(0, "TradingSection", OBJPROP_XSIZE, 430);
   ObjectSetInteger(0, "TradingSection", OBJPROP_YSIZE, 80);
   ObjectSetInteger(0, "TradingSection", OBJPROP_BGCOLOR, C'35,35,45');
   ObjectSetInteger(0, "TradingSection", OBJPROP_BORDER_COLOR, C'60,60,70');
   ObjectSetInteger(0, "TradingSection", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   
   // Trading header
   ObjectCreate(0, "TradingHeader", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TradingHeader", OBJPROP_XDISTANCE, DashboardX + 20);
   ObjectSetInteger(0, "TradingHeader", OBJPROP_YDISTANCE, DashboardY + 240);
   ObjectSetString(0, "TradingHeader", OBJPROP_TEXT, "⚡ TRADING CONTROL");
   ObjectSetInteger(0, "TradingHeader", OBJPROP_COLOR, C'255,215,0');
   ObjectSetInteger(0, "TradingHeader", OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, "TradingHeader", OBJPROP_FONT, "Arial Bold");
   
   // Auto trading button with better styling
   ObjectCreate(0, ButtonAutoTrade, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, ButtonAutoTrade, OBJPROP_XDISTANCE, DashboardX + 20);
   ObjectSetInteger(0, ButtonAutoTrade, OBJPROP_YDISTANCE, DashboardY + 265);
   ObjectSetInteger(0, ButtonAutoTrade, OBJPROP_XSIZE, 150);
   ObjectSetInteger(0, ButtonAutoTrade, OBJPROP_YSIZE, 35);
   ObjectSetString(0, ButtonAutoTrade, OBJPROP_TEXT, "🔄 AUTO TRADING: ON");
   ObjectSetInteger(0, ButtonAutoTrade, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, ButtonAutoTrade, OBJPROP_BGCOLOR, C'34,139,34');
   ObjectSetString(0, ButtonAutoTrade, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, ButtonAutoTrade, OBJPROP_FONTSIZE, 9);
   
   // Trading stats
   ObjectCreate(0, "TradingStats", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TradingStats", OBJPROP_XDISTANCE, DashboardX + 190);
   ObjectSetInteger(0, "TradingStats", OBJPROP_YDISTANCE, DashboardY + 270);
   ObjectSetString(0, "TradingStats", OBJPROP_TEXT, "📈 Trades Today: 0 | 💰 P&L: $0.00");
   ObjectSetInteger(0, "TradingStats", OBJPROP_COLOR, clrCyan);
   ObjectSetInteger(0, "TradingStats", OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, "TradingStats", OBJPROP_FONT, "Arial");
   
   ObjectCreate(0, "RiskInfo", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "RiskInfo", OBJPROP_XDISTANCE, DashboardX + 190);
   ObjectSetInteger(0, "RiskInfo", OBJPROP_YDISTANCE, DashboardY + 285);
   ObjectSetString(0, "RiskInfo", OBJPROP_TEXT, "⚠️ Risk: 1.0% | RR: 1:2.0");
   ObjectSetInteger(0, "RiskInfo", OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, "RiskInfo", OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, "RiskInfo", OBJPROP_FONT, "Arial");
   
   // Signals section
   ObjectCreate(0, "SignalsSection", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "SignalsSection", OBJPROP_XDISTANCE, DashboardX + 10);
   ObjectSetInteger(0, "SignalsSection", OBJPROP_YDISTANCE, DashboardY + 320);
   ObjectSetInteger(0, "SignalsSection", OBJPROP_XSIZE, 430);
   ObjectSetInteger(0, "SignalsSection", OBJPROP_YSIZE, 200);
   ObjectSetInteger(0, "SignalsSection", OBJPROP_BGCOLOR, C'35,35,45');
   ObjectSetInteger(0, "SignalsSection", OBJPROP_BORDER_COLOR, C'60,60,70');
   ObjectSetInteger(0, "SignalsSection", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   
   // Signals header
   ObjectCreate(0, "SignalsHeader", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "SignalsHeader", OBJPROP_XDISTANCE, DashboardX + 20);
   ObjectSetInteger(0, "SignalsHeader", OBJPROP_YDISTANCE, DashboardY + 330);
   ObjectSetString(0, "SignalsHeader", OBJPROP_TEXT, "🎯 TRADING SIGNALS");
   ObjectSetInteger(0, "SignalsHeader", OBJPROP_COLOR, C'255,215,0');
   ObjectSetInteger(0, "SignalsHeader", OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, "SignalsHeader", OBJPROP_FONT, "Arial Bold");
   
   // Signal entries with improved layout
   for(int i = 0; i < 6; i++)
   {
      // Signal background
      ObjectCreate(0, "SignalBG_" + IntegerToString(i), OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "SignalBG_" + IntegerToString(i), OBJPROP_XDISTANCE, DashboardX + 15);
      ObjectSetInteger(0, "SignalBG_" + IntegerToString(i), OBJPROP_YDISTANCE, DashboardY + 355 + i * 25);
      ObjectSetInteger(0, "SignalBG_" + IntegerToString(i), OBJPROP_XSIZE, 420);
      ObjectSetInteger(0, "SignalBG_" + IntegerToString(i), OBJPROP_YSIZE, 20);
      ObjectSetInteger(0, "SignalBG_" + IntegerToString(i), OBJPROP_BGCOLOR, C'45,45,55');
      ObjectSetInteger(0, "SignalBG_" + IntegerToString(i), OBJPROP_BORDER_TYPE, BORDER_FLAT);
      
      // Signal text
      ObjectCreate(0, "Signal_" + IntegerToString(i), OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "Signal_" + IntegerToString(i), OBJPROP_XDISTANCE, DashboardX + 25);
      ObjectSetInteger(0, "Signal_" + IntegerToString(i), OBJPROP_YDISTANCE, DashboardY + 358 + i * 25);
      ObjectSetString(0, "Signal_" + IntegerToString(i), OBJPROP_TEXT, "⏳ Scanning for signals...");
      ObjectSetInteger(0, "Signal_" + IntegerToString(i), OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, "Signal_" + IntegerToString(i), OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, "Signal_" + IntegerToString(i), OBJPROP_FONT, "Arial");
   }
   
   // Market info section
   ObjectCreate(0, "MarketSection", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "MarketSection", OBJPROP_XDISTANCE, DashboardX + 10);
   ObjectSetInteger(0, "MarketSection", OBJPROP_YDISTANCE, DashboardY + 530);
   ObjectSetInteger(0, "MarketSection", OBJPROP_XSIZE, 430);
   ObjectSetInteger(0, "MarketSection", OBJPROP_YSIZE, 110);
   ObjectSetInteger(0, "MarketSection", OBJPROP_BGCOLOR, C'35,35,45');
   ObjectSetInteger(0, "MarketSection", OBJPROP_BORDER_COLOR, C'60,60,70');
   ObjectSetInteger(0, "MarketSection", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   
   // Market header
   ObjectCreate(0, "MarketHeader", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "MarketHeader", OBJPROP_XDISTANCE, DashboardX + 20);
   ObjectSetInteger(0, "MarketHeader", OBJPROP_YDISTANCE, DashboardY + 540);
   ObjectSetString(0, "MarketHeader", OBJPROP_TEXT, "📈 MARKET STATUS");
   ObjectSetInteger(0, "MarketHeader", OBJPROP_COLOR, C'255,215,0');
   ObjectSetInteger(0, "MarketHeader", OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, "MarketHeader", OBJPROP_FONT, "Arial Bold");
   
   // Market info labels
   ObjectCreate(0, "MarketTime", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "MarketTime", OBJPROP_XDISTANCE, DashboardX + 20);
   ObjectSetInteger(0, "MarketTime", OBJPROP_YDISTANCE, DashboardY + 565);
   ObjectSetString(0, "MarketTime", OBJPROP_TEXT, "🕐 Market Time: --:--");
   ObjectSetInteger(0, "MarketTime", OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, "MarketTime", OBJPROP_FONTSIZE, 8);
   
   ObjectCreate(0, "Spread", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "Spread", OBJPROP_XDISTANCE, DashboardX + 20);
   ObjectSetInteger(0, "Spread", OBJPROP_YDISTANCE, DashboardY + 580);
   ObjectSetString(0, "Spread", OBJPROP_TEXT, "📊 Avg Spread: -- pips");
   ObjectSetInteger(0, "Spread", OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, "Spread", OBJPROP_FONTSIZE, 8);
   
   ObjectCreate(0, "Balance", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "Balance", OBJPROP_XDISTANCE, DashboardX + 20);
   ObjectSetInteger(0, "Balance", OBJPROP_YDISTANCE, DashboardY + 595);
   ObjectSetString(0, "Balance", OBJPROP_TEXT, "💰 Account: $0.00");
   ObjectSetInteger(0, "Balance", OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, "Balance", OBJPROP_FONTSIZE, 8);
   
   ObjectCreate(0, "SessionInfo", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "SessionInfo", OBJPROP_XDISTANCE, DashboardX + 230);
   ObjectSetInteger(0, "SessionInfo", OBJPROP_YDISTANCE, DashboardY + 565);
   ObjectSetString(0, "SessionInfo", OBJPROP_TEXT, "🌍 Session: LONDON");
   ObjectSetInteger(0, "SessionInfo", OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, "SessionInfo", OBJPROP_FONTSIZE, 8);
   
   ObjectCreate(0, "Volatility", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "Volatility", OBJPROP_XDISTANCE, DashboardX + 230);
   ObjectSetInteger(0, "Volatility", OBJPROP_YDISTANCE, DashboardY + 580);
   ObjectSetString(0, "Volatility", OBJPROP_TEXT, "⚡ Volatility: MEDIUM");
   ObjectSetInteger(0, "Volatility", OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, "Volatility", OBJPROP_FONTSIZE, 8);
   
   ObjectCreate(0, "Version", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "Version", OBJPROP_XDISTANCE, DashboardX + 230);
   ObjectSetInteger(0, "Version", OBJPROP_YDISTANCE, DashboardY + 595);
   ObjectSetString(0, "Version", OBJPROP_TEXT, "🔧 v2.01 | Debug: ON");
   ObjectSetInteger(0, "Version", OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, "Version", OBJPROP_FONTSIZE, 8);
}

void UpdateDashboard()
{
   // Update currency strengths with bars
   string currencies[] = {"USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD"};
   double strengths[] = {CurrentStrength.USD, CurrentStrength.EUR, CurrentStrength.GBP, CurrentStrength.JPY,
                        CurrentStrength.CHF, CurrentStrength.CAD, CurrentStrength.AUD, CurrentStrength.NZD};
   
   for(int i = 0; i < 8; i++)
   {
      // Update strength value
      string text = DoubleToString(strengths[i], 1);
      color text_color = (strengths[i] > 3.0) ? clrLime : (strengths[i] < -3.0) ? clrRed : clrWhite;
      
      ObjectSetString(0, "Strength_" + currencies[i], OBJPROP_TEXT, text);
      ObjectSetInteger(0, "Strength_" + currencies[i], OBJPROP_COLOR, text_color);
      
      // Update strength bar
      double normalized = MathMax(-10, MathMin(10, strengths[i])); // Clamp to -10,+10
      int bar_width = (int)(50 + (normalized * 5)); // 50 is center, +/- 50 pixels
      bar_width = MathMax(5, MathMin(95, bar_width));
      
      color bar_color;
      if(strengths[i] > 5.0) bar_color = clrLime;
      else if(strengths[i] > 2.0) bar_color = clrGreen;
      else if(strengths[i] > -2.0) bar_color = clrGray;
      else if(strengths[i] > -5.0) bar_color = clrOrange;
      else bar_color = clrRed;
      
      ObjectSetInteger(0, "Bar_" + currencies[i], OBJPROP_XSIZE, bar_width);
      ObjectSetInteger(0, "Bar_" + currencies[i], OBJPROP_BGCOLOR, bar_color);
   }
   
   // Update auto trading button
   string button_text = AutoTrading ? "🔄 AUTO TRADING: ON" : "⏸️ AUTO TRADING: OFF";
   color button_color = AutoTrading ? C'34,139,34' : clrRed;
   ObjectSetString(0, ButtonAutoTrade, OBJPROP_TEXT, button_text);
   ObjectSetInteger(0, ButtonAutoTrade, OBJPROP_BGCOLOR, button_color);
   
   // Update signals with better formatting
   int active_signals = 0;
   for(int i = 0; i < ArraySize(Signals); i++)
   {
      if(Signals[i].signal_type != 0 && active_signals < 6)
      {
         string signal_icon = (Signals[i].signal_type == 1) ? "🟢 BUY" : "🔴 SELL";
         string signal_text = StringFormat("%s %s | Confidence: %.0f%% | %s", 
                                         signal_icon,
                                         Signals[i].symbol, 
                                         Signals[i].confidence_score,
                                         TimeToString(TimeCurrent(), TIME_MINUTES));
         
         color signal_color = (Signals[i].signal_type == 1) ? clrLime : clrRed;
         color bg_color = (Signals[i].signal_type == 1) ? C'0,50,0' : C'50,0,0';
         
         ObjectSetString(0, "Signal_" + IntegerToString(active_signals), OBJPROP_TEXT, signal_text);
         ObjectSetInteger(0, "Signal_" + IntegerToString(active_signals), OBJPROP_COLOR, signal_color);
         ObjectSetInteger(0, "SignalBG_" + IntegerToString(active_signals), OBJPROP_BGCOLOR, bg_color);
         active_signals++;
      }
   }
   
   // Clear remaining signal slots
   for(int i = active_signals; i < 6; i++)
   {
      ObjectSetString(0, "Signal_" + IntegerToString(i), OBJPROP_TEXT, "⏳ Scanning for signals...");
      ObjectSetInteger(0, "Signal_" + IntegerToString(i), OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, "SignalBG_" + IntegerToString(i), OBJPROP_BGCOLOR, C'45,45,55');
   }
   
   // Update trading stats
   int total_trades = 0;
   for(int i = 0; i < ArraySize(Symbols); i++)
   {
      total_trades += DailyTrades[i][0] + DailyTrades[i][1];
   }
   
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double account_profit = AccountInfoDouble(ACCOUNT_PROFIT);
   
   string stats_text = StringFormat("📈 Trades Today: %d | 💰 P&L: $%.2f", total_trades, account_profit);
   ObjectSetString(0, "TradingStats", OBJPROP_TEXT, stats_text);
   
   string risk_text = StringFormat("⚠️ Risk: %.1f%% | RR: 1:%.1f", RiskPercent, RiskReward);
   ObjectSetString(0, "RiskInfo", OBJPROP_TEXT, risk_text);
   
   // Update market information
   string market_time = TimeToString(TimeCurrent(), TIME_MINUTES);
   ObjectSetString(0, "MarketTime", OBJPROP_TEXT, "🕐 Market Time: " + market_time);
   
   // Calculate average spread
   double avg_spread = 0;
   int spread_count = 0;
   for(int i = 0; i < ArraySize(Symbols); i++)
   {
      string symbol = Symbols[i];
      if(SymbolSelect(symbol, true))
      {
         double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
         avg_spread += spread / GetPipValue(symbol);
         spread_count++;
      }
   }
   if(spread_count > 0) avg_spread /= spread_count;
   
   ObjectSetString(0, "Spread", OBJPROP_TEXT, StringFormat("📊 Avg Spread: %.1f pips", avg_spread));
   
   string balance_text = StringFormat("💰 Account: $%.2f", account_balance);
   ObjectSetString(0, "Balance", OBJPROP_TEXT, balance_text);
   
   // Determine trading session
   MqlDateTime gmt_struct;
   TimeToStruct(TimeGMT(), gmt_struct);
   int hour = gmt_struct.hour;
   string session = "CLOSED";
   if(hour >= 22 || hour < 7) session = "SYDNEY";
   else if(hour >= 0 && hour < 9) session = "TOKYO";
   else if(hour >= 7 && hour < 16) session = "LONDON";
   else if(hour >= 13 && hour < 22) session = "NEW YORK";
   
   ObjectSetString(0, "SessionInfo", OBJPROP_TEXT, "🌍 Session: " + session);
   
   // Volatility assessment based on recent price movements
   string volatility = "LOW";
   double total_movement = 0;
   int movement_count = 0;
   
   for(int i = 0; i < ArraySize(Symbols); i++)
   {
      string symbol = Symbols[i];
      if(SymbolSelect(symbol, true))
      {
         double current = SymbolInfoDouble(symbol, SYMBOL_BID);
         double past = iClose(symbol, PERIOD_H1, 1);
         if(past > 0)
         {
            total_movement += MathAbs(current - past) / past * 100;
            movement_count++;
         }
      }
   }
   
   if(movement_count > 0)
   {
      total_movement /= movement_count;
      if(total_movement > 0.5) volatility = "HIGH";
      else if(total_movement > 0.2) volatility = "MEDIUM";
   }
   
   color vol_color = (volatility == "HIGH") ? clrRed : (volatility == "MEDIUM") ? clrOrange : clrLime;
   ObjectSetString(0, "Volatility", OBJPROP_TEXT, "⚡ Volatility: " + volatility);
   ObjectSetInteger(0, "Volatility", OBJPROP_COLOR, vol_color);
   
   // Update version info
   string debug_status = DebugMode ? "ON" : "OFF";
   ObjectSetString(0, "Version", OBJPROP_TEXT, "🔧 v2.01 | Debug: " + debug_status);
   
   ChartRedraw(0);
}

void RemoveDashboard()
{
   // Remove main panels
   ObjectDelete(0, PanelName);
   ObjectDelete(0, "HeaderBG");
   ObjectDelete(0, "TradingSection");
   ObjectDelete(0, "SignalsSection");
   ObjectDelete(0, "MarketSection");
   
   // Remove headers and indicators
   ObjectDelete(0, "Title_v2");
   ObjectDelete(0, "StatusIndicator");
   ObjectDelete(0, "StrengthHeader");
   ObjectDelete(0, "TradingHeader");
   ObjectDelete(0, "SignalsHeader");
   ObjectDelete(0, "MarketHeader");
   
   // Remove trading controls
   ObjectDelete(0, ButtonAutoTrade);
   ObjectDelete(0, "TradingStats");
   ObjectDelete(0, "RiskInfo");
   
   // Remove currency strength elements
   string currencies[] = {"USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD"};
   for(int i = 0; i < 8; i++)
   {
      ObjectDelete(0, "Currency_" + currencies[i]);
      ObjectDelete(0, "Strength_" + currencies[i]);
      ObjectDelete(0, "BarBG_" + currencies[i]);
      ObjectDelete(0, "Bar_" + currencies[i]);
   }
   
   // Remove signals
   for(int i = 0; i < 6; i++)
   {
      ObjectDelete(0, "Signal_" + IntegerToString(i));
      ObjectDelete(0, "SignalBG_" + IntegerToString(i));
   }
   
   // Remove market info
   ObjectDelete(0, "MarketTime");
   ObjectDelete(0, "Spread");
   ObjectDelete(0, "Balance");
   ObjectDelete(0, "SessionInfo");
   ObjectDelete(0, "Volatility");
   ObjectDelete(0, "Version");
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Event handlers                                                   |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == ButtonAutoTrade)
      {
         AutoTrading = !AutoTrading;
         ObjectSetInteger(0, ButtonAutoTrade, OBJPROP_STATE, false);
         UpdateDashboard();
         Print("🔄 Auto Trading ", AutoTrading ? "ENABLED" : "DISABLED");
      }
   }
}

void OnTimer()
{
   static datetime last_day = 0;
   datetime current_day = TimeCurrent() - (TimeCurrent() % 86400);
   
   if(current_day != last_day)
   {
      for(int i = 0; i < ArraySize(Symbols); i++)
      {
         DailyTrades[i][0] = 0;
         DailyTrades[i][1] = 0;
      }
      last_day = current_day;
      Print("🔄 Daily trade counters reset");
   }
} 