# frozen_string_literal: true

require_relative "ta-agent/version"

# TaAgent - CLI-first Technical Analysis Agent for Indian markets
#
# A serious CLI-based Technical Analysis Agent powered by:
# - dhanhq-client (data source)
# - Deterministic TA pipelines (multi-timeframe)
# - Optional LLM analysis via Ollama
# - Zero Rails, zero RSpec, zero UI
#
# @example
#   require 'ta-agent'
#   agent = TaAgent::Agent::Runner.new(symbol: 'NIFTY')
#   result = agent.run
module TaAgent
  class Error < StandardError; end

  # Configuration error - missing required ENV vars or config
  class ConfigurationError < Error; end

  # DhanHQ API error
  class DhanHQError < Error; end

  # Ollama connection error (non-fatal)
  class OllamaError < Error; end
end

