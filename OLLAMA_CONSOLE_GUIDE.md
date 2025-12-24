# Ollama Integration - Console Guide

This guide shows you how to experiment with Ollama integration using `bin/console`.

## Quick Start

### 1. Start the Console

```bash
./bin/console
# or
bundle exec ruby bin/console
```

### 2. Test Ollama Connection

```ruby
# Quick test (uses OLLAMA_HOST_URL env var or defaults to 192.168.1.14:11434)
test_ollama

# Custom host and model
test_ollama(host_url: "http://192.168.1.14:11434", model: "llama2")
```

## Basic Ollama Usage

### Simple Chat

```ruby
# Quick helper method
chat("What is technical analysis?")

# With custom model
chat("Explain RSI indicator", model: "llama2")
```

### Direct Client Usage

```ruby
# Create client
client = ollama_client(model: "llama3.2:3b")
# or with custom host
client = ollama_client(host_url: "http://192.168.1.14:11434", model: "llama3.2:3b")

# Send a message
response = client.chat(
  messages: [
    { role: "user", content: "Hello, how are you?" }
  ]
)

puts response[:content]
# => "Hello! I'm doing well, thank you for asking..."
```

### Conversation with History

```ruby
client = ollama_client

# First message
response1 = client.chat(
  messages: [
    { role: "user", content: "My name is Alice" }
  ]
)

# Continue conversation
response2 = client.chat(
  messages: [
    { role: "user", content: "My name is Alice" },
    { role: "assistant", content: response1[:content] },
    { role: "user", content: "What's my name?" }
  ]
)

puts response2[:content]
# => "Your name is Alice!"
```

### System Prompts

```ruby
client = ollama_client

response = client.chat(
  messages: [
    {
      role: "system",
      content: "You are a technical analysis expert for Indian stock markets."
    },
    {
      role: "user",
      content: "Explain what ADX means in trading"
    }
  ]
)

puts response[:content]
```

## Agent Loop (ReAct Pattern)

The agent loop implements a ReAct pattern where the LLM can call tools to gather data.

### Basic Agent Loop

```ruby
# Create a simple agent loop
loop = agent_loop(
  goal: "Explain what NIFTY is",
  initial_context: { symbol: "NIFTY" }
)

# Run the loop
result = loop.run

puts result[:answer]
puts "Steps taken: #{result[:steps]}"
```

### Agent Loop with Custom Tools

```ruby
# Create tool registry
registry = TaAgent::Agent::ToolRegistry.new(mode: :alert)

# Register a custom tool
registry.register(
  :get_price,
  description: "Get current price of a symbol",
  params_schema: {
    symbol: { type: "string", required: true }
  },
  handler: ->(args) {
    # Your tool implementation
    { success: true, data: { price: 22500, symbol: args[:symbol] } }
  }
)

# Create loop with custom registry
config = TaAgent::Config.instance
loop = TaAgent::Agent::Loop.new(
  goal: "Get NIFTY price and explain if it's high or low",
  initial_context: { symbol: "NIFTY" },
  tool_registry: registry,
  config: config
)

result = loop.run
puts result[:answer]
```

## Advanced Examples

### Tool Calling (Function Calling)

```ruby
client = ollama_client

# Define tools schema
tools = [
  {
    type: "function",
    function: {
      name: "get_weather",
      description: "Get weather for a city",
      parameters: {
        type: "object",
        properties: {
          city: { type: "string", description: "City name" }
        },
        required: ["city"]
      }
    }
  }
]

# Chat with tools
response = client.chat(
  messages: [
    { role: "user", content: "What's the weather in Mumbai?" }
  ],
  tools: tools
)

# Check if LLM wants to call a tool
if response[:tool_calls]&.any?
  tool_call = response[:tool_calls].first
  puts "Tool to call: #{tool_call.dig('function', 'name')}"
  puts "Arguments: #{tool_call.dig('function', 'arguments')}"
end
```

### Response Parsing

```ruby
require_relative "lib/ta-agent/llm/response_parser"

parser = TaAgent::LLM::ResponseParser.new
client = ollama_client

response = client.chat(
  messages: [{ role: "user", content: "Analyze NIFTY" }]
)

parsed = parser.parse(response)
puts "Type: #{parsed[:type]}"
puts "Content: #{parsed[:content]}"
```

### Error Handling

```ruby
begin
  client = ollama_client(host_url: "http://192.168.1.14:11434")
  response = client.chat(messages: [{ role: "user", content: "Hello" }])
  puts response[:content]
rescue TaAgent::OllamaError => e
  puts "Ollama error: #{e.message}"
  puts "Make sure Ollama is running!"
end
```

## Configuration

### Using Environment Variables

```bash
export OLLAMA_HOST_URL=http://192.168.1.14:11434
```

### Using Config File

Create `~/.ta-agent/config.yml`:

```yaml
ollama:
  model: mistral
  host_url: http://192.168.1.14:11434
```

### Access Config in Console

```ruby
config = TaAgent::Config.instance
puts config.ollama_enabled?  # => true/false
puts config.ollama_host_url  # => "http://192.168.1.14:11434"
puts config.ollama_model      # => "llama3.2:3b"
```

## Available Models

Test with different models:

```ruby
# Mistral (default)
client = ollama_client(model: "llama3.2:3b")

# Llama 2
client = ollama_client(model: "llama2")

# Llama 3
client = ollama_client(model: "llama3")

# Custom model
client = ollama_client(model: "your-custom-model")
```

## Troubleshooting

### Ollama Not Running

```ruby
# Check if Ollama is accessible
test_ollama
# => ❌ Ollama connection failed: Connection refused

# Solution: Start Ollama
# ollama serve
```

### Wrong Model Name

```ruby
# List available models (run in terminal)
# ollama list

# Then use correct model name
client = ollama_client(model: "llama3.2:3b")  # Use actual model name
```

### Timeout Issues

```ruby
# Create client with longer timeout
client = TaAgent::LLM::OllamaClient.new(
  host_url: "http://192.168.1.14:11434",
  model: "llama3.2:3b",
  timeout: 60  # 60 seconds
)
```

## Helper Methods Available in Console

- `test_ollama(host_url:, model:)` - Test Ollama connection
- `chat(message, model:, host_url:)` - Quick chat helper
- `ollama_client(host_url:, model:)` - Create Ollama client
- `agent_loop(goal:, initial_context:, mode:)` - Create agent loop

## Next Steps

1. Experiment with different prompts
2. Try tool calling with custom tools
3. Build agent loops for specific tasks
4. Integrate with DhanHQ data (see other guides)

Happy experimenting! 🚀

