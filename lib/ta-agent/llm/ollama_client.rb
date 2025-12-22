# frozen_string_literal: true

require "faraday"
require "json"

# TaAgent::LLM::OllamaClient
#
# Ollama API client using Faraday.
#
# Responsibilities:
# - Connect to Ollama /api/chat endpoint
# - Handle timeouts gracefully
# - Support tool calling (function calling)
# - Return nil/error if unreachable (non-fatal)
#
# Design:
# - Uses Faraday for HTTP
# - Timeout-safe (5-10s default)
# - Optional - gem works without it
# - Raises TaAgent::OllamaError (non-fatal, can continue)
module TaAgent
  module LLM
    class OllamaClient
      DEFAULT_TIMEOUT = 30
      DEFAULT_MODEL = "mistral"

      attr_reader :host_url, :model

      def initialize(host_url:, model: DEFAULT_MODEL, timeout: DEFAULT_TIMEOUT)
        @host_url = host_url.chomp("/")
        @model = model
        @timeout = timeout
        @conn = build_connection
      end

      # Send chat message to Ollama
      # @param messages [Array<Hash>] Conversation messages with :role, :content, :name keys
      # @param tools [Array<Hash>, nil] Optional tool schemas for function calling
      # @return [Hash, nil] LLM response or nil if error
      def chat(messages:, tools: nil)
        payload = {
          model: @model,
          messages: format_messages(messages),
          stream: false
        }

        # Add tools if provided (Ollama supports function calling)
        payload[:tools] = tools if tools&.any?

        response = @conn.post("/api/chat") do |req|
          req.body = payload.to_json
          req.headers["Content-Type"] = "application/json"
        end

        parse_response(response.body)
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        raise OllamaError, "Ollama connection failed: #{e.message}"
      rescue StandardError => e
        raise OllamaError, "Ollama API error: #{e.message}"
      end

      private

      def build_connection
        Faraday.new(url: @host_url) do |conn|
          conn.request :json
          conn.response :json
          conn.options.timeout = @timeout
          conn.options.open_timeout = 5
        end
      end

      def format_messages(messages)
        messages.map do |msg|
          formatted = {
            role: msg[:role]
          }

          case msg[:role]
          when "system", "user"
            formatted[:content] = msg[:content]
          when "assistant"
            formatted[:content] = msg[:content]
            # Add tool calls if present
            if msg[:tool_calls]&.any?
              formatted[:tool_calls] = msg[:tool_calls]
            end
          when "tool"
            formatted[:name] = msg[:name]
            formatted[:content] = msg[:content]
          end

          formatted
        end
      end

      def parse_response(body)
        return nil unless body

        parsed = body.is_a?(String) ? JSON.parse(body) : body

        {
          content: parsed.dig("message", "content") || "",
          tool_calls: parsed.dig("message", "tool_calls") || [],
          finish_reason: parsed.dig("message", "finish_reason")
        }
      end
    end
  end
end
