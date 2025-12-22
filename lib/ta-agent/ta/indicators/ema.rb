# frozen_string_literal: true

require "ruby-technical-analysis"

# TaAgent::TA::Indicators::EMA
#
# Exponential Moving Average calculator.
#
# Wraps ruby-technical-analysis gem for EMA calculations.
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

          moving_averages = RubyTechnicalAnalysis::MovingAverages.new(series: prices, period: period)
          return Array.new(prices.length, nil) unless moving_averages.valid?

          ema_value = moving_averages.ema
          # Return array with nils at beginning, single EMA value at end
          # Note: ruby-technical-analysis returns single value, not array
          Array.new(prices.length - 1, nil) + [ema_value]
        end

        # Get the latest EMA value
        # @param prices [Array<Numeric>] Array of closing prices
        # @param period [Integer] EMA period
        # @return [Numeric, nil] Latest EMA value or nil if insufficient data
        def self.latest(prices, period)
          return nil if prices.empty? || period < 1 || prices.length < period

          moving_averages = RubyTechnicalAnalysis::MovingAverages.new(series: prices, period: period)
          return nil unless moving_averages.valid?

          moving_averages.ema
        end
      end
    end
  end
end
