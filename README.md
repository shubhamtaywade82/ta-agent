# TaAgent

**CLI-first Technical Analysis Agent for Indian markets (NIFTY/options)**

A serious CLI-based Technical Analysis Agent powered by:
- `dhanhq-client` (data source)
- Deterministic TA pipelines (multi-timeframe)
- Optional LLM analysis via **Ollama**
- Zero Rails, zero RSpec, zero UI
- CLI-only (like `kubectl`, `terraform`, `gh`)

## Design Philosophy

- **CLI is the primary interface** - automation-ready, cron-friendly
- **LLM is optional** - works without Ollama, deterministic core
- **LLM = analyst, not calculator** - provides explanation, not calculation
- **Config via ENV + config file** - simple, portable
- **Works offline** (except DhanHQ API calls)

## Installation

```bash
gem install ta-agent
```

Or add to your Gemfile:

```ruby
gem 'ta-agent'
```

## Configuration

### Required ENV Variables

```bash
export DHANHQ_CLIENT_ID=xxxx
export DHANHQ_ACCESS_TOKEN=xxxx
export OLLAMA_HOST_URL=http://192.168.1.14:11434  # Optional
```

### Optional Config File

Create `~/.ta-agent/config.yml`:

```yaml
ollama:
  model: mistral
analysis:
  default_symbol: NIFTY
  confidence_threshold: 0.75
options:
  max_spread_pct: 1.0
```

## Usage

### One-time Analysis

```bash
ta-agent analyse NIFTY
```

Output:
```
✔ 15m Trend: Bullish (ADX 28)
✔ 5m Setup: Pullback resolved
✔ Option: 22500 CE (Score 8.4)
✔ 1m Trigger: Confirmed

Recommendation:
  Buy 22500 CE above 105
  SL: 98 | Target: 140–160
  Confidence: 82%
```

### Continuous Monitoring

```bash
ta-agent watch NIFTY --interval 60
```

Runs analysis every 60 seconds, prints only state changes.

### Interactive Config

```bash
ta-agent config
```

## Architecture

### Core Components

- **CLI** (`lib/ta-agent/cli/`) - Command routing and interface
- **Agent** (`lib/ta-agent/agent/`) - Core execution logic
- **TA** (`lib/ta-agent/ta/`) - Technical analysis pipelines
- **Options** (`lib/ta-agent/options/`) - Option chain analysis
- **LLM** (`lib/ta-agent/llm/`) - Optional Ollama integration
- **DhanHQ** (`lib/ta-agent/dhanhq/`) - Data source wrapper

### Agent Flow

1. Build 15m context → abort if blocked
2. Build 5m context → abort if blocked
3. Build option chain context → abort if empty
4. Build 1m context
5. Apply gates (kill switches)
6. If LLM enabled → LLM decision
7. Else → deterministic decision
8. Format output

## Development

This gem is designed to be implemented incrementally. The structure is in place with placeholder files documenting the design intent.

### Structure

```
lib/ta-agent/
├── config.rb              # Global config loader
├── environment.rb          # ENV validation
├── cli/                    # CLI commands
├── dhanhq/                 # Data source wrapper
├── ta/                     # Technical analysis
│   ├── indicators/         # EMA, ADX, ATR, VWAP
│   ├── structure/          # Trend, market structure
│   └── timeframes/         # 15m, 5m, 1m analyzers
├── options/                # Option chain analysis
├── market/                 # VIX, session, kill switches
├── agent/                  # Core runner
├── llm/                    # Ollama integration
└── output/                 # Formatters
```

## What This Gem Does NOT Do

❌ Trade execution
❌ Backtesting
❌ Web UI
❌ Strategy overfitting
❌ Over-configuration

This gem is **analysis only**. Execution belongs elsewhere.

## Future Evolution

This CLI-first design can evolve into:
- Daemon mode
- Cron tool
- Webhook emitter
- Telegram bot wrapper

## License

MIT

## Contributing

This is a serious technical analysis tool. Contributions should maintain the CLI-first, deterministic core philosophy.
