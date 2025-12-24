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

        # Check for tool calls in the API response first
        if response[:tool_calls]&.any?
          # Only process the first tool call - enforce sequential execution
          if response[:tool_calls].length > 1
            # Warn if multiple tools requested (but only process first one)
            warn "[Agent] Multiple tools requested, but only processing first: #{response[:tool_calls].map do |tc|
              tc.dig("function", "name")
            end.join(", ")}"
          end
          tool_call = response[:tool_calls].first
          return {
            type: "tool_call",
            tool_name: tool_call.dig("function", "name")&.to_sym,
            arguments: parse_tool_arguments(tool_call.dig("function", "arguments")),
            content: response[:content] || ""
          }
        end

        # Check for tool calls embedded in text content (LLM returning JSON in text)
        content = response[:content] || ""
        tool_call_from_text = extract_tool_call_from_text(content)
        if tool_call_from_text
          return {
            type: "tool_call",
            tool_name: tool_call_from_text[:name]&.to_sym,
            arguments: tool_call_from_text[:arguments] || {},
            content: content
          }
        end

        # Check for explicit final answer markers
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
        match = content.match(/confidence[:\s]+([\d.]+)/i)
        if match
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

      def extract_tool_call_from_text(content)
        return nil unless content.is_a?(String)

        # Look for JSON tool calls in markdown code blocks or plain JSON
        # Try to find complete JSON objects with proper bracket matching
        json_patterns = [
          # Markdown code blocks
          /```json\s*(\{.*?\})\s*```/m,
          /```\s*(\{.*?"name".*?\})\s*```/m
        ]

        # First try patterns
        json_patterns.each do |pattern|
          match = content.match(pattern)
          next unless match

          json_str = match[1] || match[0]
          begin
            parsed = JSON.parse(json_str)
            # Check if it looks like a tool call
            if parsed["name"] || parsed["tool_name"] || parsed["function"]
              tool_name = parsed["name"] || parsed["tool_name"] || parsed.dig("function", "name")
              arguments = parsed["arguments"] || parsed["params"] || parsed.dig("function", "arguments") || {}
              return {
                name: tool_name,
                arguments: arguments
              }
            end
          rescue JSON::ParserError
            next
          end
        end

        # If patterns don't work, try to find JSON by matching braces
        # Look for { "name": ... } pattern and extract complete JSON
        if content.match?(/\{[\s\n]*"name"/)
          # Find the start of the JSON object
          start_idx = content.index(/\{[\s\n]*"name"/)
          return nil unless start_idx

          # Try to find the matching closing brace by counting braces
          brace_count = 0
          json_str = ""
          in_string = false
          escape_next = false

          content[start_idx..].each_char do |char|
            if escape_next
              json_str += char
              escape_next = false
              next
            end

            if char == "\\"
              escape_next = true
              json_str += char
              next
            end

            in_string = !in_string if char == '"' && !escape_next

            json_str += char

            next if in_string

            brace_count += 1 if char == "{"
            brace_count -= 1 if char == "}"
            break if brace_count == 0 && json_str.length > 10
          end

          if brace_count == 0 && json_str.length > 10
            begin
              parsed = JSON.parse(json_str)
              if parsed["name"] || parsed["tool_name"] || parsed["function"] || parsed["tool_calls"]
                # Handle different formats
                if parsed["tool_calls"].is_a?(Array) && parsed["tool_calls"].any?
                  tool_call = parsed["tool_calls"].first
                  tool_name = tool_call.dig("function", "name") || tool_call["name"]
                  arguments = tool_call.dig("function", "arguments") || tool_call["arguments"] || {}
                else
                  tool_name = parsed["name"] || parsed["tool_name"] || parsed.dig("function", "name")
                  arguments = parsed["arguments"] || parsed["params"] || parsed.dig("function", "arguments") || {}
                end
                if tool_name
                  return {
                    name: tool_name,
                    arguments: arguments
                  }
                end
              end
            rescue JSON::ParserError
              # Try a simpler approach - just look for the pattern
              if json_str.match?(/"name"\s*:\s*"([^"]+)"/)
                tool_name = ::Regexp.last_match(1)
                # Try to extract arguments
                args_match = json_str.match(/"arguments"\s*:\s*(\{.*?\})/m)
                arguments = {}
                if args_match
                  begin
                    arguments = JSON.parse(args_match[1])
                  rescue JSON::ParserError
                    # Use empty arguments
                  end
                end
                return {
                  name: tool_name,
                  arguments: arguments
                }
              end
            end
          end
        end

        # Also try to extract tool names from text descriptions
        # This is a fallback for when LLM describes tools instead of calling them
        tool_name_patterns = [
          /(?:call|use|execute|run)\s+(?:the\s+)?(?:tool\s+)?([a-z_]+)/i,
          /(?:I\s+will\s+)?(?:first\s+)?(?:validate|check|get|calculate|fetch|analyze)\s+([a-z_]+)/i
        ]

        tool_name_patterns.each do |pattern|
          match = content.match(pattern)
          next unless match

          potential_tool = match[1]
          # Check if it matches common tool name patterns
          if potential_tool.match?(/^(validate|check|get|calculate|fetch|analyze|detect)_/)
            return {
              name: potential_tool,
              arguments: {}
            }
          end
        end

        nil
      end

      def parse_tool_arguments(arguments)
        return {} unless arguments

        parsed = if arguments.is_a?(String)
                   JSON.parse(arguments)
                 elsif arguments.is_a?(Hash)
                   arguments
                 else
                   {}
                 end

        # Normalize keys: convert string keys to symbol keys
        # This ensures compatibility with tool registry validation
        normalize_hash_keys(parsed)
      rescue JSON::ParserError
        {}
      end

      def normalize_hash_keys(hash)
        return {} unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), normalized|
          symbol_key = key.is_a?(String) ? key.to_sym : key
          # Recursively normalize nested hashes
          normalized[symbol_key] = if value.is_a?(Hash)
                                     normalize_hash_keys(value)
                                   elsif value.is_a?(Array)
                                     value.map { |item| item.is_a?(Hash) ? normalize_hash_keys(item) : item }
                                   else
                                     value
                                   end
        end
      end
    end
  end
end
