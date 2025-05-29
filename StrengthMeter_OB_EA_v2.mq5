//+------------------------------------------------------------------+
//|                                      StrengthMeter_OB_EA_v2.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "2.00"
#property description "Advanced Strength Meter + Order Block EA v2.0 with SMC"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Input parameters
input group "=== TRADING SETTINGS ==="
input double   RiskPercent = 1.0;           // Risk per trade (% of balance)
input double   RiskReward = 2.0;            // Risk to Reward ratio
input int      StopLossPips = 10;           // Stop Loss in pips beyond OB
input int      MaxTradesPerPair = 2;        // Max trades per pair per day
input bool     AutoTradingInput = true;     // Auto Trading ON/OFF (initial setting)

input group "=== STRENGTH METER v2.0 ==="
input double   MinStrengthDiff = 5.0;       // Minimum strength difference
input int      StrengthPeriod = 14;         // Period for strength calculation
input bool     UseCorrelationFilter = true; // Use correlation analysis
input bool     UseMomentumFilter = true;    // Use momentum indicators
input int      StrengthSmoothPeriod = 3;    // Smoothing period

input group "=== ORDER BLOCK v2.0 ==="
input bool     UseMultiTimeframe = true;    // Multi-timeframe OB scanning
input bool     UseOBStrengthScore = true;   // Use OB strength scoring (0-100)
input bool     UseInstitutionalOB = true;   // 3-touch rule patterns
input bool     UseFairValueGap = true;      // Fair Value Gap integration
input bool     UseBreakerBlocks = true;     // Breaker blocks detection
input int      OB_LookbackBars = 50;        // Lookback bars for OB detection
input int      BOS_LookbackBars = 20;       // Lookback bars for BOS detection
input double   OB_MinSize = 10.0;           // Minimum OB size in pips
input double   OB_MinStrengthScore = 60.0;  // Minimum OB strength score

input group "=== LIQUIDITY ANALYSIS v2.0 ==="
input bool     UseEqualHighsLows = true;    // Equal highs/lows detection
input bool     UseLiquidityPools = true;    // Liquidity pools mapping
input bool     UseStopHuntDetection = true; // Stop hunt identification
input bool     UseSweepConfirmation = true; // Sweep confirmation patterns
input bool     UseVolumeProfile = true;     // Volume profile analysis
input int      LiquidityLookback = 100;     // Lookback for liquidity analysis

input group "=== SMART MONEY CONCEPTS ==="
input bool     UseSMC = true;               // Enable Smart Money Concepts
input bool     UseMarketStructure = true;   // Market structure analysis
input bool     UseInducement = true;        // Inducement detection
input bool     UseDisplacement = true;      // Displacement analysis
input bool     UseMitigationBlocks = true;  // Mitigation blocks
input int      SMC_LookbackBars = 200;      // SMC analysis lookback

input group "=== DASHBOARD v2.0 ==="
input int      DashboardX = 20;             // Dashboard X position
input int      DashboardY = 50;             // Dashboard Y position
input bool     ShowHeatMap = true;          // Show currency heat map
input bool     ShowCorrelationMatrix = true; // Show correlation matrix
input bool     ShowLiquidityLevels = true;  // Show liquidity levels
input color    PanelColor = clrDarkSlateGray; // Panel background color
input color    TextColor = clrWhite;        // Text color

//--- Global variables
CTrade trade;
CPositionInfo position;
COrderInfo order;

// Runtime variables
bool AutoTrading = true;

// Enhanced symbol lists with .iux suffix
string Symbols[] = {"XAUUSD.iux", "EURUSD.iux", "GBPUSD.iux", "USDJPY.iux", "GBPJPY.iux", "EURJPY.iux", "US30.iux"};

// Complete 28 pairs for comprehensive strength analysis
string AllPairs[] = {
   "EURUSD.iux", "GBPUSD.iux", "USDCHF.iux", "USDJPY.iux", "USDCAD.iux", "AUDUSD.iux", "NZDUSD.iux",
   "EURGBP.iux", "EURJPY.iux", "EURCHF.iux", "EURCAD.iux", "EURAUD.iux", "EURNZD.iux",
   "GBPJPY.iux", "GBPCHF.iux", "GBPCAD.iux", "GBPAUD.iux", "GBPNZD.iux",
   "CHFJPY.iux", "CADJPY.iux", "AUDJPY.iux", "NZDJPY.iux",
   "AUDCAD.iux", "AUDCHF.iux", "AUDNZD.iux",
   "CADCHF.iux", "NZDCAD.iux", "NZDCHF.iux"
};

// Available symbols for analysis
string AvailableSymbols[];
int AvailableSymbolsCount = 0;

//--- Enhanced structures
struct AdvancedStrengthData
{
   double USD, EUR, GBP, JPY, CHF, CAD, AUD, NZD;
   double USD_momentum, EUR_momentum, GBP_momentum, JPY_momentum;
   double CHF_momentum, CAD_momentum, AUD_momentum, NZD_momentum;
   double correlation_matrix[8][8];
   datetime last_update;
};

struct EnhancedOrderBlock
{
   double high, low, open, close;
   datetime time;
   bool is_bullish;
   bool valid;
   double strength_score;        // 0-100 rating
   int touch_count;             // For 3-touch rule
   bool is_institutional;       // Institutional pattern
   bool has_fvg;               // Fair Value Gap
   bool is_breaker;            // Breaker block
   ENUM_TIMEFRAMES timeframe;   // Source timeframe
   bool is_mitigated;          // SMC mitigation
};

struct LiquidityLevel
{
   double price;
   datetime time;
   bool is_high;               // true for high, false for low
   bool is_equal;              // Equal high/low
   bool is_swept;              // Already swept
   int touch_count;            // Number of touches
   double volume;              // Volume at level
};

struct SMCStructure
{
   bool bullish_bos;           // Bullish break of structure
   bool bearish_bos;           // Bearish break of structure
   double inducement_high;     // Inducement level
   double inducement_low;      // Inducement level
   bool displacement_up;       // Bullish displacement
   bool displacement_down;     // Bearish displacement
   datetime last_structure_time;
};

struct TradeSignalV2
{
   string symbol;
   int signal_type;            // 1 = BUY, -1 = SELL, 0 = NONE
   double entry_price;
   double stop_loss;
   double take_profit;
   string reason;
   double confidence_score;    // 0-100 confidence
   EnhancedOrderBlock ob;      // Associated order block
   LiquidityLevel liquidity;   // Associated liquidity
   SMCStructure smc;          // SMC analysis
};

//--- Global data structures
AdvancedStrengthData CurrentStrength;
EnhancedOrderBlock OBDataV2[];
LiquidityLevel LiquidityLevels[];
SMCStructure SMCData[];
TradeSignalV2 SignalsV2[];
int DailyTrades[][2];

//--- Dashboard objects
string PanelName = "StrengthOB_Panel_v2";
string ButtonAutoTrade = "AutoTradeBtn_v2";
string ButtonExportLogs = "ExportLogsBtn_v2";
string ButtonSettings = "SettingsBtn_v2";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Initialize runtime variables
   AutoTrading = AutoTradingInput;
   
   //--- Detect available symbols
   DetectAvailableSymbols();
   
   //--- Initialize arrays
   ArrayResize(OBDataV2, ArraySize(Symbols));
   ArrayResize(SignalsV2, ArraySize(Symbols));
   ArrayResize(DailyTrades, ArraySize(Symbols));
   ArrayResize(SMCData, ArraySize(Symbols));
   ArrayResize(LiquidityLevels, LiquidityLookback);
   
   for(int i = 0; i < ArraySize(Symbols); i++)
   {
      DailyTrades[i][0] = 0;
      DailyTrades[i][1] = 0;
   }
   
   //--- Initialize correlation matrix
   InitializeCorrelationMatrix();
   
   //--- Create enhanced dashboard
   CreateEnhancedDashboard();
   
   //--- Set timer for updates
   EventSetTimer(1);
   
   Print("Advanced Strength Meter + OB EA v2.0 initialized successfully");
   Print("Available symbols for analysis: ", AvailableSymbolsCount);
   Print("Features enabled: SMC=", UseSMC, ", Multi-TF=", UseMultiTimeframe, ", Liquidity=", UseLiquidityPools);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   RemoveEnhancedDashboard();
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Update advanced strength meter
   CalculateAdvancedCurrencyStrength();
   
   //--- Analyze liquidity levels
   if(UseLiquidityPools) AnalyzeLiquidityLevels();
   
   //--- Perform SMC analysis
   if(UseSMC) AnalyzeSmartMoneyConcepts();
   
   //--- Scan for enhanced signals
   ScanForEnhancedSignals();
   
   //--- Update enhanced dashboard
   UpdateEnhancedDashboard();
   
   //--- Execute trades if auto trading is enabled
   if(AutoTrading)
   {
      ExecuteEnhancedSignals();
   }
}

//+------------------------------------------------------------------+
//| Detect available symbols for analysis                           |
//+------------------------------------------------------------------+
void DetectAvailableSymbols()
{
   ArrayResize(AvailableSymbols, ArraySize(AllPairs));
   AvailableSymbolsCount = 0;
   
   for(int i = 0; i < ArraySize(AllPairs); i++)
   {
      string symbol = AllPairs[i];
      
      if(SymbolSelect(symbol, true))
      {
         if(SymbolInfoDouble(symbol, SYMBOL_BID) > 0)
         {
            AvailableSymbols[AvailableSymbolsCount] = symbol;
            AvailableSymbolsCount++;
         }
      }
   }
   
   ArrayResize(AvailableSymbols, AvailableSymbolsCount);
   
   if(AvailableSymbolsCount < 10)
   {
      Print("WARNING: Only ", AvailableSymbolsCount, " symbols available. Analysis may be limited.");
   }
}

//+------------------------------------------------------------------+
//| Calculate advanced currency strength with momentum              |
//+------------------------------------------------------------------+
void CalculateAdvancedCurrencyStrength()
{
   double usd=0, eur=0, gbp=0, jpy=0, chf=0, cad=0, aud=0, nzd=0;
   double usd_mom=0, eur_mom=0, gbp_mom=0, jpy_mom=0, chf_mom=0, cad_mom=0, aud_mom=0, nzd_mom=0;
   int count = 0;
   
   for(int i = 0; i < AvailableSymbolsCount; i++)
   {
      string symbol = AvailableSymbols[i];
      
      double price_change = GetPriceChange(symbol, StrengthPeriod);
      double momentum = GetMomentum(symbol, StrengthPeriod);
      
      if(price_change == 0) continue;
      
      string base = GetBaseCurrency(symbol);
      string quote = GetQuoteCurrency(symbol);
      
      // Calculate strength
      AddCurrencyStrength(base, price_change, usd, eur, gbp, jpy, chf, cad, aud, nzd);
      SubtractCurrencyStrength(quote, price_change, usd, eur, gbp, jpy, chf, cad, aud, nzd);
      
      // Calculate momentum
      if(UseMomentumFilter)
      {
         AddCurrencyStrength(base, momentum, usd_mom, eur_mom, gbp_mom, jpy_mom, chf_mom, cad_mom, aud_mom, nzd_mom);
         SubtractCurrencyStrength(quote, momentum, usd_mom, eur_mom, gbp_mom, jpy_mom, chf_mom, cad_mom, aud_mom, nzd_mom);
      }
      
      count++;
   }
   
   if(count > 0)
   {
      // Apply smoothing
      double smooth_factor = 1.0 / StrengthSmoothPeriod;
      
      CurrentStrength.USD = SmoothValue(CurrentStrength.USD, usd / count * 100, smooth_factor);
      CurrentStrength.EUR = SmoothValue(CurrentStrength.EUR, eur / count * 100, smooth_factor);
      CurrentStrength.GBP = SmoothValue(CurrentStrength.GBP, gbp / count * 100, smooth_factor);
      CurrentStrength.JPY = SmoothValue(CurrentStrength.JPY, jpy / count * 100, smooth_factor);
      CurrentStrength.CHF = SmoothValue(CurrentStrength.CHF, chf / count * 100, smooth_factor);
      CurrentStrength.CAD = SmoothValue(CurrentStrength.CAD, cad / count * 100, smooth_factor);
      CurrentStrength.AUD = SmoothValue(CurrentStrength.AUD, aud / count * 100, smooth_factor);
      CurrentStrength.NZD = SmoothValue(CurrentStrength.NZD, nzd / count * 100, smooth_factor);
      
      // Store momentum
      if(UseMomentumFilter)
      {
         CurrentStrength.USD_momentum = usd_mom / count * 100;
         CurrentStrength.EUR_momentum = eur_mom / count * 100;
         CurrentStrength.GBP_momentum = gbp_mom / count * 100;
         CurrentStrength.JPY_momentum = jpy_mom / count * 100;
         CurrentStrength.CHF_momentum = chf_mom / count * 100;
         CurrentStrength.CAD_momentum = cad_mom / count * 100;
         CurrentStrength.AUD_momentum = aud_mom / count * 100;
         CurrentStrength.NZD_momentum = nzd_mom / count * 100;
      }
      
      CurrentStrength.last_update = TimeCurrent();
   }
   
   // Update correlation matrix
   if(UseCorrelationFilter) UpdateCorrelationMatrix();
}

//+------------------------------------------------------------------+
//| Helper functions for currency strength calculation              |
//+------------------------------------------------------------------+
void AddCurrencyStrength(string currency, double value, double &usd, double &eur, double &gbp, double &jpy, double &chf, double &cad, double &aud, double &nzd)
{
   if(currency == "USD") usd += value;
   else if(currency == "EUR") eur += value;
   else if(currency == "GBP") gbp += value;
   else if(currency == "JPY") jpy += value;
   else if(currency == "CHF") chf += value;
   else if(currency == "CAD") cad += value;
   else if(currency == "AUD") aud += value;
   else if(currency == "NZD") nzd += value;
}

void SubtractCurrencyStrength(string currency, double value, double &usd, double &eur, double &gbp, double &jpy, double &chf, double &cad, double &aud, double &nzd)
{
   if(currency == "USD") usd -= value;
   else if(currency == "EUR") eur -= value;
   else if(currency == "GBP") gbp -= value;
   else if(currency == "JPY") jpy -= value;
   else if(currency == "CHF") chf -= value;
   else if(currency == "CAD") cad -= value;
   else if(currency == "AUD") aud -= value;
   else if(currency == "NZD") nzd -= value;
}

double SmoothValue(double old_value, double new_value, double factor)
{
   return old_value + (new_value - old_value) * factor;
}

//+------------------------------------------------------------------+
//| Get price change percentage                                      |
//+------------------------------------------------------------------+
double GetPriceChange(string symbol, int period)
{
   double current_price = SymbolInfoDouble(symbol, SYMBOL_BID);
   double past_price = iClose(symbol, PERIOD_H1, period);
   
   if(past_price == 0) return 0;
   
   return (current_price - past_price) / past_price * 100;
}

//+------------------------------------------------------------------+
//| Get momentum indicator                                           |
//+------------------------------------------------------------------+
double GetMomentum(string symbol, int period)
{
   double current_price = SymbolInfoDouble(symbol, SYMBOL_BID);
   double past_price = iClose(symbol, PERIOD_H1, period / 2);
   double older_price = iClose(symbol, PERIOD_H1, period);
   
   if(past_price == 0 || older_price == 0) return 0;
   
   double recent_change = (current_price - past_price) / past_price;
   double older_change = (past_price - older_price) / older_price;
   
   return (recent_change - older_change) * 100;
}

//+------------------------------------------------------------------+
//| Initialize correlation matrix                                    |
//+------------------------------------------------------------------+
void InitializeCorrelationMatrix()
{
   for(int i = 0; i < 8; i++)
   {
      for(int j = 0; j < 8; j++)
      {
         CurrentStrength.correlation_matrix[i][j] = (i == j) ? 1.0 : 0.0;
      }
   }
}

//+------------------------------------------------------------------+
//| Update correlation matrix                                        |
//+------------------------------------------------------------------+
void UpdateCorrelationMatrix()
{
   // Simplified correlation calculation
   // In a full implementation, this would use historical price data
   double currencies[] = {CurrentStrength.USD, CurrentStrength.EUR, CurrentStrength.GBP, CurrentStrength.JPY,
                         CurrentStrength.CHF, CurrentStrength.CAD, CurrentStrength.AUD, CurrentStrength.NZD};
   
   for(int i = 0; i < 8; i++)
   {
      for(int j = 0; j < 8; j++)
      {
         if(i != j)
         {
            // Simple correlation based on current strength values
            double correlation = 1.0 - MathAbs(currencies[i] - currencies[j]) / 10.0;
            correlation = MathMax(-1.0, MathMin(1.0, correlation));
            CurrentStrength.correlation_matrix[i][j] = correlation;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get currency strength                                            |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Get base currency (handle .iux suffix)                          |
//+------------------------------------------------------------------+
string GetBaseCurrency(string symbol)
{
   string clean_symbol = symbol;
   if(StringFind(symbol, ".iux") >= 0)
      clean_symbol = StringSubstr(symbol, 0, StringFind(symbol, ".iux"));
   
   if(StringLen(clean_symbol) >= 6)
      return StringSubstr(clean_symbol, 0, 3);
   return "";
}

//+------------------------------------------------------------------+
//| Get quote currency (handle .iux suffix)                         |
//+------------------------------------------------------------------+
string GetQuoteCurrency(string symbol)
{
   string clean_symbol = symbol;
   if(StringFind(symbol, ".iux") >= 0)
      clean_symbol = StringSubstr(symbol, 0, StringFind(symbol, ".iux"));
   
   if(StringLen(clean_symbol) >= 6)
      return StringSubstr(clean_symbol, 3, 3);
   return "";
}

// Placeholder functions - will be implemented in next parts
void AnalyzeLiquidityLevels() { /* Implementation coming */ }
void AnalyzeSmartMoneyConcepts() { /* Implementation coming */ }
void ScanForEnhancedSignals() { /* Implementation coming */ }
void ExecuteEnhancedSignals() { /* Implementation coming */ }
void CreateEnhancedDashboard() { /* Implementation coming */ }
void UpdateEnhancedDashboard() { /* Implementation coming */ }
void RemoveEnhancedDashboard() { /* Implementation coming */ } 