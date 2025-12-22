# frozen_string_literal: true

require "ruby-technical-analysis"

# TaAgent::TA::Indicators::VWAP
#
# Volume Weighted Average Price (VWAP) indicator.
#
# Wraps ruby-technical-analysis gem for VWAP calculations.
#
# Responsibilities:
# - Calculate VWAP from OHLCV data
# - Determine price position relative to VWAP
#
# Contract:
# - Input: Array of OHLCV hashes with :high, :low, :close, :volume
# - Output: VWAP value or nil if insufficient data
#
# @example
#   ohlcv = [{high: 100, low: 95, close: 98, volume: 1000}, ...]
#   vwap = TA::Indicators::VWAP.calculate(ohlcv)
module TaAgent
  module TA
    module Indicators
      class VWAP
        # Contract: Calculate VWAP from OHLCV data
        # @param ohlcv [Array<Hash>] OHLCV data with :high, :low, :close, :volume keys
        # @return [Float, nil] VWAP value or nil if insufficient data
        def self.calculate(ohlcv)
          return nil if ohlcv.empty?

          # Convert to format expected by gem: array of hashes with date_time
          data = ohlcv.map.with_index do |d, i|
            {
              date_time: Time.now - (ohlcv.length - i) * 86400, # Placeholder dates
              high: d[:high],
              low: d[:low],
              close: d[:close],
              volume: d[:volume]
            }
          end

          vwap_values = RubyTechnicalAnalysis::Vwap.calculate(data)
          return nil if vwap_values.empty?

          # Return the latest VWAP value
          vwap_values.last.vwap
        end

        # Contract: Get latest VWAP value
        # @param ohlcv [Array<Hash>] OHLCV data
        # @return [Float, nil] Latest VWAP value
        def self.latest(ohlcv)
          calculate(ohlcv)
        end

        # Contract: Determine price position relative to VWAP
        # @param price [Float] Current price
        # @param vwap [Float, nil] VWAP value
        # @return [String] "above", "below", or "unknown"
        def self.position(price, vwap)
          return "unknown" if vwap.nil?
          price > vwap ? "above" : "below"
        end
      end
    end
  end
end
