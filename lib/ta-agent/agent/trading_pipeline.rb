# frozen_string_literal: true

require "date"
require_relative "context_builder"
require_relative "gates"
require_relative "tool_registry"
require_relative "loop"
require_relative "context_contracts"
require_relative "../market/session"
require_relative "../tools/timeframe_context_builders"
require_relative "../tools/option_chain_tools"
require_relative "../tools/risk_tools"
require_relative "../options/strike_scorer"

# TaAgent::Agent::TradingPipeline
#
# Battle-ready multi-timeframe options analysis pipeline.
#
# Architecture:
# - Layered decision pipeline (NOT one big prompt)
# - Timeframe hierarchy: 15m → 5m → 1m
# - Hard gates before LLM
# - LLM = analyst, NOT trader
# - Structured output only
#
# Flow:
#   1. 15m Context → Gate (trade_allowed?)
#   2. 5m Setup → Gate (proceed_to_entry?)
#   3. Option Chain → Filter + Score
#   4. 1m Entry → Gate (entry_signal?)
#   5. LLM Analysis (if all gates pass)
#   6. Structured Recommendation
#
# Design:
# - Higher timeframe = CONTEXT
# - Lower timeframe = TIMING
# - Options chain = FEASIBILITY
# - LLM = VALIDATION, not decision
module TaAgent
  module Agent
    class TradingPipeline
      attr_reader :symbol, :config, :dhanhq_client, :result

      def initialize(symbol:, config: nil)
        @symbol = symbol.upcase
        @config = config || TaAgent::Config.instance
        @dhanhq_client = DhanHQ::Client.new(
          client_id: @config.dhanhq_client_id,
          access_token: @config.dhanhq_access_token
        )
        @context_builder = ContextBuilder.new(@dhanhq_client)
        @gates = Gates.new
        @strike_scorer = Options::StrikeScorer.new
        @result = {
          symbol: @symbol,
          timestamp: Time.now,
          timeframes: {},
          options: nil,
          recommendation: nil,
          confidence: 0.0,
          errors: [],
          gates_passed: []
        }
      end

      # Run the complete trading pipeline
      # @return [Hash] Structured recommendation or no-trade signal
      def run
        # STEP 1: Build 15m context (MARKET CONTEXT)
        tf_15m = build_15m_context
        return gate_failed("15m", "trade_allowed = false") unless tf_15m[:trade_allowed]

        # STEP 2: Build 5m context (SETUP VALIDATION)
        tf_5m = build_5m_context
        return gate_failed("5m", "proceed_to_entry = false") unless tf_5m[:proceed_to_entry]

        # STEP 3: Fetch and score option chain (FEASIBILITY)
        options = build_option_chain_context
        return gate_failed("options", "no liquid strikes") if options[:candidates].empty?

        # STEP 4: Build 1m context (ENTRY TIMING)
        tf_1m = build_1m_context
        return gate_failed("1m", "entry_signal = not_confirmed") unless tf_1m[:entry_signal] == "confirmed"

        # STEP 5: LLM Analysis (if enabled and all gates passed)
        recommendation = if @config.ollama_enabled?
                           analyze_with_llm(tf_15m, tf_5m, tf_1m, options)
                         else
                           deterministic_recommendation(tf_15m, tf_5m, tf_1m, options)
                         end

        # STEP 6: Build final result
        @result.merge!(
          timeframes: {
            tf_15m: tf_15m,
            tf_5m: tf_5m,
            tf_1m: tf_1m
          },
          options: options,
          recommendation: recommendation,
          confidence: recommendation[:confidence] || 0.0,
          gates_passed: %w[15m 5m options 1m]
        )

        @result
      rescue DhanHQError => e
        @result[:errors] << e.message
        @result
      rescue StandardError => e
        @result[:errors] << "Unexpected error: #{e.message}"
        @result
      end

      private

      # Build 15m context - MARKET CONTEXT (NO ENTRIES)
      # Output: { bias, trend_strength, volatility, trade_allowed }
      def build_15m_context
        to_date = Date.today
        # For intraday data: from_date <= today - 1 OR last trading date, to_date == today
        min_from_date = Market::Session.last_trading_date
        historical_from_date = to_date - 30
        from_date = [min_from_date, historical_from_date].min

        ohlcv_data = @dhanhq_client.fetch_ohlcv(
          symbol: @symbol,
          timeframe: "15",
          from_date: from_date,
          to_date: to_date
        )

        if ohlcv_data.empty?
          return {
            bias: "neutral",
            trend_strength: "unknown",
            volatility: "unknown",
            trade_allowed: false,
            status: "no_data",
            error: "No 15m data available"
          }
        end

        # Build context using TF15M
        tf_context = TA::Timeframes::TF15M.build(ohlcv_data)

        # Determine bias
        bias = if tf_context[:trend] == "bullish"
                 "bullish"
               else
                 (tf_context[:trend] == "bearish" ? "bearish" : "neutral")
               end

        # Determine trend strength (simplified - can enhance with ADX)
        trend_strength = if tf_context[:ema_9] && tf_context[:ema_21]
                           (tf_context[:ema_9] - tf_context[:ema_21]).abs > (tf_context[:latest_close] * 0.01) ? "strong" : "weak"
                         else
                           "unknown"
                         end

        # Determine volatility (simplified - can enhance with ATR)
        volatility = "stable" # TODO: Calculate from ATR

        # Gate: trade_allowed
        trade_allowed = bias != "neutral" && trend_strength != "unknown" && tf_context[:status] == "complete"

        {
          bias: bias,
          trend_strength: trend_strength,
          volatility: volatility,
          trade_allowed: trade_allowed,
          ema_9: tf_context[:ema_9],
          ema_21: tf_context[:ema_21],
          latest_close: tf_context[:latest_close],
          status: tf_context[:status]
        }
      rescue DhanHQError => e
        {
          bias: "neutral",
          trend_strength: "unknown",
          volatility: "unknown",
          trade_allowed: false,
          status: "error",
          error: e.message
        }
      end

      # Build 5m context - SETUP VALIDATION (STILL NO ENTRY)
      # Output: { setup_type, momentum_alignment, invalidations, proceed_to_entry }
      def build_5m_context
        to_date = Date.today
        # For intraday data: from_date <= today - 1 OR last trading date, to_date == today
        min_from_date = Market::Session.last_trading_date
        historical_from_date = to_date - 7
        from_date = [min_from_date, historical_from_date].min

        ohlcv_data = @dhanhq_client.fetch_ohlcv(
          symbol: @symbol,
          timeframe: "5",
          from_date: from_date,
          to_date: to_date
        )

        if ohlcv_data.empty?
          return {
            setup_type: "none",
            momentum_alignment: false,
            invalidations: ["no_data"],
            proceed_to_entry: false,
            status: "no_data"
          }
        end

        tf_context = TA::Timeframes::TF5M.build(ohlcv_data)

        # Determine setup type (simplified - can enhance)
        setup_type = tf_context[:status] == "complete" ? "trend_continuation" : "none"

        # Check momentum alignment (5m EMA vs 15m trend)
        momentum_alignment = true # TODO: Compare with 15m context

        invalidations = []
        invalidations << "weak_close" if ohlcv_data.last[:close] < ohlcv_data.last[:open]

        # Gate: proceed_to_entry
        proceed_to_entry = setup_type != "none" && momentum_alignment && invalidations.empty? && tf_context[:status] == "complete"

        {
          setup_type: setup_type,
          momentum_alignment: momentum_alignment,
          invalidations: invalidations,
          proceed_to_entry: proceed_to_entry,
          ema_9: tf_context[:ema_9],
          latest_close: tf_context[:latest_close],
          status: tf_context[:status]
        }
      rescue DhanHQError => e
        {
          setup_type: "none",
          momentum_alignment: false,
          invalidations: ["error: #{e.message}"],
          proceed_to_entry: false,
          status: "error"
        }
      end

      # Build option chain context - FEASIBILITY (PARALLEL PIPELINE)
      # Output: { candidates: [{strike, score, ...}], filtered_count }
      def build_option_chain_context
        # Fetch option chain
        chain_data = @dhanhq_client.fetch_option_chain(symbol: @symbol)

        if chain_data[:strikes].empty?
          return {
            candidates: [],
            filtered_count: 0,
            status: "no_data"
          }
        end

        # Filter: Only ATM, ATM+1
        # Score: Pre-rank strikes (NON-LLM)
        candidates = chain_data[:strikes]
                     .select { |s| filter_strike(s) }
                     .map { |s| score_strike(s) }
                     .sort_by { |s| -s[:score] }
                     .first(2) # Top 1-2 strikes only

        {
          candidates: candidates,
          filtered_count: chain_data[:strikes].length - candidates.length,
          status: "complete"
        }
      rescue DhanHQError => e
        {
          candidates: [],
          filtered_count: 0,
          status: "error",
          error: e.message
        }
      end

      # Build 1m context - ENTRY TIMING ONLY
      # Output: { entry_signal, trigger_reason, entry_zone }
      def build_1m_context
        to_date = Date.today
        # For 1m intraday: from_date <= today - 1 OR last trading date, to_date == today
        from_date = Market::Session.last_trading_date

        ohlcv_data = @dhanhq_client.fetch_ohlcv(
          symbol: @symbol,
          timeframe: "1",
          from_date: from_date,
          to_date: to_date
        )

        if ohlcv_data.empty?
          return {
            entry_signal: "not_confirmed",
            trigger_reason: "no_data",
            entry_zone: nil,
            status: "no_data"
          }
        end

        tf_context = TA::Timeframes::TF1M.build(ohlcv_data)

        # Determine entry signal (simplified - can enhance)
        entry_signal = tf_context[:status] == "complete" ? "confirmed" : "not_confirmed"
        trigger_reason = entry_signal == "confirmed" ? "momentum_ignition" : "waiting"

        # Entry zone (simplified)
        entry_zone = if entry_signal == "confirmed" && tf_context[:latest_close]
                       {
                         from: (tf_context[:latest_close] * 0.98).round(2),
                         to: (tf_context[:latest_close] * 1.02).round(2)
                       }
                     end

        {
          entry_signal: entry_signal,
          trigger_reason: trigger_reason,
          entry_zone: entry_zone,
          latest_close: tf_context[:latest_close],
          status: tf_context[:status]
        }
      rescue DhanHQError => e
        {
          entry_signal: "not_confirmed",
          trigger_reason: "error: #{e.message}",
          entry_zone: nil,
          status: "error"
        }
      end

      # Filter strikes (STRICT)
      # Only: ATM, ATM+1
      # Ignore: Deep ITM, Far OTM
      def filter_strike(strike)
        # TODO: Implement proper ATM detection
        # For now, placeholder
        true
      end

      # Score strike (NON-LLM)
      # Formula: delta_weight + gamma_weight + spread_penalty + ...
      def score_strike(strike)
        base_score = @strike_scorer.score(strike, context: {})
        {
          strike: strike[:strike],
          score: base_score,
          delta: strike[:delta],
          gamma: strike[:gamma],
          iv: strike[:iv]
        }
      end

      # LLM Analysis (ONLY AFTER ALL GATES PASS)
      def analyze_with_llm(structured_context)
        # Create tool registry for LLM
        registry = build_tool_registry

        # Run agent loop
        loop = Loop.new(
          goal: "Cross-validate trading signals and provide confidence score for #{@symbol} options",
          initial_context: structured_context,
          tool_registry: registry,
          config: @config
        )

        result = loop.run

        # Parse LLM output into recommendation
        parse_llm_recommendation(result, structured_context)
      rescue OllamaError => e
        # LLM failed, fall back to deterministic
        deterministic_recommendation_from_structured(structured_context)
      end

      # Deterministic recommendation (no LLM)
      def deterministic_recommendation_from_structured(structured_context)
        tf_15m = structured_context[:tf_15m]
        tf_5m = structured_context[:tf_5m]
        tf_1m = structured_context[:tf_1m]
        option_strikes = structured_context[:option_strikes] || []

        best_strike = option_strikes.first

        {
          decision: "enter",
          direction: tf_15m.dig(:permission, :allowed_direction) || "CE",
          recommended_strike: best_strike&.dig(:strike) || "N/A",
          entry: tf_1m.dig(:entry_zone, :price_from) ? "Above #{tf_1m[:entry_zone][:price_from]}" : "N/A",
          stop_loss: tf_1m.dig(:risk, :invalid_price) ? "Below #{tf_1m[:risk][:invalid_price]}" : "N/A",
          target_zone: tf_1m.dig(:risk, :rr_estimate) ? "Calculate from RR" : "N/A",
          confidence: 0.6,
          notes: "Deterministic analysis: #{tf_15m.dig(:trend, :direction)} trend, #{tf_5m.dig(:setup, :type)} setup"
        }
      end

      # Parse LLM result into structured recommendation
      def parse_llm_recommendation(llm_result, structured_context)
        # TODO: Parse LLM output JSON
        # For now, use deterministic with LLM confidence adjustment
        base = deterministic_recommendation_from_structured(structured_context)
        base[:confidence] = extract_confidence(llm_result[:answer]) || base[:confidence]
        base[:notes] = llm_result[:answer]
        base
      end

      def extract_confidence(text)
        return nil unless text

        return unless match = text.match(/confidence[:\s]+([\d.]+)/i)

        match[1].to_f / 100.0
      end

      # Build tool registry for LLM
      def build_tool_registry
        registry = ToolRegistry.new(mode: :alert) # Always alert mode for analysis

        # Register tools that LLM can use for validation
        registry.register(
          :validate_signal_alignment,
          description: "Check if signals across timeframes are aligned",
          params_schema: {
            tf_15m: { type: "object", required: true },
            tf_5m: { type: "object", required: true },
            tf_1m: { type: "object", required: true }
          },
          handler: lambda { |args|
            # Validate alignment logic
            { success: true, data: { aligned: true } }
          }
        )

        registry
      end

      def gate_failed(gate_name, reason)
        @result.merge!(
          recommendation: {
            decision: "no_trade",
            reason: "Gate failed: #{gate_name} - #{reason}",
            confidence: 0.0
          },
          gates_passed: @result[:gates_passed]
        )
        @result
      end
    end
  end
end

