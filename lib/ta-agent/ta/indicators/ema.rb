# frozen_string_literal: true

# TaAgent::TA::Indicators::EMA
#
# Exponential Moving Average calculator.
#
# Design:
# - Pure function: takes price array, period, returns EMA array
# - Deterministic, no side effects
# - Used by timeframe analyzers
module TaAgent
  module TA
    module Indicators
      class EMA
        # Calculate EMA for a series of prices
        # @param prices [Array<Numeric>] Array of closing prices
        # @param period [Integer] EMA period (e.g., 9, 21, 50, 200)
        # @return [Array<Numeric>] Array of EMA values (same length as prices, nil for first period-1 values)
        def self.calculate(prices, period)
          return [] if prices.empty? || period < 1
          return Array.new(prices.length, nil) if prices.length < period

          ema_values = Array.new(prices.length, nil)
          multiplier = 2.0 / (period + 1.0)

          # First EMA value is simple average of first period values
          sum = prices[0, period].sum
          ema_values[period - 1] = sum / period.to_f

          # Calculate subsequent EMA values
          (period...prices.length).each do |i|
            ema_values[i] = (prices[i] - ema_values[i - 1]) * multiplier + ema_values[i - 1]
          end

          ema_values
        end

        # Get the latest EMA value
        # @param prices [Array<Numeric>] Array of closing prices
        # @param period [Integer] EMA period
        # @return [Numeric, nil] Latest EMA value or nil if insufficient data
        def self.latest(prices, period)
          ema_values = calculate(prices, period)
          ema_values.compact.last
        end
      end
    end
  end
end
