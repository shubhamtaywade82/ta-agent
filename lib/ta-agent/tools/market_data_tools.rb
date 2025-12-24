# frozen_string_literal: true

require "date"
require_relative "../market/session"

# TaAgent::Tools::MarketDataTools
#
# Category 1: Market Data Tools (Raw Fetchers)
#
# Responsibilities:
# - Fetch raw market data from DhanHQ
# - Return raw OHLC, option chain, VIX, market status
# - NO computation, NO interpretation
#
# Design:
# - Pure data fetchers
# - Output: Raw arrays/hashes
# - NEVER sent to LLM directly
module TaAgent
  module Tools
    module MarketDataTools
      # Fetch OHLCV data
      # @param client [TaAgent::DhanHQ::Client] DhanHQ client
      # @param symbol [String] Symbol name
      # @param timeframe [String] Timeframe (15, 5, 1)
      # @param days [Integer] Number of days
      # @return [Hash] Raw OHLCV data
      def self.fetch_ohlc(client, symbol:, timeframe:, days:)
        to_date = Date.today
        # For intraday data: from_date <= today - 1 OR last trading date, to_date == today
        min_from_date = Market::Session.last_trading_date
        historical_from_date = to_date - days
        from_date = [min_from_date, historical_from_date].min

        ohlcv = client.fetch_ohlcv(
          symbol: symbol,
          timeframe: timeframe,
          from_date: from_date,
          to_date: to_date
        )

        {
          open: ohlcv.map { |d| d[:open] },
          high: ohlcv.map { |d| d[:high] },
          low: ohlcv.map { |d| d[:low] },
          close: ohlcv.map { |d| d[:close] },
          volume: ohlcv.map { |d| d[:volume] },
          timestamp: ohlcv.map { |d| d[:timestamp] }
        }
      rescue StandardError => e
        { error: e.message }
      end

      # Fetch option chain
      # @param client [TaAgent::DhanHQ::Client] DhanHQ client
      # @param symbol [String] Symbol name
      # @param expiry [Date, String, nil] Expiry date (optional)
      # @return [Hash] Raw option chain data
      def self.fetch_option_chain(client, symbol:, expiry: nil)
        chain = client.fetch_option_chain(symbol: symbol)

        {
          strikes: chain[:strikes] || [],
          expiries: chain[:expiry_dates] || [],
          symbol: symbol
        }
      rescue StandardError => e
        { error: e.message }
      end

      # Fetch India VIX
      # @param client [TaAgent::DhanHQ::Client] DhanHQ client
      # @return [Hash] VIX data
      def self.fetch_india_vix(client)
        # TODO: Implement VIX fetch when DhanHQ API available
        {
          value: nil,
          trend: "unknown"
        }
      end

      # Fetch market status
      # @return [Hash] Market status
      def self.fetch_market_status
        {
          is_open: Market::Session.open?,
          session_type: Market::Session.type,
          current_time: Time.now.strftime("%H:%M")
        }
      end
    end
  end
end

