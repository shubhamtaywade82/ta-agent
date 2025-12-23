# Tool-Based Architecture (The Correct Mental Model)

## The Hard Truth (Memorize This)

> **The LLM never "gets data"**
> **The LLM only gets "facts produced by tools"**

Every single field in the structured context is produced by **deterministic tools**, not by the LLM.

---

## The Real Agent Loop (Correct Version)

```
┌──────────────┐
│   Scheduler  │  (every X seconds)
└──────┬───────┘
       │
       ▼
┌──────────────────────────┐
│ Context Builder Pipeline │  (TOOLS ONLY)
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│  Hard Gates / Kill Switch│  (NO LLM)
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│     LLM Analyst Call     │  (READ-ONLY)
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│  Alert / Decision Output │
└──────────────────────────┘
```

**LLM is downstream. Always.**

---

## Tool Categories

### 1️⃣ Market Data Tools (Raw Fetchers)

**Location:** `lib/ta-agent/tools/market_data_tools.rb`

**Purpose:** Fetch raw data — nothing else.

**Examples:**
- `fetch_ohlc(client, symbol:, timeframe:, days:)`
- `fetch_option_chain(client, symbol:, expiry:)`
- `fetch_india_vix(client)`
- `fetch_market_status()`

**Output:** Raw arrays/hashes
```json
{ "open": [...], "high": [...], "low": [...], "close": [...] }
```

⚠️ **These NEVER go to LLM.**

---

### 2️⃣ Indicator Tools (Pure Math)

**Location:** `lib/ta-agent/tools/indicator_tools.rb`

**Purpose:** Convert raw data → numbers.

**Examples:**
- `calculate_ema(closes, period)`
- `calculate_adx(highs, lows, closes, period:)`
- `calculate_atr(highs, lows, closes, period:)`
- `calculate_vwap(ohlcv)`

**Output:** Indicator values
```json
{ "adx": 28.4, "di_plus": 32.1, "di_minus": 19.8 }
```

⚠️ **Still NOT sent to LLM directly.**

---

### 3️⃣ Structure & Behavior Tools (Interpretation, Still Deterministic)

**Location:** `lib/ta-agent/tools/structure_tools.rb`

**Purpose:** Turn numbers → **labels**.

**Examples:**
- `detect_trend(adx:, ema_9:, ema_21:)`
- `detect_structure(highs, lows)`
- `detect_volatility_state(atr_series)`
- `detect_vwap_relation(price, vwap)`

**Output:** Labels and classifications
```json
{
  "trend": "bullish",
  "strength": "strong",
  "structure": "HH_HL"
}
```

⚠️ **This is what LLM understands.**

---

### 4️⃣ Timeframe Context Builders (CRITICAL)

**Location:** `lib/ta-agent/tools/timeframe_context_builders.rb`

**Purpose:** Aggregate everything per timeframe.

**Examples:**
- `build_tf_context_15m(client, symbol:)`
- `build_tf_context_5m(client, symbol:)`
- `build_tf_context_1m(client, symbol:)`

**Each builder:**
- Pulls outputs from tools 1–3
- Applies **hard rules**
- Produces final JSON blocks

**Output:** Structured context ready for LLM
```json
{
  "permission": {
    "options_buying_allowed": true,
    "allowed_direction": "CE"
  }
}
```

⚠️ **If permission = false → STOP LOOP.**

---

### 5️⃣ Option Chain Processing Tools (MOST IMPORTANT)

**Location:** `lib/ta-agent/tools/option_chain_tools.rb`

**Purpose:** Filter and score strikes (NOT LLM jobs).

**Examples:**
- `filter_strikes(chain, spot_price:)`
- `score_strikes(strikes, context:)`
- `detect_liquidity_risk(strike)`
- `detect_theta_risk(strike)`
- `process_option_chain(client, symbol:, spot_price:)`

**Output:** Pre-filtered, pre-scored strikes
```json
[
  { "strike": "22500 CE", "score": 8.4 }
]
```

⚠️ **LLM sees only the survivors.**

---

### 6️⃣ Market Condition & Risk Tools (GLOBAL KILL SWITCHES)

**Location:** `lib/ta-agent/tools/risk_tools.rb`

**Purpose:** Global filters and kill switches.

**Examples:**
- `check_expiry_risk()`
- `check_time_window()`
- `check_volatility_regime(client)`
- `check_profit_lock()`
- `run_all_checks(client)`

**Output:** Risk assessment
```json
{ "no_trade": false, "reasons": [] }
```

⚠️ **If `no_trade = true` → ABORT.**

---

## Execution Flow

```
TradingPipeline.run
  ↓
STEP 0: RiskTools.run_all_checks (KILL SWITCH)
  ↓ (if passed)
STEP 1: TimeframeContextBuilders.build_tf_context_15m
  ├─▶ MarketDataTools.fetch_ohlc
  ├─▶ IndicatorTools.calculate_ema, calculate_adx, calculate_atr, calculate_vwap
  ├─▶ StructureTools.detect_trend, detect_structure, detect_volatility_state
  └─▶ ContextContracts::TF15MContext.build
  ↓ (if permission granted)
STEP 2: TimeframeContextBuilders.build_tf_context_5m
  ├─▶ MarketDataTools.fetch_ohlc
  ├─▶ IndicatorTools.calculate_ema, calculate_vwap
  └─▶ ContextContracts::TF5MContext.build
  ↓ (if proceed_to_entry)
STEP 3: OptionChainTools.process_option_chain
  ├─▶ MarketDataTools.fetch_option_chain
  ├─▶ OptionChainTools.filter_strikes
  ├─▶ OptionChainTools.score_strikes
  └─▶ ContextContracts::OptionStrikesContext.build
  ↓ (if liquid strikes found)
STEP 4: TimeframeContextBuilders.build_tf_context_1m
  ├─▶ MarketDataTools.fetch_ohlc
  ├─▶ IndicatorTools.calculate_atr
  └─▶ ContextContracts::TF1MContext.build
  ↓ (if trigger confirmed)
STEP 5: Build structured context (all contracts)
  ↓
STEP 6: LLM Analysis (if enabled)
  └─▶ Agent::Loop with structured context
  ↓
STEP 7: Output recommendation
```

---

## When Does the LLM Get Called?

**Only AFTER:**
✅ All contexts built (via tools)
✅ All hard gates passed
✅ Strikes filtered & scored (via tools)
✅ Risk allowed

Then and only then:

```ruby
if hard_gates_passed?
  structured_context = build_structured_context_from_tools()
  call_llm(structured_context)
end
```

---

## Why This Design Works

| Problem       | This Design Solves It |
| ------------- | --------------------- |
| Hallucination | LLM never computes    |
| Overtrading   | Hard gates stop flow  |
| Late entries  | 1m trigger isolated   |
| Theta bleed   | Strike filtering      |
| Random trades | Deterministic filters |
| Token waste   | Compressed facts      |

---

## What the LLM is NOT Allowed to Do

❌ Compute indicators
❌ Decide risk
❌ Override gates
❌ Pick random strikes
❌ Say "I think market will…"

**LLM is a judge, not a gambler.**

---

## Implementation Status

✅ **MarketDataTools** - Raw fetchers
✅ **IndicatorTools** - Pure math (EMA, ADX, ATR, VWAP)
✅ **StructureTools** - Interpretation (trend, structure, volatility)
✅ **TimeframeContextBuilders** - Aggregators (15m, 5m, 1m)
✅ **OptionChainTools** - Filter & score strikes
✅ **RiskTools** - Global kill switches
✅ **TradingPipeline** - Uses all tools in correct order

⏳ **Enhanced indicators** - RSI, MACD, DI+/-
⏳ **Structure detection** - Proper HH_HL, BOS detection
⏳ **Market conditions** - VIX fetch, expiry detection

---

## This is NOT "Optional"

If you:
- let LLM calculate RSI
- let it inspect candles
- let it pick strikes freely

You are **building a toy**, not a system.

**This architecture prevents that.**

