# frozen_string_literal: true

require_relative "../indicators/ema"

# TaAgent::TA::Timeframes::TF15M
#
# 15-minute timeframe analyzer.
#
# Responsibilities:
# - Build 15m context from OHLCV data
# - Calculate indicators (EMA 9, EMA 21)
# - Detect trend direction
# - Return structured context
#
# Contract:
# - Input: OHLCV data array
# - Output: 15m context hash with :trend, :ema_9, :ema_21, :status keys
#
# @example
#   ohlcv = [{high: 100, low: 95, close: 98, volume: 1000}, ...]
#   context = TA::Timeframes::TF15M.build(ohlcv)
module TaAgent
  module TA
    module Timeframes
      class TF15M
        # Contract: Build 15m timeframe context
        # @param ohlcv [Array<Hash>] OHLCV data with :close key
        # @return [Hash] 15m context with :trend, :ema_9, :ema_21, :data_points, :latest_close, :status keys
        def self.build(ohlcv)
          if ohlcv.empty?
            return {
              trend: "unknown",
              status: "no_data",
              error: "No data available"
            }
          end

          # Extract closing prices
          closes = ohlcv.map { |d| d[:close] }

          # Calculate EMAs
          ema_9 = Indicators::EMA.latest(closes, 9)
          ema_21 = Indicators::EMA.latest(closes, 21)

          # Determine trend
          trend = if ema_9 && ema_21
                    if ema_9 > ema_21
                      "bullish"
                    elsif ema_9 < ema_21
                      "bearish"
                    else
                      "neutral"
                    end
                  else
                    "neutral"
                  end

          {
            trend: trend,
            ema_9: ema_9,
            ema_21: ema_21,
            data_points: ohlcv.length,
            latest_close: closes.last,
            status: "complete"
          }
        rescue StandardError => e
          {
            trend: "unknown",
            status: "error",
            error: e.message
          }
        end
      end
    end
  end
end

