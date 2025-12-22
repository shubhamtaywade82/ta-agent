# frozen_string_literal: true

require "json"

# TaAgent::LLM::ResponseParser
#
# Parses LLM responses into structured data.
#
# Responsibilities:
# - Parse LLM response (text or tool calls)
# - Extract structured data (confidence, reasoning, etc.)
# - Handle malformed responses gracefully
# - Detect tool calls vs final answers
#
# Contract:
# - Input: LLM response hash from OllamaClient
# - Output: Parsed response hash with :type, :content, :tool_name, :arguments keys
#
# @example
#   parser = TaAgent::LLM::ResponseParser.new
#   parsed = parser.parse(llm_response)
module TaAgent
  module LLM
    class ResponseParser
      # Contract: Parse LLM response
      # @param response [Hash] LLM response from OllamaClient with :content, :tool_calls keys
      # @return [Hash] Parsed response with :type, :content, :tool_name, :arguments keys
      def parse(response)
        return { type: "error", content: "Empty response" } unless response

        # Check for tool calls first
        if response[:tool_calls]&.any?
          tool_call = response[:tool_calls].first
          return {
            type: "tool_call",
            tool_name: tool_call.dig("function", "name")&.to_sym,
            arguments: parse_tool_arguments(tool_call.dig("function", "arguments")),
            content: response[:content] || ""
          }
        end

        # Check for explicit final answer markers
        content = response[:content] || ""
        if content.match?(/final.*answer|conclusion|recommendation/i) || response[:finish_reason] == "stop"
          return {
            type: "final",
            content: content
          }
        end

        # Default: text response (may continue to tool call)
        {
          type: "text",
          content: content
        }
      end

      # Contract: Extract confidence adjustment from response
      # @param response [Hash] LLM response
      # @return [Float] Confidence adjustment (-1.0 to 1.0)
      def confidence_adjustment(response)
        parsed = parse(response)
        # Try to extract confidence from content
        content = parsed[:content] || ""
        if match = content.match(/confidence[:\s]+([\d.]+)/i)
          match[1].to_f / 100.0
        else
          0.0
        end
      end

      # Contract: Extract reasoning from response
      # @param response [Hash] LLM response
      # @return [String] Reasoning text
      def reasoning(response)
        parsed = parse(response)
        parsed[:content] || ""
      end

      private

      def parse_tool_arguments(arguments)
        return {} unless arguments

        if arguments.is_a?(String)
          JSON.parse(arguments)
        elsif arguments.is_a?(Hash)
          arguments
        else
          {}
        end
      rescue JSON::ParserError
        {}
      end
    end
  end
end

