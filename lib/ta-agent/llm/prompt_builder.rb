# frozen_string_literal: true

require "json"
require_relative "../agent/context_contracts"

# TaAgent::LLM::PromptBuilder
#
# Builds structured prompts for LLM analysis.
#
# Responsibilities:
# - Format pre-computed, decision-ready facts (NOT raw data)
# - Create trading brief for LLM
# - Request structured decision output
#
# Design:
# - NO raw OHLC arrays
# - NO indicator arrays
# - Compressed, structured JSON only
# - LLM = reasoning + synthesis, NOT computation
#
# @example
#   builder = TaAgent::LLM::PromptBuilder.new
#   prompt = builder.build(structured_context)
module TaAgent
  module LLM
    class PromptBuilder
      # Build analysis prompt from structured context
      # @param structured_context [Hash] Pre-computed context with tf_15m, tf_5m, tf_1m, option_strikes, market_conditions
      # @return [String] Formatted prompt for LLM
      def build(structured_context)
        prompt_parts = []

        # System instruction
        prompt_parts << build_system_instruction

        # Trading brief (structured JSON)
        prompt_parts << "\n## TRADING BRIEF\n"
        prompt_parts << JSON.pretty_generate(structured_context)

        # Decision request
        prompt_parts << "\n## YOUR TASK\n"
        prompt_parts << build_decision_request

        prompt_parts.join("\n")
      end

      # Format structured context for LLM
      # @param structured_context [Hash] Pre-computed context
      # @return [String] Formatted context summary
      def format_context(structured_context)
        JSON.pretty_generate(structured_context)
      end

      private

      def build_system_instruction
        <<~INSTRUCTION
          You are a professional options trading analyst for Indian markets (NIFTY).

          CRITICAL RULES:
          1. You receive PRE-COMPUTED facts, not raw data
          2. You do NOT compute indicators or scan candles
          3. Your job: reasoning + contradiction detection + synthesis
          4. All math and indicators are already calculated by the system

          Your role: Validate signals, detect contradictions, provide confidence score.
          You are NOT a trading engine. You are an analyst.
        INSTRUCTION
      end

      def build_decision_request
        <<~REQUEST
          Based on the trading brief above, provide your analysis:

          Required output (JSON format):
          {
            "decision": "enter | wait | no_trade",
            "confidence": 0.0-1.0,
            "reasoning": [
              "Fact 1 from 15m context",
              "Fact 2 from 5m setup",
              "Fact 3 from 1m trigger",
              "Fact 4 from option strikes"
            ],
            "preferred_strike": "22500 CE" (or null if no_trade),
            "entry_guidance": "Buy on hold above 105" (or null if no_trade)
          }

          Decision criteria:
          - "enter": All gates passed, signals aligned, confidence >= 0.7
          - "wait": Signals forming but not confirmed, confidence 0.5-0.7
          - "no_trade": Contradictions detected, low confidence, or gates failed

          If confidence < 0.7 → recommend "wait" or "no_trade"
        REQUEST
      end
    end
  end
end

