# frozen_string_literal: true

require "ruby-technical-analysis"

# TaAgent::TA::Indicators::ADX
#
# Average Directional Index (ADX) indicator.
#
# Wraps ruby-technical-analysis gem for ADX calculations.
#
# Responsibilities:
# - Calculate ADX from price data
# - Determine trend strength (weak/strong)
#
# Contract:
# - Input: Array of price hashes with :high, :low, :close
# - Output: ADX value (0-100) or nil if insufficient data
#
# @example
#   prices = [{high: 100, low: 95, close: 98}, ...]
#   adx = TA::Indicators::ADX.calculate(prices, period: 14)
#   strength = TA::Indicators::ADX.strength(adx) # => "weak" | "strong"
module TaAgent
  module TA
    module Indicators
      class ADX
        DEFAULT_PERIOD = 14

        # Contract: Calculate ADX from price data
        # @param prices [Array<Hash>] Price data with :high, :low, :close keys
        # @param period [Integer] ADX period (default: 14)
        # @return [Float, nil] ADX value or nil if insufficient data
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

          adx_values = RubyTechnicalAnalysis::Adx.calculate(data, period: period)
          return nil if adx_values.empty?

          # Return the latest ADX value
          adx_values.last.adx
        end

        # Contract: Get latest ADX value
        # @param prices [Array<Hash>] Price data
        # @param period [Integer] ADX period
        # @return [Float, nil] Latest ADX value
        def self.latest(prices, period: DEFAULT_PERIOD)
          calculate(prices, period: period)
        end

        # Contract: Determine trend strength from ADX
        # @param adx [Float, nil] ADX value
        # @return [String] "weak" (< 25), "strong" (>= 25), or "unknown" (nil)
        def self.strength(adx)
          return "unknown" if adx.nil?
          adx >= 25 ? "strong" : "weak"
        end
      end
    end
  end
end
