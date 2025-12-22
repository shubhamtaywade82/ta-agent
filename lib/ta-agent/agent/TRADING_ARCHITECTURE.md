# Battle-Ready Trading Pipeline Architecture

## Core Principle (Non-Negotiable)

> **Higher timeframe defines CONTEXT**
> **Lower timeframe defines TIMING**
> **Options chain defines FEASIBILITY**

If you violate this → garbage signals.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│         TradingPipeline (Orchestrator)          │
└─────────────────────────────────────────────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
    ┌───▼───┐   ┌───▼───┐   ┌───▼──────┐
    │ 15m   │   │  5m   │   │ Options  │
    │Context│   │Setup  │   │  Chain   │
    └───┬───┘   └───┬───┘   └───┬──────┘
        │           │           │
        └───────────┼───────────┘
                    │
            ┌───────▼───────┐
            │  Hard Gates   │
            │ (Stop if fail)│
            └───────┬───────┘
                    │
            ┌───────▼───────┐
            │  1m Entry     │
            │   Timing      │
            └───────┬───────┘
                    │
            ┌───────▼───────┐
            │  LLM Analysis │
            │ (Validation)  │
            └───────┬───────┘
                    │
            ┌───────▼───────┐
            │ Recommendation│
            └───────────────┘
```

---

## Timeframe Responsibilities

### 15 MINUTE → MARKET CONTEXT (NO ENTRIES)

**Purpose:**
- Directional bias
- Trend strength
- Volatility state
- "Should I even think about CE or PE?"

**Output (STRICT):**
```json
{
  "bias": "bullish | bearish | neutral",
  "trend_strength": "strong | weak",
  "volatility": "expanding | contracting | stable",
  "trade_allowed": true | false
}
```

**Gate:** If `trade_allowed = false` → **STOP**
NO 5m, NO 1m, NO option chain.

---

### 5 MINUTE → SETUP VALIDATION (STILL NO ENTRY)

**Purpose:**
- Is there a **tradable setup forming**?
- Pullback? Breakout? Range expansion?
- Is momentum aligning with 15m?

**Output:**
```json
{
  "setup_type": "breakout | pullback | trend_continuation | none",
  "momentum_alignment": true | false,
  "invalidations": ["vwap_rejection", "weak_close", ...],
  "proceed_to_entry": true | false
}
```

**Gate:** If `proceed_to_entry = false` → **STOP**

---

### 1 MINUTE → ENTRY TIMING ONLY

**Purpose:**
- Exact trigger
- Risk-defined entry
- Momentum ignition

**Output:**
```json
{
  "entry_signal": "confirmed | not_confirmed",
  "trigger_reason": "range_break + strong_close",
  "entry_zone": { "from": 102, "to": 105 }
}
```

**Gate:** If not confirmed → **WAIT**
No "anticipatory entries". That's gambler trash.

---

## Options Chain Analysis (Parallel Pipeline)

Runs **in parallel**, not inside candle logic.

### Filtering Rules (STRICT)

**Only:**
- ATM
- ATM +1

**Ignore:**
- Deep ITM (theta trap)
- Far OTM (liquidity + spread hell)

### Pre-Scoring (NON-LLM)

**Formula:**
```
score =
  delta_weight (0-3) +
  gamma_weight (0-2) +
  spread_penalty (0 to -2) +
  iv_behavior_bonus (0-1.5) +
  oi_confirmation (0-1.5) +
  theta_risk_penalty (0 to -1)
```

**Output:**
```json
[
  {
    "strike": "NIFTY 22500 CE",
    "score": 8.7,
    "delta": 0.42,
    "gamma": 0.012,
    "iv": 18.5
  }
]
```

**Only top 1-2 strikes go to LLM.**

---

## LLM Role (ONLY AFTER ALL GATES PASS)

LLM is used **ONLY AFTER ALL HARD FILTERS PASS**.

**LLM Tasks:**
- Cross-validate signals
- Explain *why* trade makes sense
- Detect **contradictions**
- Suggest **wait vs enter**
- Provide **confidence score**

**LLM Input (structured, not raw data):**
```json
{
  "tf_15m": {
    "bias": "bullish",
    "trend_strength": "strong",
    "volatility": "expanding"
  },
  "tf_5m": {
    "setup_type": "pullback",
    "momentum_alignment": true
  },
  "tf_1m": {
    "entry_signal": "confirmed",
    "trigger_reason": "momentum_ignition"
  },
  "option_strikes": [
    {"strike": "22500 CE", "score": 8.7}
  ]
}
```

**LLM Output:**
```json
{
  "decision": "enter | wait | no_trade",
  "confidence": 0.82,
  "reasoning": [
    "15m trend strong",
    "5m pullback complete",
    "1m momentum ignition",
    "ATM CE shows IV expansion"
  ]
}
```

**Gate:** If confidence < threshold → **NO TRADE**

---

## Execution Flow

```
START
 ├─▶ Fetch 15m data
 │    └─▶ Build context (bias, trend, volatility)
 │         └─▶ Gate: trade_allowed?
 │              └─▶ STOP if false
 │
 ├─▶ Fetch 5m data
 │    └─▶ Build setup (setup_type, momentum)
 │         └─▶ Gate: proceed_to_entry?
 │              └─▶ STOP if false
 │
 ├─▶ Fetch option chain (parallel)
 │    └─▶ Filter (ATM, ATM+1 only)
 │         └─▶ Score strikes (NON-LLM)
 │              └─▶ Top 1-2 strikes
 │                   └─▶ STOP if no liquid strikes
 │
 ├─▶ Fetch 1m data
 │    └─▶ Build entry timing
 │         └─▶ Gate: entry_signal confirmed?
 │              └─▶ STOP if not confirmed
 │
 ├─▶ Call LLM (analysis only)
 │    └─▶ Tools: validate_alignment, check_conditions, detect_contradictions
 │         └─▶ LLM provides confidence + reasoning
 │
 └─▶ Output structured recommendation
END
```

---

## What This Agent MUST NOT DO

❌ Predict price
❌ Say "market will go up"
❌ Enter trades itself
❌ Ignore higher timeframe
❌ Trade without liquidity check
❌ Override risk rules

If it does → **kill it**

---

## Output Format (Actionable, Not Vague)

```json
{
  "symbol": "NIFTY",
  "direction": "CE",
  "recommended_strike": "22500 CE",
  "entry": "Above 104",
  "stop_loss": "Below 92",
  "target_zone": "130–150",
  "confidence": 0.82,
  "notes": "Momentum ignition after VWAP reclaim",
  "gates_passed": ["15m", "5m", "options", "1m"]
}
```

---

## Implementation Status

✅ **TradingPipeline** - Main orchestrator
✅ **Timeframe contexts** - 15m, 5m, 1m with proper gates
✅ **StrikeScorer** - Pre-ranking (NON-LLM)
✅ **ToolRegistry** - Analysis tools only (no execution in alert mode)
✅ **Agent Loop** - LLM validation after gates
⏳ **Tool handlers** - Connect to DhanHQ client
⏳ **Enhanced indicators** - ADX, ATR, VWAP for better context
⏳ **Risk engine** - For live mode execution gates

---

## Usage

```ruby
pipeline = TaAgent::Agent::TradingPipeline.new(symbol: "NIFTY")
result = pipeline.run

if result[:recommendation][:decision] == "enter"
  puts "Strike: #{result[:recommendation][:recommended_strike]}"
  puts "Entry: #{result[:recommendation][:entry]}"
  puts "Confidence: #{(result[:confidence] * 100).round(1)}%"
else
  puts "No trade: #{result[:recommendation][:reason]}"
end
```

---

## Hard Truth

If you try to:
- merge all timeframes into one blob
- let the LLM "figure it out"
- skip option chain microstructure

You will:
- overtrade
- enter late
- bleed theta
- blow accounts slowly

**This architecture prevents that.**
