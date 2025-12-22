# frozen_string_literal: true

require "ruby-technical-analysis"

# TaAgent::TA::Indicators::ATR
#
# Average True Range (ATR) indicator.
#
# Wraps ruby-technical-analysis gem for ATR calculations.
#
# Responsibilities:
# - Calculate ATR from price data
# - Determine volatility levels
#
# Contract:
# - Input: Array of price hashes with :high, :low, :close
# - Output: ATR value or nil if insufficient data
#
# @example
#   prices = [{high: 100, low: 95, close: 98}, ...]
#   atr = TA::Indicators::ATR.calculate(prices, period: 14)
module TaAgent
  module TA
    module Indicators
      class ATR
        DEFAULT_PERIOD = 14

        # Contract: Calculate ATR from price data
        # @param prices [Array<Hash>] Price data with :high, :low, :close keys
        # @param period [Integer] ATR period (default: 14)
        # @return [Float, nil] ATR value or nil if insufficient data
        def self.calculate(prices, period: DEFAULT_PERIOD)
          return nil if prices.empty? || prices.length < period

          # Convert to format expected by gem: array of hashes with date_time
          data = prices.map.with_index do |p, i|
            {
              date_time: Time.now - (prices.length - i) * 86400, # Placeholder dates
              high: p[:high],
              low: p[:low],
              close: p[:close]
            }
          end

          atr_values = RubyTechnicalAnalysis::Atr.calculate(data, period: period)
          return nil if atr_values.empty?

          # Return the latest ATR value
          atr_values.last.atr
        end

        # Contract: Get latest ATR value
        # @param prices [Array<Hash>] Price data
        # @param period [Integer] ATR period
        # @return [Float, nil] Latest ATR value
        def self.latest(prices, period: DEFAULT_PERIOD)
          calculate(prices, period: period)
        end
      end
    end
  end
end
