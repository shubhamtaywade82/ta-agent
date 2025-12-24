# frozen_string_literal: true

require_relative "../dhanhq/client"
require_relative "context_builder"
require_relative "gates"
require_relative "decision"

# TaAgent::Agent::Runner
#
# Core agent execution logic.
#
# Pseudocode flow:
#   build_15m_context
#   abort_if_blocked
#
#   build_5m_context
#   abort_if_blocked
#
#   build_option_chain_context
#   abort_if_empty
#
#   build_1m_context
#
#   if llm_enabled?
#     llm_decision
#   else
#     deterministic_decision
#   end
#
#   format_output
#
# Design:
# - Orchestrates all TA pipelines
# - Applies gates (kill switches)
# - Optionally calls LLM
# - Returns structured result
module TaAgent
  module Agent
    class Runner
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
        @decision = Decision.new(@config, dhanhq_client: @dhanhq_client)
        @result = {
          symbol: @symbol,
          timestamp: Time.now,
          timeframes: {},
          options: nil,
          recommendation: nil,
          confidence: 0.0,
          errors: []
        }
      end

      def run
        # Build context step by step with gates
        context = { symbol: @symbol, timeframes: {}, options: nil, errors: [] }

        # Build 15m context
        context[:timeframes][:tf_15m] = @context_builder.build_15m(symbol: @symbol)
        if @gates.abort_after_15m?(context)
          @result.merge!(context)
          @result[:errors] << "Aborted: 15m data unavailable"
          return @result
        end

        # Build 5m context
        context[:timeframes][:tf_5m] = @context_builder.build_5m(symbol: @symbol)
        if @gates.abort_after_5m?(context)
          @result.merge!(context)
          @result[:errors] << "Aborted: 5m data unavailable"
          return @result
        end

        # Build option chain context
        context[:options] = @context_builder.build_options(symbol: @symbol)
        if @gates.abort_if_empty_options?(context)
          @result.merge!(context)
          @result[:errors] << "Aborted: Options data unavailable"
          return @result
        end

        # Build 1m context
        context[:timeframes][:tf_1m] = @context_builder.build_1m(symbol: @symbol)

        # Make decision
        recommendation = @decision.make(context)

        # Build final result
        @result.merge!(
          timeframes: context[:timeframes],
          options: context[:options],
          recommendation: recommendation,
          confidence: recommendation[:confidence] || 0.0,
          errors: context[:errors]
        )

        @result
      rescue DhanHQError => e
        @result[:errors] << e.message
        @result
      rescue StandardError => e
        @result[:errors] << "Unexpected error: #{e.message}"
        @result
      end
    end
  end
end
