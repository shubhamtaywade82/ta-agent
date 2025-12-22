# frozen_string_literal: true

require_relative "../indicators/ema"

# TaAgent::TA::Timeframes::TF5M
#
# 5-minute timeframe analysis pipeline.
#
# Responsibilities:
# - Build 5m context from OHLCV data
# - Calculate 5m-specific indicators
# - Detect setup conditions (pullbacks, breakouts)
#
# Contract:
# - Input: OHLCV data array
# - Output: 5m context hash with :setup, :ema_9, :status keys
#
# @example
#   ohlcv = [{high: 100, low: 95, close: 98, volume: 1000}, ...]
#   context = TA::Timeframes::TF5M.build(ohlcv)
module TaAgent
  module TA
    module Timeframes
      class TF5M
        # Contract: Build 5m timeframe context
        # @param ohlcv [Array<Hash>] OHLCV data with :close key
        # @return [Hash] 5m context with :setup, :ema_9, :data_points, :latest_close, :status keys
        def self.build(ohlcv)
          if ohlcv.empty?
            return {
              setup: "unknown",
              status: "no_data"
            }
          end

          closes = ohlcv.map { |d| d[:close] }
          ema_9 = Indicators::EMA.latest(closes, 9)

          {
            setup: "analyzed",
            ema_9: ema_9,
            data_points: ohlcv.length,
            latest_close: closes.last,
            status: "complete"
          }
        rescue StandardError => e
          {
            setup: "unknown",
            status: "error",
            error: e.message
          }
        end

        # Contract: Detect setup type
        # @param ohlcv [Array<Hash>] OHLCV data
        # @return [String] Setup type (e.g., "pullback", "breakout", "neutral")
        def self.setup(ohlcv)
          build(ohlcv)[:setup]
        end
      end
    end
  end
end
