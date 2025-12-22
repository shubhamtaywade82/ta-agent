# frozen_string_literal: true

# TaAgent::Config
#
# Global configuration loader and validator.
#
# Responsibilities:
# - Load ENV variables (DHANHQ_CLIENT_ID, DHANHQ_ACCESS_TOKEN, OLLAMA_HOST_URL)
# - Load optional config file (~/.ta-agent/config.yml)
# - Validate presence of required config
# - Fail fast if token missing
#
# @example
#   config = TaAgent::Config.load
#   config.dhanhq_client_id # => "xxxx"
#   config.ollama_enabled?  # => true/false
#
# Design:
# - Singleton pattern or class-level accessor
# - Raises TaAgent::ConfigurationError if required ENV missing
# - Merges ENV + config file (ENV takes precedence)
module TaAgent
  class Config
    # TODO: Implement config loading logic
    # - Load from ENV
    # - Load from ~/.ta-agent/config.yml if exists
    # - Validate required fields
    # - Return config object with accessors
  end
end

