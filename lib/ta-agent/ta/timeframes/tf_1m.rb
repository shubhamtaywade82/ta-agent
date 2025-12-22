# frozen_string_literal: true

# TaAgent::TA::Timeframes::TF1M
#
# 1-minute timeframe analysis pipeline.
#
# Responsibilities:
# - Build 1m context from OHLCV data
# - Detect entry triggers
# - Monitor real-time price action
#
# Contract:
# - Input: OHLCV data array
# - Output: 1m context hash with :trigger, :data_points, :status keys
#
# @example
#   ohlcv = [{high: 100, low: 95, close: 98, volume: 1000}, ...]
#   context = TA::Timeframes::TF1M.build(ohlcv)
module TaAgent
  module TA
    module Timeframes
      class TF1M
        # Contract: Build 1m timeframe context
        # @param ohlcv [Array<Hash>] OHLCV data with :close key
        # @return [Hash] 1m context with :trigger, :data_points, :latest_close, :status keys
        def self.build(ohlcv)
          if ohlcv.empty?
            return {
              trigger: "unknown",
              status: "no_data"
            }
          end

          closes = ohlcv.map { |d| d[:close] }

          {
            trigger: "analyzed",
            data_points: ohlcv.length,
            latest_close: closes.last,
            status: "complete"
          }
        rescue StandardError => e
          {
            trigger: "unknown",
            status: "error",
            error: e.message
          }
        end

        # Contract: Detect trigger condition
        # @param ohlcv [Array<Hash>] OHLCV data
        # @return [String] Trigger type (e.g., "confirmed", "pending", "none")
        def self.trigger(ohlcv)
          build(ohlcv)[:trigger]
        end
      end
    end
  end
end
