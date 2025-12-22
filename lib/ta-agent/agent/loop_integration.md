# Agent Loop Integration Guide

## Overview

The agent loop system implements a **ReAct (Reasoning + Acting) pattern** where:
- **LLM decides** what tools to call (doesn't execute)
- **Runtime executes** tools
- **Tool results** fed back to LLM
- **Loop continues** until stop condition

## Architecture

```
┌─────────────────┐
│  Agent::Loop    │  ← Main orchestrator
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼───┐  ┌──▼──────────┐
│ State │  │ ToolRegistry│
└───┬───┘  └──┬──────────┘
    │         │
┌───▼─────────▼───┐
│  OllamaClient   │
└─────────────────┘
```

## Components

### 1. ToolRegistry
- Registers available tools with schemas
- Validates tool calls
- Executes tools
- **Mode-based**: `:alert` (read-only) vs `:live` (with execution gates)

### 2. LoopState
- Tracks conversation history
- Manages memory (last N tool results)
- Enforces step limits
- Builds prompts with context

### 3. Loop
- Main execution loop
- Orchestrates: LLM → Tool → Observe → Repeat
- Enforces stop conditions

## Usage

### Basic Example

```ruby
require "ta-agent"

# Create tool registry (alert mode = read-only)
registry = TaAgent::Agent::ToolRegistry.new(mode: :alert)

# Register custom tools
registry.register(
  :get_ohlc,
  description: "Fetch OHLCV data",
  params_schema: {
    symbol: { type: "string", required: true },
    timeframe: { type: "string", required: true }
  },
  handler: ->(args) {
    # Your tool implementation
    client = TaAgent::DhanHQ::Client.new(...)
    client.fetch_ohlcv(symbol: args[:symbol], timeframe: args[:timeframe])
  }
)

# Create loop
loop = TaAgent::Agent::Loop.new(
  goal: "Analyze NIFTY and recommend best option strike",
  initial_context: { symbol: "NIFTY", trend: "bullish" },
  tool_registry: registry,
  config: TaAgent::Config.instance
)

# Run loop
result = loop.run

puts result[:answer]
puts "Steps: #{result[:steps]}"
```

## Stop Conditions

The loop stops when:
1. **Explicit final answer** - LLM says "final answer" or "conclusion"
2. **Step limit** - Maximum 10 steps reached
3. **Confidence threshold** - Confidence < 0.3
4. **Too many errors** - 2+ consecutive tool errors

## Safety Features

### Alert Mode (Default)
- ✅ Read tools: `get_ohlc`, `calculate_ema`, `get_option_chain`, `score_strike`
- ❌ Execution tools: `place_order` **DISABLED**

### Live Mode
- ✅ All tools available
- ⚠️ Execution tools **GATED** behind risk engine (to be implemented)

## Integration with Current System

### Option 1: Replace Decision.with_llm

```ruby
# In Agent::Decision
def with_llm(context, base_decision)
  loop = Loop.new(
    goal: "Enhance trading recommendation with deeper analysis",
    initial_context: context,
    tool_registry: build_tool_registry(context),
    config: @config
  )

  result = loop.run
  enhance_decision(base_decision, result[:answer])
end
```

### Option 2: New CLI Command

```ruby
# ta-agent loop NIFTY --goal "Find best strike"
# Uses agent loop instead of single-shot analysis
```

## Tool Implementation

Tools must:
1. Return `Hash` with `:success`, `:data` or `:error` keys
2. Handle errors gracefully
3. Validate inputs (registry does basic validation)

Example:
```ruby
handler: ->(args) {
  begin
    data = fetch_data(args[:symbol])
    { success: true, data: data }
  rescue StandardError => e
    { success: false, error: e.message }
  end
}
```

## Next Steps

1. ✅ Core loop system (DONE)
2. ⏳ Implement tool handlers (connect to existing DhanHQ client)
3. ⏳ Add risk engine for live mode
4. ⏳ Integrate with Runner or create new command
5. ⏳ Add monitoring/logging
