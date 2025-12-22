# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "environment"

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
    CONFIG_DIR = File.expand_path("~/.ta-agent")
    CONFIG_FILE = File.join(CONFIG_DIR, "config.yml")

    attr_reader :dhanhq_client_id, :dhanhq_access_token, :ollama_host_url
    attr_reader :ollama_model, :default_symbol, :confidence_threshold, :max_spread_pct

    def self.load
      new.load
    end

    def self.instance
      @instance ||= load
    end

    def initialize
      @dhanhq_client_id = nil
      @dhanhq_access_token = nil
      @ollama_host_url = nil
      @ollama_model = nil
      @default_symbol = nil
      @confidence_threshold = nil
      @max_spread_pct = nil
    end

    def load
      # Validate required ENV first
      Environment.validate!

      # Load from ENV (highest priority)
      @dhanhq_client_id = Environment.dhanhq_client_id
      @dhanhq_access_token = Environment.dhanhq_access_token
      @ollama_host_url = Environment.ollama_host_url

      # Load from config file (lower priority, ENV overrides)
      load_from_file

      self
    end

    def ollama_enabled?
      ollama_host_url && !ollama_host_url.strip.empty?
    end

    def ollama_model
      @ollama_model || "mistral"
    end

    def default_symbol
      @default_symbol || "NIFTY"
    end

    def confidence_threshold
      @confidence_threshold || 0.75
    end

    def max_spread_pct
      @max_spread_pct || 1.0
    end

    def config_file_path
      CONFIG_FILE
    end

    def config_file_exists?
      File.exist?(CONFIG_FILE)
    end

    private

    def load_from_file
      return unless config_file_exists?

      begin
        yaml_data = YAML.safe_load(File.read(CONFIG_FILE), permitted_classes: [Symbol])
        return unless yaml_data.is_a?(Hash)

        # Load Ollama config
        if yaml_data["ollama"].is_a?(Hash)
          @ollama_model = yaml_data["ollama"]["model"] if yaml_data["ollama"]["model"]
          # ENV takes precedence, so don't override if already set
          @ollama_host_url ||= yaml_data["ollama"]["host_url"] if yaml_data["ollama"]["host_url"]
        end

        # Load analysis config
        if yaml_data["analysis"].is_a?(Hash)
          @default_symbol = yaml_data["analysis"]["default_symbol"] if yaml_data["analysis"]["default_symbol"]
          @confidence_threshold = yaml_data["analysis"]["confidence_threshold"] if yaml_data["analysis"]["confidence_threshold"]
        end

        # Load options config
        if yaml_data["options"].is_a?(Hash)
          @max_spread_pct = yaml_data["options"]["max_spread_pct"] if yaml_data["options"]["max_spread_pct"]
        end
      rescue StandardError => e
        warn "Warning: Failed to load config file #{CONFIG_FILE}: #{e.message}"
      end
    end
  end
end
