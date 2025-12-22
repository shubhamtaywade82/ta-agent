# frozen_string_literal: true

# TaAgent::Agent::ToolRegistry
#
# Tool registration and schema management.
#
# Responsibilities:
# - Register available tools with schemas
# - Validate tool calls
# - Provide tool metadata to LLM
#
# Design:
# - Tools are READ-ONLY for trading analysis
# - Execution tools (place_order) are gated/disabled in alert mode
# - Each tool has: name, description, params schema
#
# @example
#   registry = ToolRegistry.new(mode: :alert)
#   registry.register(:get_ohlc, ...)
#   tools_json = registry.to_json_schema
module TaAgent
  module Agent
    class ToolRegistry
      attr_reader :mode, :tools

      # @param mode [Symbol] :alert (read-only) or :live (with execution gates)
      def initialize(mode: :alert)
        @mode = mode
        @tools = {}
        register_default_tools
      end

      # Register a tool
      # @param name [Symbol] Tool name
      # @param description [String] Tool description for LLM
      # @param params_schema [Hash] JSON schema for parameters
      # @param handler [Proc] Tool execution handler
      # @param enabled [Boolean] Whether tool is enabled in current mode
      def register(name, description:, params_schema:, handler:, enabled: true)
        @tools[name] = {
          description: description,
          params_schema: params_schema,
          handler: handler,
          enabled: enabled && tool_allowed_in_mode?(name)
        }
      end

      # Get tool by name
      # @param name [Symbol] Tool name
      # @return [Hash, nil] Tool definition or nil
      def get(name)
        tool = @tools[name]
        return nil unless tool
        return nil unless tool[:enabled]
        tool
      end

      # Check if tool is available
      # @param name [Symbol] Tool name
      # @return [Boolean] True if tool is registered and enabled
      def available?(name)
        tool = get(name)
        !tool.nil?
      end

      # Convert tools to JSON schema format for LLM
      # @return [Array<Hash>] Array of tool schemas
      def to_json_schema
        @tools.select { |_name, tool| tool[:enabled] }.map do |name, tool|
          {
            type: "function",
            function: {
              name: name.to_s,
              description: tool[:description],
              parameters: {
                type: "object",
                properties: tool[:params_schema],
                required: tool[:params_schema].keys.select { |k| tool[:params_schema][k][:required] }
              }
            }
          }
        end
      end

      # Execute a tool
      # @param name [Symbol] Tool name
      # @param arguments [Hash] Tool arguments
      # @return [Hash] Tool result with :success, :data, :error keys
      def execute(name, arguments)
        tool = get(name)
        unless tool
          return {
            success: false,
            error: "Tool '#{name}' not found or disabled"
          }
        end

        # Validate arguments
        validation_error = validate_arguments(name, arguments, tool[:params_schema])
        if validation_error
          return {
            success: false,
            error: "Invalid arguments: #{validation_error}"
          }
        end

        # Execute tool handler
        begin
          result = tool[:handler].call(arguments)
          {
            success: true,
            data: result
          }
        rescue StandardError => e
          {
            success: false,
            error: e.message
          }
        end
      end

      private

      def register_default_tools
        # Analysis tools - always available in alert mode
        register(
          :validate_signal_alignment,
          description: "Check if signals across timeframes (15m, 5m, 1m) are aligned and consistent",
          params_schema: {
            tf_15m: { type: "object", description: "15m timeframe context with bias, trend_strength", required: true },
            tf_5m: { type: "object", description: "5m timeframe context with setup_type, momentum_alignment", required: true },
            tf_1m: { type: "object", description: "1m timeframe context with entry_signal", required: true }
          },
          handler: ->(args) {
            tf_15m = args[:tf_15m] || {}
            tf_5m = args[:tf_5m] || {}
            tf_1m = args[:tf_1m] || {}

            aligned = true
            contradictions = []

            # Check bias alignment
            if tf_15m[:bias] == "bullish" && tf_5m[:setup_type] == "bearish_setup"
              aligned = false
              contradictions << "15m bullish but 5m bearish setup"
            end

            # Check momentum alignment
            unless tf_5m[:momentum_alignment]
              aligned = false
              contradictions << "5m momentum not aligned with 15m"
            end

            # Check entry signal
            if tf_1m[:entry_signal] != "confirmed"
              aligned = false
              contradictions << "1m entry signal not confirmed"
            end

            {
              success: true,
              data: {
                aligned: aligned,
                contradictions: contradictions,
                recommendation: aligned ? "proceed" : "wait"
              }
            }
          },
          enabled: true
        )

        register(
          :check_market_conditions,
          description: "Validate market conditions (volatility, trend strength, liquidity) are suitable for options trading",
          params_schema: {
            volatility: { type: "string", description: "Volatility state (expanding, contracting, stable)", required: true },
            trend_strength: { type: "string", description: "Trend strength (strong, weak, unknown)", required: true },
            liquidity_score: { type: "number", description: "Liquidity score (0-10)", required: true }
          },
          handler: ->(args) {
            suitable = true
            warnings = []

            if args[:volatility] == "contracting"
              suitable = false
              warnings << "Volatility contracting - poor for options"
            end

            if args[:trend_strength] == "weak"
              warnings << "Weak trend - lower confidence"
            end

            if args[:liquidity_score] < 5.0
              suitable = false
              warnings << "Low liquidity - avoid trading"
            end

            {
              success: true,
              data: {
                suitable: suitable,
                warnings: warnings,
                recommendation: suitable ? "proceed" : "avoid"
              }
            }
          },
          enabled: true
        )

        register(
          :detect_contradictions,
          description: "Detect contradictions in trading signals that might indicate false signals",
          params_schema: {
            signals: { type: "object", description: "All trading signals from different timeframes", required: true }
          },
          handler: ->(args) {
            signals = args[:signals] || {}
            contradictions = []

            # Example contradiction checks
            if signals[:tf_15m_bias] == "bullish" && signals[:tf_5m_setup] == "bearish"
              contradictions << "Bias mismatch between 15m and 5m"
            end

            {
              success: true,
              data: {
                contradictions: contradictions,
                has_contradictions: !contradictions.empty?,
                recommendation: contradictions.empty? ? "signals_consistent" : "signals_conflicting"
              }
            }
          },
          enabled: true
        )

        # Execution tools - only in live mode with gates
        register(
          :place_order,
          description: "Place a trade order (GATED - only in live mode with risk checks). DO NOT USE unless explicitly authorized.",
          params_schema: {
            symbol: { type: "string", required: true },
            side: { type: "string", enum: ["buy", "sell"], required: true },
            qty: { type: "integer", required: true },
            price: { type: "number", required: false },
            strike: { type: "string", required: true },
            option_type: { type: "string", enum: ["CE", "PE"], required: true }
          },
          handler: ->(args) {
            {
              success: false,
              error: "Execution tools are disabled in alert mode. This is a safety feature."
            }
          },
          enabled: @mode == :live
        )
      end

      def tool_allowed_in_mode?(name)
        # Execution tools only allowed in live mode
        execution_tools = [:place_order, :modify_order, :cancel_order]
        return true unless execution_tools.include?(name)
        @mode == :live
      end

      def validate_arguments(name, arguments, schema)
        schema.each do |param_name, param_def|
          if param_def[:required] && !arguments.key?(param_name)
            return "Missing required parameter: #{param_name}"
          end

          if arguments.key?(param_name)
            expected_type = param_def[:type]
            actual_value = arguments[param_name]

            case expected_type
            when "string"
              return "Parameter #{param_name} must be a string" unless actual_value.is_a?(String)
            when "integer"
              return "Parameter #{param_name} must be an integer" unless actual_value.is_a?(Integer)
            when "number"
              return "Parameter #{param_name} must be a number" unless actual_value.is_a?(Numeric)
            when "array"
              return "Parameter #{param_name} must be an array" unless actual_value.is_a?(Array)
            when "object"
              return "Parameter #{param_name} must be an object/hash" unless actual_value.is_a?(Hash)
            end
          end
        end

        nil
      end
    end
  end
end
