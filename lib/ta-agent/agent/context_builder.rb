# frozen_string_literal: true

require "date"
require_relative "../dhanhq/client"
require_relative "../market/session"
require_relative "../ta/timeframes/tf_15m"
require_relative "../ta/timeframes/tf_5m"
require_relative "../ta/timeframes/tf_1m"

# TaAgent::Agent::ContextBuilder
#
# Builds comprehensive agent context from multiple data sources.
#
# Responsibilities:
# - Orchestrate data fetching across timeframes
# - Build unified context hash
# - Handle errors gracefully
#
# Contract:
# - Input: Symbol and DhanHQ client
# - Output: Complete context hash for decision making
#
# @example
#   builder = TaAgent::Agent::ContextBuilder.new(dhanhq_client)
#   context = builder.build(symbol: "NIFTY")
module TaAgent
  module Agent
    class ContextBuilder
      # Contract: Initialize with DhanHQ client
      # @param client [TaAgent::DhanHQ::Client] DhanHQ client instance
      def initialize(client)
        @client = client
      end

      # Contract: Build complete agent context
      # @param symbol [String] Symbol name
      # @return [Hash] Complete context with :timeframes, :options, :market keys
      def build(symbol:)
        context = {
          symbol: symbol.upcase,
          timeframes: {},
          options: nil,
          errors: []
        }

        context[:timeframes][:tf_15m] = build_15m(symbol: symbol)
        context[:timeframes][:tf_5m] = build_5m(symbol: symbol)
        context[:timeframes][:tf_1m] = build_1m(symbol: symbol)
        context[:options] = build_options(symbol: symbol)

        context
      end

      # Contract: Build 15m context
      # @param symbol [String] Symbol name
      # @return [Hash] 15m timeframe context
      def build_15m(symbol:)
        to_date = Date.today
        # For intraday data: from_date <= today - 1 OR last trading date, to_date == today
        # For 15m, fetch at least 30 days but ensure from_date respects last trading date
        min_from_date = last_trading_date
        historical_from_date = to_date - 30
        from_date = [min_from_date, historical_from_date].min

        ohlcv_data = @client.fetch_ohlcv(
          symbol: symbol,
          timeframe: "15",
          from_date: from_date,
          to_date: to_date
        )

        TA::Timeframes::TF15M.build(ohlcv_data)
      rescue DhanHQError => e
        {
          trend: "unknown",
          status: "error",
          error: e.message
        }
      end

      # Contract: Build 5m context
      # @param symbol [String] Symbol name
      # @return [Hash] 5m timeframe context
      def build_5m(symbol:)
        to_date = Date.today
        # For intraday data: from_date <= today - 1 OR last trading date, to_date == today
        # For 5m, fetch at least 7 days but ensure from_date respects last trading date
        min_from_date = last_trading_date
        historical_from_date = to_date - 7
        from_date = [min_from_date, historical_from_date].min

        ohlcv_data = @client.fetch_ohlcv(
          symbol: symbol,
          timeframe: "5",
          from_date: from_date,
          to_date: to_date
        )

        TA::Timeframes::TF5M.build(ohlcv_data)
      rescue DhanHQError => e
        {
          setup: "unknown",
          status: "error",
          error: e.message
        }
      end

      # Contract: Build 1m context
      # @param symbol [String] Symbol name
      # @return [Hash] 1m timeframe context
      def build_1m(symbol:)
        to_date = Date.today
        # For 1m intraday: from_date <= today - 1 OR last trading date, to_date == today
        from_date = last_trading_date

        ohlcv_data = @client.fetch_ohlcv(
          symbol: symbol,
          timeframe: "1",
          from_date: from_date,
          to_date: to_date
        )

        TA::Timeframes::TF1M.build(ohlcv_data)
      rescue DhanHQError => e
        {
          trigger: "unknown",
          status: "error",
          error: e.message
        }
      end

      # Contract: Build option chain context
      # @param symbol [String] Symbol name
      # @return [Hash] Option chain context
      def build_options(symbol:)
        # TODO: Implement option chain fetching when DhanHQ API is available
        {
          strikes: [],
          best_strike: nil,
          status: "pending"
        }
      end

      private

      # Get last trading date for Indian markets
      # Delegates to Market::Session.last_trading_date
      # @return [Date] Last trading date (minimum: today - 1)
      def last_trading_date
        Market::Session.last_trading_date
      end
    end
  end
end
