# frozen_string_literal: true

# TaAgent::Agent::Decision
#
# Decision making logic (deterministic + optional LLM).
#
# Responsibilities:
# - Make deterministic decisions from context
# - Optionally enhance with LLM analysis
# - Generate recommendation hash
#
# Contract:
# - Input: Complete agent context
# - Output: Recommendation hash with action, confidence, etc.
#
# @example
#   decision = TaAgent::Agent::Decision.new(config)
#   recommendation = decision.make(context)
module TaAgent
  module Agent
    class Decision
      # Contract: Initialize with config
      # @param config [TaAgent::Config] Configuration instance
      def initialize(config)
        @config = config
      end

      # Contract: Make decision from context
      # @param context [Hash] Complete agent context
      # @return [Hash] Recommendation with :action, :confidence, :reason, :strike keys
      def make(context)
        base_decision = deterministic(context)

        # Optionally enhance with LLM if enabled
        if @config.ollama_enabled?
          begin
            with_llm(context, base_decision)
          rescue OllamaError => e
            # LLM failed, use deterministic decision
            base_decision
          end
        else
          base_decision
        end
      end

      # Contract: Make deterministic decision (no LLM)
      # @param context [Hash] Agent context
      # @return [Hash] Deterministic recommendation with :action, :confidence, :reason, :strike, :entry keys
      def deterministic(context)
        tf_15m = context[:timeframes][:tf_15m] || {}
        tf_5m = context[:timeframes][:tf_5m] || {}
        tf_1m = context[:timeframes][:tf_1m] || {}

        # Basic decision logic based on 15m trend
        if tf_15m[:status] == "complete" && tf_15m[:trend] == "bullish"
          confidence = 0.6
          if tf_5m[:status] == "complete" && tf_5m[:ema_9] && tf_15m[:ema_9]
            # 5m EMA above 15m EMA = stronger bullish
            if tf_5m[:ema_9] > tf_15m[:ema_9]
              confidence = 0.75
            end
          end

          {
            action: "buy",
            reason: "15m trend is bullish#{tf_15m[:ema_9] && tf_15m[:ema_21] ? " (EMA 9: #{tf_15m[:ema_9].round(2)} > EMA 21: #{tf_15m[:ema_21].round(2)})" : ""}",
            strike: nil,
            entry: tf_1m[:latest_close],
            stop_loss: nil,
            target: nil
          }.merge(confidence: confidence)
        elsif tf_15m[:status] == "complete" && tf_15m[:trend] == "bearish"
          {
            action: "sell",
            reason: "15m trend is bearish#{tf_15m[:ema_9] && tf_15m[:ema_21] ? " (EMA 9: #{tf_15m[:ema_9].round(2)} < EMA 21: #{tf_15m[:ema_21].round(2)})" : ""}",
            strike: nil,
            entry: tf_1m[:latest_close],
            stop_loss: nil,
            target: nil,
            confidence: 0.6
          }
        else
          {
            action: "wait",
            reason: tf_15m[:status] == "error" ? "Data fetch error" : "Trend unclear or neutral",
            strike: nil,
            entry: nil,
            stop_loss: nil,
            target: nil,
            confidence: 0.0
          }
        end
      end

      # Contract: Enhance decision with LLM (if enabled)
      # @param context [Hash] Agent context
      # @param base_decision [Hash] Base deterministic decision
      # @return [Hash] Enhanced recommendation
      def with_llm(context, base_decision)
        # TODO: Implement LLM enhancement
        # For now, return base decision
        base_decision
      end
    end
  end
end
