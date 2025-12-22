# frozen_string_literal: true

# TaAgent::Agent::ContextContracts
#
# Structured data contracts for LLM input.
#
# Design:
# - Pre-computed, decision-ready facts
# - NO raw OHLC arrays
# - NO indicator arrays
# - Compressed, structured JSON
#
# Rule: LLM must NEVER compute indicators or scan candles.
# All math → your system. LLM → reasoning + synthesis.
module TaAgent
  module Agent
    module ContextContracts
      # 15m Market Context Contract
      # Answers: "Should I even look for a trade?"
      module TF15MContext
        def self.build(tf_data, indicators: {})
          {
            trend: {
              direction: determine_direction(tf_data),
              strength: determine_strength(tf_data, indicators),
              adx: indicators[:adx],
              di_diff: indicators[:di_diff]
            },
            structure: {
              market_structure: determine_structure(tf_data),
              last_bos: indicators[:last_bos] || "none",
              structure_age_candles: indicators[:structure_age] || 0
            },
            volatility: {
              atr_trend: indicators[:atr_trend] || "stable",
              range_state: indicators[:range_state] || "compression"
            },
            key_levels: {
              vwap_position: indicators[:vwap_position] || "inside",
              ema_stack: determine_ema_stack(tf_data),
              distance_from_vwap_pct: indicators[:vwap_distance_pct] || 0.0
            },
            permission: {
              options_buying_allowed: determine_permission(tf_data, indicators),
              allowed_direction: determine_allowed_direction(tf_data)
            }
          }
        end

        private

        def self.determine_direction(tf_data)
          case tf_data[:trend]
          when "bullish"
            "bullish"
          when "bearish"
            "bearish"
          else
            "sideways"
          end
        end

        def self.determine_strength(tf_data, indicators)
          adx = indicators[:adx] || 0.0
          if adx >= 25
            "strong"
          elsif adx >= 20
            "moderate"
          else
            "weak"
          end
        end

        def self.determine_structure(tf_data)
          # TODO: Implement proper structure detection
          "HH_HL" # Placeholder
        end

        def self.determine_ema_stack(tf_data)
          ema_9 = tf_data[:ema_9]
          ema_21 = tf_data[:ema_21]
          return "mixed" unless ema_9 && ema_21

          if ema_9 > ema_21
            "bullish"
          elsif ema_9 < ema_21
            "bearish"
          else
            "mixed"
          end
        end

        def self.determine_permission(tf_data, indicators)
          return false unless tf_data[:status] == "complete"
          return false if tf_data[:trend] == "neutral"
          return false if indicators[:adx] && indicators[:adx] < 20

          true
        end

        def self.determine_allowed_direction(tf_data)
          case tf_data[:trend]
          when "bullish"
            "CE"
          when "bearish"
            "PE"
          else
            "none"
          end
        end
      end

      # 5m Setup Validation Contract
      # Answers: "Is a tradable setup forming?"
      module TF5MContext
        def self.build(tf_data, indicators: {})
          {
            setup: {
              type: determine_setup_type(tf_data, indicators),
              quality: determine_quality(tf_data, indicators)
            },
            momentum: {
              rsi: indicators[:rsi],
              rsi_trend: indicators[:rsi_trend] || "flat",
              macd_state: indicators[:macd_state] || "neutral"
            },
            price_behavior: {
              last_close_strength: determine_close_strength(tf_data),
              upper_wick_pct: indicators[:upper_wick_pct] || 0.0,
              body_pct: indicators[:body_pct] || 0.0
            },
            vwap_relation: {
              state: indicators[:vwap_state] || "inside",
              retests: indicators[:vwap_retests] || 0
            },
            invalidations: determine_invalidations(tf_data, indicators),
            proceed_to_entry: determine_proceed(tf_data, indicators)
          }
        end

        private

        def self.determine_setup_type(tf_data, indicators)
          return "none" unless tf_data[:status] == "complete"

          case indicators[:setup_type]
          when "pullback"
            "pullback"
          when "breakout"
            "breakout"
          else
            "trend_continuation"
          end
        end

        def self.determine_quality(tf_data, indicators)
          return "low" unless tf_data[:status] == "complete"

          quality_score = 0
          quality_score += 1 if indicators[:rsi] && indicators[:rsi] > 50
          quality_score += 1 if indicators[:momentum_alignment]
          quality_score += 1 if (indicators[:invalidations] || []).empty?

          case quality_score
          when 3
            "high"
          when 2
            "medium"
          else
            "low"
          end
        end

        def self.determine_close_strength(tf_data)
          # TODO: Implement from actual candle data
          "strong"
        end

        def self.determine_invalidations(tf_data, indicators)
          invalidations = []
          invalidations << "weak_close_near_high" if indicators[:weak_close]
          invalidations << "failed_retest" if indicators[:failed_retest]
          invalidations
        end

        def self.determine_proceed(tf_data, indicators)
          return false unless tf_data[:status] == "complete"
          return false if determine_setup_type(tf_data, indicators) == "none"
          return false unless (determine_invalidations(tf_data, indicators)).empty?

          true
        end
      end

      # 1m Entry Timing Contract
      # Answers: "NOW or WAIT?"
      module TF1MContext
        def self.build(tf_data, indicators: {})
          {
            trigger: {
              status: determine_trigger_status(tf_data, indicators),
              type: determine_trigger_type(indicators)
            },
            momentum_ignition: {
              range_expansion_pct: indicators[:range_expansion_pct] || 0.0,
              atr_spike: indicators[:atr_spike] || false,
              consecutive_strong_closes: indicators[:consecutive_strong_closes] || 0
            },
            micro_structure: {
              higher_low: indicators[:higher_low] || false,
              lower_wick_dominance: indicators[:lower_wick_dominance] || false
            },
            entry_zone: determine_entry_zone(tf_data),
            risk: {
              invalid_price: determine_invalid_price(tf_data),
              rr_estimate: indicators[:rr_estimate] || 0.0
            }
          }
        end

        private

        def self.determine_trigger_status(tf_data, indicators)
          return "none" unless tf_data[:status] == "complete"

          if tf_data[:entry_signal] == "confirmed"
            "confirmed"
          elsif indicators[:forming]
            "forming"
          else
            "none"
          end
        end

        def self.determine_trigger_type(indicators)
          return "none" unless indicators[:trigger_type]

          case indicators[:trigger_type]
          when "range_break"
            "range_break"
          when "vwap_reclaim"
            "vwap_reclaim"
          when "momentum_burst"
            "momentum_burst"
          else
            "none"
          end
        end

        def self.determine_entry_zone(tf_data)
          return nil unless tf_data[:entry_zone]

          {
            price_from: tf_data[:entry_zone][:from],
            price_to: tf_data[:entry_zone][:to]
          }
        end

        def self.determine_invalid_price(tf_data)
          return nil unless tf_data[:latest_close]

          (tf_data[:latest_close] * 0.92).round(2)
        end
      end

      # Option Strikes Contract
      # Pre-filtered, pre-scored strikes only
      module OptionStrikesContext
        def self.build(strikes)
          strikes.map do |strike|
            {
              symbol: strike[:symbol] || "NIFTY",
              strike: strike[:strike],
              moneyness: strike[:moneyness] || "ATM",
              pricing: {
                ltp: strike[:ltp],
                bid: strike[:bid],
                ask: strike[:ask],
                spread_pct: calculate_spread_pct(strike)
              },
              greeks: {
                delta: strike[:delta],
                gamma: strike[:gamma],
                theta: strike[:theta],
                vega: strike[:vega]
              },
              iv: {
                current: strike[:iv],
                iv_trend: strike[:iv_trend] || "stable"
              },
              oi: {
                oi_change: strike[:oi_change] || "stable",
                oi_confirmation: strike[:oi_confirmation] || false
              },
              risk_flags: {
                theta_risk: determine_theta_risk(strike),
                liquidity: determine_liquidity(strike)
              },
              score: strike[:score] || 0.0
            }
          end
        end

        private

        def self.calculate_spread_pct(strike)
          return 100.0 unless strike[:bid] && strike[:ask]

          spread = (strike[:ask] - strike[:bid]).abs
          mid = (strike[:bid] + strike[:ask]) / 2.0
          return 100.0 if mid.zero?

          (spread / mid) * 100.0
        end

        def self.determine_theta_risk(strike)
          theta = strike[:theta]&.abs || 0.0
          theta > 10.0 ? "high" : "acceptable"
        end

        def self.determine_liquidity(strike)
          spread_pct = calculate_spread_pct(strike)
          spread_pct < 1.0 ? "good" : "poor"
        end
      end

      # Market Conditions Contract
      # Global filters and kill switches
      module MarketConditionsContext
        def self.build(session_data: {}, vix_data: {}, event_data: {})
          {
            session: {
              time: Time.now.strftime("%H:%M"),
              phase: determine_session_phase
            },
            index_state: {
              gap: session_data[:gap] || "none",
              gap_filled: session_data[:gap_filled] || false
            },
            volatility: {
              india_vix: vix_data[:value],
              vix_trend: vix_data[:trend] || "flat"
            },
            event_risk: {
              expiry_day: event_data[:expiry_day] || false,
              major_event: event_data[:major_event] || false
            },
            no_trade_zones: {
              reason: determine_no_trade_reason(session_data, vix_data, event_data)
            }
          }
        end

        private

        def self.determine_session_phase
          hour = Time.now.hour
          if hour >= 9 && hour < 11
            "open"
          elsif hour >= 11 && hour < 14
            "mid"
          else
            "close"
          end
        end

        def self.determine_no_trade_reason(session_data, vix_data, event_data)
          return "Low VIX + sideways market" if vix_data[:value] && vix_data[:value] < 12 && session_data[:sideways]
          return "Expiry day volatility" if event_data[:expiry_day]
          return "Major event risk" if event_data[:major_event]

          nil
        end
      end
    end
  end
end
