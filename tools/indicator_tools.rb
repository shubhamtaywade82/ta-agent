# frozen_string_literal: true

require_relative "../lib/ta-agent/ta/indicators/ema"
require_relative "../lib/ta-agent/ta/indicators/adx"
require_relative "../lib/ta-agent/ta/indicators/atr"
require_relative "../lib/ta-agent/ta/indicators/vwap"

# TaAgent::Tools::IndicatorTools
#
# Category 2: Indicator Tools (Pure Math)
#
# Responsibilities:
# - Convert raw data → numbers
# - Pure mathematical calculations
# - NO interpretation, NO labels
#
# Design:
# - Deterministic functions
# - Input: Raw arrays
# - Output: Indicator values
# - Still NOT sent to LLM directly
module TaAgent
  module Tools
    module IndicatorTools
      # Calculate EMA
      # @param closes [Array<Float>] Closing prices
      # @param period [Integer] EMA period
      # @return [Hash] EMA values
      def self.calculate_ema(closes, period)
        ema_values = TA::Indicators::EMA.calculate(closes, period)
        latest = TA::Indicators::EMA.latest(closes, period)

        {
          values: ema_values,
          latest: latest,
          period: period
        }
      end

      # Calculate ADX
      # @param highs [Array<Float>] High prices
      # @param lows [Array<Float>] Low prices
      # @param closes [Array<Float>] Close prices
      # @param period [Integer] ADX period (default: 14)
      # @return [Hash] ADX and DI values
      def self.calculate_adx(highs, lows, closes, period: 14)
        prices = highs.zip(lows, closes).map { |h, l, c| { high: h, low: l, close: c } }
        adx = TA::Indicators::ADX.latest(prices, period: period)

        {
          adx: adx,
          period: period
          # TODO: Add DI+ and DI- when ADX implementation supports it
        }
      end

      # Calculate ATR
      # @param highs [Array<Float>] High prices
      # @param lows [Array<Float>] Low prices
      # @param closes [Array<Float>] Close prices
      # @param period [Integer] ATR period (default: 14)
      # @return [Hash] ATR values
      def self.calculate_atr(highs, lows, closes, period: 14)
        prices = highs.zip(lows, closes).map { |h, l, c| { high: h, low: l, close: c } }
        atr = TA::Indicators::ATR.latest(prices, period: period)

        {
          atr: atr,
          period: period
        }
      end

      # Calculate VWAP
      # @param ohlcv [Hash] OHLCV data with :open, :high, :low, :close, :volume keys
      # @return [Hash] VWAP value
      def self.calculate_vwap(ohlcv)
        ohlcv_array = ohlcv[:open].zip(
          ohlcv[:high],
          ohlcv[:low],
          ohlcv[:close],
          ohlcv[:volume]
        ).map { |o, h, l, c, v| { open: o, high: h, low: l, close: c, volume: v } }

        vwap = TA::Indicators::VWAP.latest(ohlcv_array)

        {
          vwap: vwap
        }
      end
    end
  end
end

