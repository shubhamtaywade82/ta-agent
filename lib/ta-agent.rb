# frozen_string_literal: true


# Load .env file if it exists (before loading other modules)
begin
  require "dotenv"
  # Look for .env in current directory or project root
  env_file = File.exist?(".env") ? ".env" : File.expand_path("../.env", __dir__)
  Dotenv.load(env_file) if File.exist?(env_file)
rescue LoadError
  # dotenv gem not available, skip .env loading
end

require_relative "ta-agent/version"
require_relative "ta-agent/environment"
require_relative "ta-agent/config"

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

