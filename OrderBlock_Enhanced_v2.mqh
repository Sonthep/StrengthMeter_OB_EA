//+------------------------------------------------------------------+
//|                                      OrderBlock_Enhanced_v2.mqh |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "2.00"
#property description "Advanced Order Block Detection Library v2.0 with SMC"

//+------------------------------------------------------------------+
//| Enhanced Order Block Detection Class v2.0                       |
//+------------------------------------------------------------------+
class COrderBlockDetectorV2
{
private:
   // Multi-timeframe data
   ENUM_TIMEFRAMES m_timeframes[4];
   int             m_tf_count;
   
   // Detection parameters
   int             m_lookback_bars;
   int             m_bos_lookback;
   double          m_min_ob_size;
   double          m_min_strength_score;
   
   // SMC parameters
   bool            m_use_smc;
   bool            m_use_institutional;
   bool            m_use_fvg;
   bool            m_use_breaker;
   
   // Internal arrays
   double          m_highs[];
   double          m_lows[];
   double          m_opens[];
   double          m_closes[];
   datetime        m_times[];
   long            m_volumes[];
   
public:
   //--- Constructor
   COrderBlockDetectorV2(void);
   ~COrderBlockDetectorV2(void);
   
   //--- Initialization
   bool Initialize(int lookback, int bos_lookback, double min_size, double min_score);
   void SetMultiTimeframe(bool enable);
   void SetSMCFeatures(bool smc, bool institutional, bool fvg, bool breaker);
   
   //--- Main detection functions
   bool DetectOrderBlocks(string symbol, EnhancedOrderBlock &ob_array[]);
   bool DetectMultiTimeframeOB(string symbol, EnhancedOrderBlock &ob_array[]);
   
   //--- Order Block analysis
   double CalculateOBStrengthScore(string symbol, EnhancedOrderBlock &ob);
   bool IsInstitutionalPattern(string symbol, EnhancedOrderBlock &ob);
   bool HasFairValueGap(string symbol, EnhancedOrderBlock &ob);
   bool IsBreakerBlock(string symbol, EnhancedOrderBlock &ob);
   
   //--- Break of Structure detection
   bool DetectBOS(string symbol, ENUM_TIMEFRAMES timeframe, bool &bullish_bos, bool &bearish_bos);
   bool DetectDisplacement(string symbol, ENUM_TIMEFRAMES timeframe, double &displacement_size);
   
   //--- Liquidity analysis
   bool DetectLiquiditySweep(string symbol, ENUM_TIMEFRAMES timeframe, double &sweep_level);
   bool DetectEqualHighsLows(string symbol, double &equal_high, double &equal_low);
   bool DetectStopHunt(string symbol, double &hunt_level);
   
   //--- Volume analysis
   double GetVolumeAtLevel(string symbol, double price_level, int bars_back);
   bool IsHighVolumeOB(string symbol, EnhancedOrderBlock &ob);
   
   //--- Validation functions
   bool ValidateOBIntegrity(string symbol, EnhancedOrderBlock &ob);
   bool IsOBMitigated(string symbol, EnhancedOrderBlock &ob);
   void UpdateOBStatus(string symbol, EnhancedOrderBlock &ob_array[]);
   
   //--- Utility functions
   double GetPipValue(string symbol);
   double CalculateOBSize(EnhancedOrderBlock &ob, string symbol);
   color GetOBColor(EnhancedOrderBlock &ob);
   string GetOBDescription(EnhancedOrderBlock &ob);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
COrderBlockDetectorV2::COrderBlockDetectorV2(void)
{
   // Initialize timeframes for multi-TF analysis
   m_timeframes[0] = PERIOD_M1;
   m_timeframes[1] = PERIOD_M5;
   m_timeframes[2] = PERIOD_M15;
   m_timeframes[3] = PERIOD_H1;
   m_tf_count = 4;
   
   // Default parameters
   m_lookback_bars = 50;
   m_bos_lookback = 20;
   m_min_ob_size = 10.0;
   m_min_strength_score = 60.0;
   
   // SMC features
   m_use_smc = true;
   m_use_institutional = true;
   m_use_fvg = true;
   m_use_breaker = true;
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
COrderBlockDetectorV2::~COrderBlockDetectorV2(void)
{
   ArrayFree(m_highs);
   ArrayFree(m_lows);
   ArrayFree(m_opens);
   ArrayFree(m_closes);
   ArrayFree(m_times);
   ArrayFree(m_volumes);
}

//+------------------------------------------------------------------+
//| Initialize detector                                              |
//+------------------------------------------------------------------+
bool COrderBlockDetectorV2::Initialize(int lookback, int bos_lookback, double min_size, double min_score)
{
   m_lookback_bars = lookback;
   m_bos_lookback = bos_lookback;
   m_min_ob_size = min_size;
   m_min_strength_score = min_score;
   
   // Resize arrays
   ArrayResize(m_highs, m_lookback_bars);
   ArrayResize(m_lows, m_lookback_bars);
   ArrayResize(m_opens, m_lookback_bars);
   ArrayResize(m_closes, m_lookback_bars);
   ArrayResize(m_times, m_lookback_bars);
   ArrayResize(m_volumes, m_lookback_bars);
   
   return true;
}

//+------------------------------------------------------------------+
//| Set multi-timeframe analysis                                    |
//+------------------------------------------------------------------+
void COrderBlockDetectorV2::SetMultiTimeframe(bool enable)
{
   if(enable)
   {
      m_tf_count = 4;
   }
   else
   {
      m_tf_count = 1;
      m_timeframes[0] = PERIOD_M5; // Default to M5
   }
}

//+------------------------------------------------------------------+
//| Set SMC features                                                |
//+------------------------------------------------------------------+
void COrderBlockDetectorV2::SetSMCFeatures(bool smc, bool institutional, bool fvg, bool breaker)
{
   m_use_smc = smc;
   m_use_institutional = institutional;
   m_use_fvg = fvg;
   m_use_breaker = breaker;
}

//+------------------------------------------------------------------+
//| Detect Order Blocks with enhanced features                      |
//+------------------------------------------------------------------+
bool COrderBlockDetectorV2::DetectOrderBlocks(string symbol, EnhancedOrderBlock &ob_array[])
{
   if(m_tf_count > 1)
   {
      return DetectMultiTimeframeOB(symbol, ob_array);
   }
   
   ENUM_TIMEFRAMES timeframe = PERIOD_M5;
   
   // Load price data
   for(int i = 0; i < m_lookback_bars; i++)
   {
      m_highs[i] = iHigh(symbol, timeframe, i);
      m_lows[i] = iLow(symbol, timeframe, i);
      m_opens[i] = iOpen(symbol, timeframe, i);
      m_closes[i] = iClose(symbol, timeframe, i);
      m_times[i] = iTime(symbol, timeframe, i);
      m_volumes[i] = iTickVolume(symbol, timeframe, i);
   }
   
   // Detect BOS first
   bool bullish_bos = false, bearish_bos = false;
   DetectBOS(symbol, timeframe, bullish_bos, bearish_bos);
   
   int ob_count = 0;
   ArrayResize(ob_array, 0);
   
   // Scan for order blocks
   for(int i = m_bos_lookback; i < m_lookback_bars - 5; i++)
   {
      // Look for bullish order blocks (after bearish BOS)
      if(bearish_bos && m_closes[i] < m_opens[i]) // Bearish candle
      {
         bool is_ob = true;
         
         // Check if price broke below this candle and then returned
         for(int j = i - 1; j >= 1; j--)
         {
            if(m_lows[j] < m_lows[i]) // Break below
            {
               // Check for return and bounce
               for(int k = j - 1; k >= 0; k--)
               {
                  if(m_lows[k] >= m_lows[i] && m_closes[k] > m_opens[k])
                  {
                     // Found potential bullish OB
                     EnhancedOrderBlock ob;
                     ob.high = m_highs[i];
                     ob.low = m_lows[i];
                     ob.open = m_opens[i];
                     ob.close = m_closes[i];
                     ob.time = m_times[i];
                     ob.is_bullish = true;
                     ob.valid = true;
                     ob.timeframe = timeframe;
                     ob.touch_count = 1;
                     ob.is_mitigated = false;
                     
                     // Calculate strength score
                     ob.strength_score = CalculateOBStrengthScore(symbol, ob);
                     
                     // Enhanced analysis
                     if(m_use_institutional)
                        ob.is_institutional = IsInstitutionalPattern(symbol, ob);
                     
                     if(m_use_fvg)
                        ob.has_fvg = HasFairValueGap(symbol, ob);
                     
                     if(m_use_breaker)
                        ob.is_breaker = IsBreakerBlock(symbol, ob);
                     
                     // Validate OB
                     if(ValidateOBIntegrity(symbol, ob) && ob.strength_score >= m_min_strength_score)
                     {
                        ArrayResize(ob_array, ob_count + 1);
                        ob_array[ob_count] = ob;
                        ob_count++;
                     }
                     break;
                  }
               }
               break;
            }
         }
      }
      
      // Look for bearish order blocks (after bullish BOS)
      if(bullish_bos && m_closes[i] > m_opens[i]) // Bullish candle
      {
         bool is_ob = true;
         
         // Check if price broke above this candle and then returned
         for(int j = i - 1; j >= 1; j--)
         {
            if(m_highs[j] > m_highs[i]) // Break above
            {
               // Check for return and rejection
               for(int k = j - 1; k >= 0; k--)
               {
                  if(m_highs[k] <= m_highs[i] && m_closes[k] < m_opens[k])
                  {
                     // Found potential bearish OB
                     EnhancedOrderBlock ob;
                     ob.high = m_highs[i];
                     ob.low = m_lows[i];
                     ob.open = m_opens[i];
                     ob.close = m_closes[i];
                     ob.time = m_times[i];
                     ob.is_bullish = false;
                     ob.valid = true;
                     ob.timeframe = timeframe;
                     ob.touch_count = 1;
                     ob.is_mitigated = false;
                     
                     // Calculate strength score
                     ob.strength_score = CalculateOBStrengthScore(symbol, ob);
                     
                     // Enhanced analysis
                     if(m_use_institutional)
                        ob.is_institutional = IsInstitutionalPattern(symbol, ob);
                     
                     if(m_use_fvg)
                        ob.has_fvg = HasFairValueGap(symbol, ob);
                     
                     if(m_use_breaker)
                        ob.is_breaker = IsBreakerBlock(symbol, ob);
                     
                     // Validate OB
                     if(ValidateOBIntegrity(symbol, ob) && ob.strength_score >= m_min_strength_score)
                     {
                        ArrayResize(ob_array, ob_count + 1);
                        ob_array[ob_count] = ob;
                        ob_count++;
                     }
                     break;
                  }
               }
               break;
            }
         }
      }
   }
   
   return ob_count > 0;
}

//+------------------------------------------------------------------+
//| Detect multi-timeframe order blocks                             |
//+------------------------------------------------------------------+
bool COrderBlockDetectorV2::DetectMultiTimeframeOB(string symbol, EnhancedOrderBlock &ob_array[])
{
   int total_obs = 0;
   ArrayResize(ob_array, 0);
   
   // Scan each timeframe
   for(int tf = 0; tf < m_tf_count; tf++)
   {
      ENUM_TIMEFRAMES timeframe = m_timeframes[tf];
      EnhancedOrderBlock tf_obs[];
      
      // Temporarily set single timeframe for detection
      int original_tf_count = m_tf_count;
      m_tf_count = 1;
      m_timeframes[0] = timeframe;
      
      // Detect OBs on this timeframe
      if(DetectOrderBlocks(symbol, tf_obs))
      {
         // Add to main array with timeframe weighting
         for(int i = 0; i < ArraySize(tf_obs); i++)
         {
            tf_obs[i].timeframe = timeframe;
            
            // Apply timeframe multiplier to strength score
            double tf_multiplier = 1.0;
            switch(timeframe)
            {
               case PERIOD_H1:  tf_multiplier = 1.5; break;
               case PERIOD_M15: tf_multiplier = 1.2; break;
               case PERIOD_M5:  tf_multiplier = 1.0; break;
               case PERIOD_M1:  tf_multiplier = 0.8; break;
            }
            
            tf_obs[i].strength_score *= tf_multiplier;
            tf_obs[i].strength_score = MathMin(100.0, tf_obs[i].strength_score);
            
            // Add to main array
            ArrayResize(ob_array, total_obs + 1);
            ob_array[total_obs] = tf_obs[i];
            total_obs++;
         }
      }
      
      // Restore original timeframe count
      m_tf_count = original_tf_count;
   }
   
   // Sort by strength score (highest first)
   for(int i = 0; i < total_obs - 1; i++)
   {
      for(int j = i + 1; j < total_obs; j++)
      {
         if(ob_array[j].strength_score > ob_array[i].strength_score)
         {
            EnhancedOrderBlock temp = ob_array[i];
            ob_array[i] = ob_array[j];
            ob_array[j] = temp;
         }
      }
   }
   
   return total_obs > 0;
}

//+------------------------------------------------------------------+
//| Calculate Order Block strength score (0-100)                    |
//+------------------------------------------------------------------+
double COrderBlockDetectorV2::CalculateOBStrengthScore(string symbol, EnhancedOrderBlock &ob)
{
   double score = 0.0;
   
   // Base score from candle size (0-25 points)
   double ob_size = CalculateOBSize(ob, symbol);
   score += MathMin(25.0, ob_size / m_min_ob_size * 10.0);
   
   // Volume score (0-20 points)
   if(IsHighVolumeOB(symbol, ob))
      score += 20.0;
   else
      score += 10.0;
   
   // Touch count score (0-15 points)
   score += MathMin(15.0, ob.touch_count * 5.0);
   
   // Institutional pattern bonus (0-15 points)
   if(ob.is_institutional)
      score += 15.0;
   
   // Fair Value Gap bonus (0-10 points)
   if(ob.has_fvg)
      score += 10.0;
   
   // Breaker block bonus (0-10 points)
   if(ob.is_breaker)
      score += 10.0;
   
   // Time decay factor (0-5 points)
   datetime current_time = TimeCurrent();
   int hours_old = (int)((current_time - ob.time) / 3600);
   double time_factor = MathMax(0.0, 5.0 - (hours_old / 24.0));
   score += time_factor;
   
   return MathMin(100.0, score);
}

//+------------------------------------------------------------------+
//| Check if OB follows institutional pattern (3-touch rule)        |
//+------------------------------------------------------------------+
bool COrderBlockDetectorV2::IsInstitutionalPattern(string symbol, EnhancedOrderBlock &ob)
{
   if(!m_use_institutional) return false;
   
   // Check for 3-touch rule
   int touch_count = 0;
   double tolerance = GetPipValue(symbol) * 2.0; // 2 pip tolerance
   
   // Count touches to the OB level
   for(int i = 0; i < m_lookback_bars / 2; i++)
   {
      double high = iHigh(symbol, ob.timeframe, i);
      double low = iLow(symbol, ob.timeframe, i);
      
      if(ob.is_bullish)
      {
         // Check touches to support level
         if(MathAbs(low - ob.low) <= tolerance)
            touch_count++;
      }
      else
      {
         // Check touches to resistance level
         if(MathAbs(high - ob.high) <= tolerance)
            touch_count++;
      }
   }
   
   ob.touch_count = touch_count;
   return touch_count >= 3;
}

//+------------------------------------------------------------------+
//| Check for Fair Value Gap                                        |
//+------------------------------------------------------------------+
bool COrderBlockDetectorV2::HasFairValueGap(string symbol, EnhancedOrderBlock &ob)
{
   if(!m_use_fvg) return false;
   
   // Look for gap before the OB formation
   for(int i = 1; i < 5; i++)
   {
      double prev_high = iHigh(symbol, ob.timeframe, i + 1);
      double prev_low = iLow(symbol, ob.timeframe, i + 1);
      double curr_high = iHigh(symbol, ob.timeframe, i);
      double curr_low = iLow(symbol, ob.timeframe, i);
      
      // Check for bullish FVG (gap up)
      if(ob.is_bullish && prev_high < curr_low)
      {
         double gap_size = (curr_low - prev_high) / GetPipValue(symbol);
         if(gap_size >= 3.0) // Minimum 3 pip gap
            return true;
      }
      
      // Check for bearish FVG (gap down)
      if(!ob.is_bullish && prev_low > curr_high)
      {
         double gap_size = (prev_low - curr_high) / GetPipValue(symbol);
         if(gap_size >= 3.0) // Minimum 3 pip gap
            return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if OB is a breaker block                                  |
//+------------------------------------------------------------------+
bool COrderBlockDetectorV2::IsBreakerBlock(string symbol, EnhancedOrderBlock &ob)
{
   if(!m_use_breaker) return false;
   
   // Breaker block: OB that was broken and then became support/resistance
   double tolerance = GetPipValue(symbol) * 1.0;
   
   for(int i = 0; i < m_lookback_bars / 3; i++)
   {
      double high = iHigh(symbol, ob.timeframe, i);
      double low = iLow(symbol, ob.timeframe, i);
      double close = iClose(symbol, ob.timeframe, i);
      
      if(ob.is_bullish)
      {
         // Check if price broke below and then returned above
         if(low < (ob.low - tolerance) && close > ob.high)
            return true;
      }
      else
      {
         // Check if price broke above and then returned below
         if(high > (ob.high + tolerance) && close < ob.low)
            return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Detect Break of Structure                                       |
//+------------------------------------------------------------------+
bool COrderBlockDetectorV2::DetectBOS(string symbol, ENUM_TIMEFRAMES timeframe, bool &bullish_bos, bool &bearish_bos)
{
   bullish_bos = false;
   bearish_bos = false;
   
   // Find recent swing highs and lows
   double recent_high = 0, recent_low = DBL_MAX;
   int high_index = -1, low_index = -1;
   
   for(int i = 1; i < m_bos_lookback; i++)
   {
      double high = iHigh(symbol, timeframe, i);
      double low = iLow(symbol, timeframe, i);
      
      if(high > recent_high)
      {
         recent_high = high;
         high_index = i;
      }
      
      if(low < recent_low)
      {
         recent_low = low;
         low_index = i;
      }
   }
   
   // Check current price against recent structure
   double current_high = iHigh(symbol, timeframe, 0);
   double current_low = iLow(symbol, timeframe, 0);
   
   // Bullish BOS: break above recent high
   if(current_high > recent_high)
      bullish_bos = true;
   
   // Bearish BOS: break below recent low
   if(current_low < recent_low)
      bearish_bos = true;
   
   return bullish_bos || bearish_bos;
}

//+------------------------------------------------------------------+
//| Detect displacement                                              |
//+------------------------------------------------------------------+
bool COrderBlockDetectorV2::DetectDisplacement(string symbol, ENUM_TIMEFRAMES timeframe, double &displacement_size)
{
   displacement_size = 0.0;
   
   // Look for large candles indicating displacement
   for(int i = 0; i < 5; i++)
   {
      double high = iHigh(symbol, timeframe, i);
      double low = iLow(symbol, timeframe, i);
      double candle_size = (high - low) / GetPipValue(symbol);
      
      if(candle_size > displacement_size)
         displacement_size = candle_size;
   }
   
   // Consider displacement if > 15 pips for major pairs
   return displacement_size >= 15.0;
}

//+------------------------------------------------------------------+
//| Utility functions                                               |
//+------------------------------------------------------------------+
double COrderBlockDetectorV2::GetPipValue(string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   if(digits == 5 || digits == 3)
      return point * 10;
   else
      return point * 100;
}

double COrderBlockDetectorV2::CalculateOBSize(EnhancedOrderBlock &ob, string symbol)
{
   return (ob.high - ob.low) / GetPipValue(symbol);
}

bool COrderBlockDetectorV2::IsHighVolumeOB(string symbol, EnhancedOrderBlock &ob)
{
   // Compare volume to average
   long avg_volume = 0;
   for(int i = 0; i < 20; i++)
   {
      avg_volume += iTickVolume(symbol, ob.timeframe, i);
   }
   avg_volume /= 20;
   
   long ob_volume = iTickVolume(symbol, ob.timeframe, 0); // Simplified
   return ob_volume > avg_volume * 1.5;
}

bool COrderBlockDetectorV2::ValidateOBIntegrity(string symbol, EnhancedOrderBlock &ob)
{
   // Basic validation
   if(ob.high <= ob.low) return false;
   if(CalculateOBSize(ob, symbol) < m_min_ob_size) return false;
   
   return true;
}

bool COrderBlockDetectorV2::IsOBMitigated(string symbol, EnhancedOrderBlock &ob)
{
   double current_price = SymbolInfoDouble(symbol, SYMBOL_BID);
   
   if(ob.is_bullish)
   {
      // Bullish OB mitigated if price closes below low
      return current_price < ob.low;
   }
   else
   {
      // Bearish OB mitigated if price closes above high
      return current_price > ob.high;
   }
}

void COrderBlockDetectorV2::UpdateOBStatus(string symbol, EnhancedOrderBlock &ob_array[])
{
   for(int i = 0; i < ArraySize(ob_array); i++)
   {
      if(ob_array[i].valid)
      {
         ob_array[i].is_mitigated = IsOBMitigated(symbol, ob_array[i]);
         if(ob_array[i].is_mitigated)
            ob_array[i].valid = false;
      }
   }
}

color COrderBlockDetectorV2::GetOBColor(EnhancedOrderBlock &ob)
{
   if(!ob.valid) return clrGray;
   
   if(ob.is_bullish)
   {
      if(ob.strength_score >= 80) return clrLime;
      else if(ob.strength_score >= 60) return clrGreen;
      else return clrDarkGreen;
   }
   else
   {
      if(ob.strength_score >= 80) return clrRed;
      else if(ob.strength_score >= 60) return clrCrimson;
      else return clrDarkRed;
   }
}

string COrderBlockDetectorV2::GetOBDescription(EnhancedOrderBlock &ob)
{
   string desc = "";
   desc += (ob.is_bullish ? "Bullish" : "Bearish") + " OB ";
   desc += "Score: " + DoubleToString(ob.strength_score, 1) + " ";
   desc += "TF: " + EnumToString(ob.timeframe) + " ";
   
   if(ob.is_institutional) desc += "[INST] ";
   if(ob.has_fvg) desc += "[FVG] ";
   if(ob.is_breaker) desc += "[BRK] ";
   
   return desc;
}

// Additional liquidity detection functions
bool COrderBlockDetectorV2::DetectLiquiditySweep(string symbol, ENUM_TIMEFRAMES timeframe, double &sweep_level)
{
   // Implementation for liquidity sweep detection
   return false; // Placeholder
}

bool COrderBlockDetectorV2::DetectEqualHighsLows(string symbol, double &equal_high, double &equal_low)
{
   // Implementation for equal highs/lows detection
   return false; // Placeholder
}

bool COrderBlockDetectorV2::DetectStopHunt(string symbol, double &hunt_level)
{
   // Implementation for stop hunt detection
   return false; // Placeholder
}

double COrderBlockDetectorV2::GetVolumeAtLevel(string symbol, double price_level, int bars_back)
{
   // Implementation for volume at specific price level
   return 0.0; // Placeholder
} 