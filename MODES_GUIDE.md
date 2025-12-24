# Ta-Agent Modes Guide

This guide explains the different modes supported by ta-agent and how to use them.

## Overview

Ta-agent supports multiple modes for different use cases:

1. **ToolRegistry Modes** - Control tool availability and execution capabilities
2. **Console Interaction Modes** - Different ways to interact with the LLM
3. **CLI Command Modes** - Different operational modes via CLI commands

---

## 1. ToolRegistry Modes

The `ToolRegistry` class supports two modes that control which tools are available:

### Alert Mode (`:alert`) - Default

**Purpose**: Read-only analysis mode. Safe for experimentation and analysis.

**Features**:
- ✅ All analysis tools enabled
- ✅ Signal validation tools enabled
- ✅ Market condition checking tools enabled
- ❌ Execution tools disabled (safety feature)
- ❌ Order placement tools disabled

**Usage**:
```ruby
registry = TaAgent::Agent::ToolRegistry.new(mode: :alert)
# or
registry = TaAgent::Agent::ToolRegistry.new  # defaults to :alert
```

**When to use**:
- Testing and development
- Analysis-only workflows
- Learning and experimentation
- Production analysis (without execution)

### Live Mode (`:live`)

**Purpose**: Full execution mode with risk gates. Use with extreme caution.

**Features**:
- ✅ All analysis tools enabled
- ✅ Signal validation tools enabled
- ✅ Market condition checking tools enabled
- ✅ Execution tools enabled (with gates)
- ✅ Order placement tools enabled (with risk checks)

**Usage**:
```ruby
registry = TaAgent::Agent::ToolRegistry.new(mode: :live)
```

**When to use**:
- Live trading (with proper risk management)
- Automated execution workflows
- Production trading systems

**⚠️ Warning**: Live mode enables order placement. Always implement proper risk gates and monitoring.

---

## 2. Console Interaction Modes

When using `bin/console`, you have access to different interaction modes:

### Chat Mode

**Purpose**: Simple conversational interaction with the LLM.

**Features**:
- Direct chat with Ollama
- No tool calling
- Simple question/answer format
- Conversation history support

**Usage**:
```ruby
# Simple chat
chat("What is technical analysis?")

# With custom model
chat("Explain RSI indicator", model: "llama2")

# With custom host
chat("Hello", host_url: "http://192.168.1.14:11434", model: "llama3.2:3b")
```

**When to use**:
- Quick questions
- Learning about trading concepts
- Simple explanations
- Testing Ollama connection

### Agent Mode

**Purpose**: ReAct pattern agent with tool calling capabilities.

**Features**:
- LLM can call tools to gather data
- Tool execution and result feedback
- Multi-step reasoning
- Context-aware responses

**Usage**:
```ruby
# Create agent loop with alert mode (default)
loop = agent_loop(
  goal: "Analyze NIFTY and explain the current trend",
  initial_context: { symbol: "NIFTY" }
)
result = loop.run

# Create agent loop with live mode
loop = agent_loop(
  goal: "Analyze NIFTY and provide trading recommendation",
  initial_context: { symbol: "NIFTY" },
  mode: :live  # Enable execution tools
)
result = loop.run
```

**When to use**:
- Complex analysis requiring data gathering
- Multi-step reasoning tasks
- Tool-assisted analysis
- Automated decision making

### Direct Client Mode

**Purpose**: Direct control over Ollama client for advanced use cases.

**Features**:
- Full control over messages
- Custom system prompts
- Conversation history management
- Advanced configurations

**Usage**:
```ruby
# Create client
client = ollama_client(model: "llama3.2:3b")

# Simple chat
response = client.chat(
  messages: [
    { role: "user", content: "Hello!" }
  ]
)

# With system prompt
response = client.chat(
  messages: [
    {
      role: "system",
      content: "You are a technical analysis expert."
    },
    {
      role: "user",
      content: "Explain ADX indicator"
    }
  ]
)

# Conversation with history
response = client.chat(
  messages: [
    { role: "user", content: "My name is Alice" },
    { role: "assistant", content: "Nice to meet you, Alice!" },
    { role: "user", content: "What's my name?" }
  ]
)
```

**When to use**:
- Custom workflows
- Advanced prompt engineering
- Integration with other systems
- Fine-grained control

---

## 3. CLI Command Modes

The CLI provides different operational modes:

### Analysis Mode

**Command**: `ta-agent analyse SYMBOL`

**Purpose**: One-time analysis of a symbol.

**Features**:
- Runs complete analysis pipeline
- Multi-timeframe analysis
- Option chain analysis
- Deterministic + optional LLM analysis

**Usage**:
```bash
ta-agent analyse NIFTY
```

### Watch Mode

**Command**: `ta-agent watch SYMBOL [OPTIONS]`

**Purpose**: Continuous monitoring with state change detection.

**Features**:
- Continuous analysis at intervals
- Only prints state changes
- Interactive controls
- Real-time monitoring

**Usage**:
```bash
ta-agent watch NIFTY --interval 60
```

### Console Mode

**Command**: `ta-agent console`

**Purpose**: Interactive REPL for experimentation.

**Features**:
- Interactive prompt
- Command history
- Tab completion
- All console interaction modes available

**Usage**:
```bash
ta-agent console
```

Then in console:
```ruby
# Use chat mode
chat("What is RSI?")

# Use agent mode
loop = agent_loop(goal: "Analyze NIFTY")
result = loop.run

# Use direct client
client = ollama_client
```

### Config Mode

**Command**: `ta-agent config`

**Purpose**: Interactive configuration setup.

**Features**:
- Guided configuration
- ENV variable setup
- Config file creation
- Validation

**Usage**:
```bash
ta-agent config
```

---

## Mode Selection Guide

### For Analysis Only
- **ToolRegistry**: `:alert` mode
- **Console**: Chat mode or Agent mode with `:alert`
- **CLI**: `analyse` or `watch` commands

### For Development/Testing
- **ToolRegistry**: `:alert` mode
- **Console**: All modes available for experimentation
- **CLI**: `console` for interactive testing

### For Live Trading
- **ToolRegistry**: `:live` mode (with proper risk gates)
- **Console**: Agent mode with `:live` (use with caution)
- **CLI**: Custom scripts with `:live` mode

### For Learning/Exploration
- **ToolRegistry**: `:alert` mode
- **Console**: Chat mode for questions, Agent mode for examples
- **CLI**: `console` for interactive exploration

---

## Mode Safety

### Alert Mode Safety
- ✅ Safe by default
- ✅ No execution capabilities
- ✅ Analysis tools only
- ✅ Recommended for most use cases

### Live Mode Safety
- ⚠️ Execution tools enabled
- ⚠️ Requires risk gates
- ⚠️ Requires monitoring
- ⚠️ Use only in production with proper safeguards

---

## Examples

### Example 1: Simple Chat
```ruby
# In bin/console
chat("What is the difference between RSI and MACD?")
```

### Example 2: Agent Analysis (Alert Mode)
```ruby
# In bin/console
loop = agent_loop(
  goal: "Analyze NIFTY and explain the current market conditions",
  initial_context: { symbol: "NIFTY" },
  mode: :alert  # Safe, read-only
)
result = loop.run
puts result[:answer]
```

### Example 3: Agent with Live Mode (Advanced)
```ruby
# In bin/console - USE WITH CAUTION
loop = agent_loop(
  goal: "Analyze NIFTY and place a trade if conditions are met",
  initial_context: { symbol: "NIFTY" },
  mode: :live  # Enables execution tools
)
result = loop.run
```

### Example 4: Direct Client with Custom Prompt
```ruby
# In bin/console
client = ollama_client(model: "llama3.2:3b")
response = client.chat(
  messages: [
    {
      role: "system",
      content: "You are an expert in Indian stock market technical analysis."
    },
    {
      role: "user",
      content: "Explain the best entry strategy for NIFTY options"
    }
  ]
)
puts response[:content]
```

---

## Summary

| Mode Type      | Options           | Use Case                  |
| -------------- | ----------------- | ------------------------- |
| ToolRegistry   | `:alert`, `:live` | Control tool availability |
| Console Chat   | `chat()`          | Simple Q&A                |
| Console Agent  | `agent_loop()`    | Tool-assisted reasoning   |
| Console Client | `ollama_client()` | Advanced control          |
| CLI Analysis   | `analyse`         | One-time analysis         |
| CLI Watch      | `watch`           | Continuous monitoring     |
| CLI Console    | `console`         | Interactive REPL          |
| CLI Config     | `config`          | Configuration setup       |

Choose the mode that best fits your use case, and always prefer `:alert` mode unless you specifically need execution capabilities.

