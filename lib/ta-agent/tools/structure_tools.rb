# frozen_string_literal: true

# TaAgent::Tools::StructureTools
#
# Category 3: Structure & Behavior Tools (Interpretation, Still Deterministic)
#
# Responsibilities:
# - Turn numbers → labels
# - Interpret indicators into trading concepts
# - Still deterministic (no LLM)
#
# Design:
# - Rule-based interpretation
# - Input: Indicator values
# - Output: Labels and classifications
# - This is what LLM understands
module TaAgent
  module Tools
    module StructureTools
      # Detect trend from indicators
      # @param adx [Float, nil] ADX value
      # @param ema_9 [Float, nil] EMA 9 value
      # @param ema_21 [Float, nil] EMA 21 value
      # @return [Hash] Trend classification
      def self.detect_trend(adx:, ema_9:, ema_21:)
        direction = if ema_9 && ema_21
                      if ema_9 > ema_21
                        "bullish"
                      elsif ema_9 < ema_21
                        "bearish"
                      else
                        "sideways"
                      end
                    else
                      "unknown"
                    end

        strength = if adx
                     if adx >= 25
                       "strong"
                     elsif adx >= 20
                       "moderate"
                     else
                       "weak"
                     end
                   else
                     "unknown"
                   end

        {
          direction: direction,
          strength: strength,
          adx: adx,
          ema_stack: determine_ema_stack(ema_9, ema_21)
        }
      end

      # Detect market structure
      # @param highs [Array<Float>] High prices
      # @param lows [Array<Float>] Low prices
      # @return [Hash] Structure classification
      def self.detect_structure(highs, lows)
        return { market_structure: "unknown", last_bos: "none" } if highs.length < 5 || lows.length < 5

        # Simplified structure detection
        # TODO: Implement proper HH_HL, LL_LH, BOS detection
        recent_highs = highs.last(5)
        recent_lows = lows.last(5)

        higher_highs = recent_highs.each_cons(2).all? { |a, b| b > a }
        higher_lows = recent_lows.each_cons(2).all? { |a, b| b > a }
        lower_highs = recent_highs.each_cons(2).all? { |a, b| b < a }
        lower_lows = recent_lows.each_cons(2).all? { |a, b| b < a }

        structure = if higher_highs && higher_lows
                      "HH_HL"
                    elsif lower_highs && lower_lows
                      "LL_LH"
                    else
                      "range"
                    end

        {
          market_structure: structure,
          last_bos: determine_bos(structure),
          structure_age_candles: 0 # TODO: Calculate actual age
        }
      end

      # Detect volatility state
      # @param atr_series [Array<Float>] ATR values over time
      # @return [Hash] Volatility classification
      def self.detect_volatility_state(atr_series)
        return { atr_trend: "unknown", range_state: "unknown" } if atr_series.length < 2

        recent_atr = atr_series.last(5)
        older_atr = atr_series[-10..-6] || []

        return { atr_trend: "stable", range_state: "compression" } if older_atr.empty?

        avg_recent = recent_atr.sum / recent_atr.length
        avg_older = older_atr.sum / older_atr.length

        atr_trend = if avg_recent > avg_older * 1.1
                      "expanding"
                    elsif avg_recent < avg_older * 0.9
                      "contracting"
                    else
                      "stable"
                    end

        range_state = atr_trend == "expanding" ? "expansion" : "compression"

        {
          atr_trend: atr_trend,
          range_state: range_state
        }
      end

      # Detect VWAP relation
      # @param price [Float] Current price
      # @param vwap [Float, nil] VWAP value
      # @return [Hash] VWAP relation classification
      def self.detect_vwap_relation(price, vwap)
        return { state: "unknown", distance_pct: 0.0 } unless vwap

        distance_pct = ((price - vwap) / vwap * 100.0).round(2)

        state = if price > vwap * 1.01
                  "above"
                elsif price < vwap * 0.99
                  "below"
                else
                  "inside"
                end

        {
          state: state,
          distance_pct: distance_pct
        }
      end

      private

      def self.determine_ema_stack(ema_9, ema_21)
        return "unknown" unless ema_9 && ema_21

        if ema_9 > ema_21
          "bullish"
        elsif ema_9 < ema_21
          "bearish"
        else
          "mixed"
        end
      end

      def self.determine_bos(structure)
        case structure
        when "HH_HL"
          "up"
        when "LL_LH"
          "down"
        else
          "none"
        end
      end
    end
  end
end

