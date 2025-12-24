# frozen_string_literal: true

# TaAgent::Environment
#
# ENV validation and environment setup.
#
# Responsibilities:
# - Validate required ENV variables are present
# - Provide helper methods for environment checks
# - Fail fast with clear error messages
#
# Required ENV:
# - DHANHQ_CLIENT_ID
# - DHANHQ_ACCESS_TOKEN
# - OLLAMA_HOST_URL (optional, defaults to http://192.168.1.14:11434)
#
# Design:
# - Class-level validation methods
# - Raises TaAgent::ConfigurationError with helpful messages
module TaAgent
  class Environment
    REQUIRED_VARS = %w[DHANHQ_CLIENT_ID DHANHQ_ACCESS_TOKEN].freeze
    OPTIONAL_VARS = {
      "OLLAMA_HOST_URL" => "http://192.168.1.14:11434"
    }.freeze

    # Support both naming conventions:
    # - DHANHQ_CLIENT_ID / CLIENT_ID
    # - DHANHQ_ACCESS_TOKEN / ACCESS_TOKEN
    ALIASES = {
      "CLIENT_ID" => "DHANHQ_CLIENT_ID",
      "ACCESS_TOKEN" => "DHANHQ_ACCESS_TOKEN"
    }.freeze

    def self.validate!
      # Normalize aliases first
      normalize_aliases!

      missing = REQUIRED_VARS.reject { |var| ENV[var] && !ENV[var].strip.empty? }

      unless missing.empty?
        raise ConfigurationError, <<~ERROR
          Missing required environment variables: #{missing.join(", ")}

          Please set in .env file or environment:
          #{missing.map { |var| "  #{var}=your_value" }.join("\n")}

          Or use aliases:
          #{missing.map { |var| "  #{ALIASES.key(var) || var}=your_value" }.join("\n")}

          Or run 'ta-agent config' for interactive setup.
        ERROR
      end

      true
    end

    def self.normalize_aliases!
      ALIASES.each do |alias_key, canonical_key|
        if ENV[alias_key] && !ENV[alias_key].strip.empty? && (ENV[canonical_key].nil? || ENV[canonical_key].strip.empty?)
          ENV[canonical_key] = ENV[alias_key]
        end
      end
    end

    def self.ollama_host_url
      ENV["OLLAMA_HOST_URL"] || OPTIONAL_VARS["OLLAMA_HOST_URL"]
    end

    def self.dhanhq_client_id
      normalize_aliases!
      ENV["DHANHQ_CLIENT_ID"] || ENV["CLIENT_ID"]
    end

    def self.dhanhq_access_token
      normalize_aliases!
      ENV["DHANHQ_ACCESS_TOKEN"] || ENV["ACCESS_TOKEN"]
    end

    def self.ollama_enabled?
      !ollama_host_url.nil? && !ollama_host_url.strip.empty?
    end
  end
end
