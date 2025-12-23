# Structured Input Contract for LLM

## Rule Zero (Non-Negotiable)

> **LLM must NEVER compute indicators**
> **LLM must NEVER scan candles**
> **LLM must NEVER infer structure from raw data**

All math, indicators, structure, filters → **your system**
LLM → **reasoning + contradiction detection + synthesis**

---

## Implementation

### ContextContracts Module

Located in `lib/ta-agent/agent/context_contracts.rb`

Provides structured data contracts for each timeframe:

1. **TF15MContext** - Market context (direction & permission)
2. **TF5MContext** - Setup validation (quality check)
3. **TF1MContext** - Entry timing (execution precision)
4. **OptionStrikesContext** - Feasibility & selection (pre-filtered, pre-scored)
5. **MarketConditionsContext** - Global filters (kill switches)

### What LLM Receives (Trading Brief)

```json
{
  "tf_15m": {
    "trend": {
      "direction": "bullish",
      "strength": "strong",
      "adx": 28.4,
      "di_diff": 12.1
    },
    "structure": {
      "market_structure": "HH_HL",
      "last_bos": "up",
      "structure_age_candles": 6
    },
    "volatility": {
      "atr_trend": "expanding",
      "range_state": "expansion"
    },
    "key_levels": {
      "vwap_position": "above",
      "ema_stack": "bullish",
      "distance_from_vwap_pct": 0.18
    },
    "permission": {
      "options_buying_allowed": true,
      "allowed_direction": "CE"
    }
  },
  "tf_5m": {
    "setup": {
      "type": "pullback",
      "quality": "high"
    },
    "momentum": {
      "rsi": 58.2,
      "rsi_trend": "rising",
      "macd_state": "bullish_cross"
    },
    "price_behavior": {
      "last_close_strength": "strong",
      "upper_wick_pct": 12.5,
      "body_pct": 68.0
    },
    "vwap_relation": {
      "state": "reclaiming",
      "retests": 1
    },
    "invalidations": [],
    "proceed_to_entry": true
  },
  "tf_1m": {
    "trigger": {
      "status": "confirmed",
      "type": "momentum_burst"
    },
    "momentum_ignition": {
      "range_expansion_pct": 1.6,
      "atr_spike": true,
      "consecutive_strong_closes": 2
    },
    "micro_structure": {
      "higher_low": true,
      "lower_wick_dominance": true
    },
    "entry_zone": {
      "price_from": 103.5,
      "price_to": 105.0
    },
    "risk": {
      "invalid_price": 97.8,
      "rr_estimate": 2.1
    }
  },
  "option_strikes": [
    {
      "symbol": "NIFTY",
      "strike": "22500 CE",
      "moneyness": "ATM",
      "pricing": {
        "ltp": 104.2,
        "bid": 103.8,
        "ask": 104.6,
        "spread_pct": 0.76
      },
      "greeks": {
        "delta": 0.54,
        "gamma": 0.041,
        "theta": -0.92,
        "vega": 0.18
      },
      "iv": {
        "current": 16.8,
        "iv_trend": "rising"
      },
      "oi": {
        "oi_change": "increase",
        "oi_confirmation": true
      },
      "risk_flags": {
        "theta_risk": "acceptable",
        "liquidity": "good"
      },
      "score": 8.4
    }
  ],
  "market_conditions": {
    "session": {
      "time": "13:42",
      "phase": "mid"
    },
    "index_state": {
      "gap": "none",
      "gap_filled": true
    },
    "volatility": {
      "india_vix": 12.4,
      "vix_trend": "rising"
    },
    "event_risk": {
      "expiry_day": false,
      "major_event": false
    },
    "no_trade_zones": {
      "reason": null
    }
  }
}
```

### What LLM NEVER Sees

❌ Raw OHLC arrays
❌ Indicator arrays
❌ Candle-by-candle data
❌ Unfiltered strikes
❌ Wide spreads
❌ Deep OTM options

---

## LLM Output Contract

```json
{
  "decision": "enter | wait | no_trade",
  "confidence": 0.82,
  "reasoning": [
    "15m bullish trend with expanding ATR",
    "5m pullback resolved above VWAP",
    "1m momentum burst confirmed",
    "ATM CE shows rising IV and tight spread"
  ],
  "preferred_strike": "22500 CE",
  "entry_guidance": "Buy on hold above 105"
}
```

**Decision Criteria:**
- `enter`: All gates passed, signals aligned, confidence >= 0.7
- `wait`: Signals forming but not confirmed, confidence 0.5-0.7
- `no_trade`: Contradictions detected, low confidence, or gates failed

**If confidence < 0.7 → recommend "wait" or "no_trade"**

---

## Integration Flow

```
TradingPipeline.run
  ↓
Build raw contexts (15m, 5m, 1m, options)
  ↓
Extract indicators (ADX, RSI, ATR, VWAP, etc.)
  ↓
Build structured contexts (ContextContracts)
  ↓
Check 15m permission gate (hard stop)
  ↓
Build trading brief (structured JSON)
  ↓
Pass to LLM (PromptBuilder)
  ↓
LLM analyzes structured facts
  ↓
Return structured decision
```

---

## Implementation Status

✅ **ContextContracts** - All 5 context builders
✅ **PromptBuilder** - Formats structured brief
✅ **TradingPipeline** - Uses contracts, not raw data
⏳ **Indicator extraction** - Placeholders for ADX, RSI, ATR, VWAP
⏳ **Structure detection** - Placeholders for HH_HL, BOS detection
⏳ **Market conditions** - Placeholders for VIX, session data

---

## Next Steps

1. Implement actual indicator calculations (ADX, RSI, ATR, VWAP)
2. Implement structure detection (HH_HL, LL_LH, BOS)
3. Connect to VIX data source
4. Enhance market conditions detection
5. Test with real LLM responses

---

## Hard Truth

If you pass:
- raw candles → wasting tokens
- indicator arrays → encouraging hallucination
- "figure it out" prompts → building unreliable system

This structure is **how institutional systems talk to humans**.
Your LLM is replacing the human analyst — **not the trading engine**.


