# frozen_string_literal: true

require "json"

# TaAgent::Output::JSONFormatter
#
# Formats agent output as JSON.
#
# Responsibilities:
# - Convert result hash to JSON
# - Ensure consistent JSON structure
# - Handle errors gracefully
#
# Contract:
# - Input: Agent result hash
# - Output: JSON string
#
# @example
#   formatter = TaAgent::Output::JSONFormatter.new
#   json = formatter.format(result)
#   puts json
module TaAgent
  module Output
    class JSONFormatter
      # Contract: Format agent result as JSON
      # @param result [Hash] Agent result hash
      # @return [String] JSON string
      def format(result)
        JSON.pretty_generate(result)
      end

      # Contract: Format with custom options
      # @param result [Hash] Agent result hash
      # @param pretty [Boolean] Pretty print (default: true)
      # @return [String] JSON string
      def format(result, pretty: true)
        if pretty
          JSON.pretty_generate(result)
        else
          JSON.generate(result)
        end
      end
    end
  end
end
