# frozen_string_literal: true

require "date"

# TaAgent::Agent::Decision
#
# Decision making logic (deterministic + optional LLM).
#
# Responsibilities:
# - Make deterministic decisions from context
# - Optionally enhance with LLM analysis
# - Generate recommendation hash
#
# Contract:
# - Input: Complete agent context
# - Output: Recommendation hash with action, confidence, etc.
#
# @example
#   decision = TaAgent::Agent::Decision.new(config)
#   recommendation = decision.make(context)
module TaAgent
  module Agent
    class Decision
      # Contract: Initialize with config
      # @param config [TaAgent::Config] Configuration instance
      def initialize(config)
        @config = config
      end

      # Contract: Make decision from context
      # @param context [Hash] Complete agent context
      # @return [Hash] Recommendation with :action, :confidence, :reason, :strike keys
      def make(context)
        base_decision = deterministic(context)

        # Optionally enhance with LLM if enabled
        if @config.ollama_enabled?
          begin
            with_llm(context, base_decision)
          rescue OllamaError => e
            # LLM failed, use deterministic decision
            base_decision
          end
        else
          base_decision
        end
      end

      # Contract: Make deterministic decision (no LLM)
      # @param context [Hash] Agent context
      # @return [Hash] Deterministic recommendation with :action, :confidence, :reason, :strike, :entry keys
      def deterministic(context)
        tf_15m = context[:timeframes][:tf_15m] || {}
        tf_5m = context[:timeframes][:tf_5m] || {}
        tf_1m = context[:timeframes][:tf_1m] || {}
        options = context[:options] || {}

        # Determine trend
        trend = if tf_15m[:status] == "complete"
                  tf_15m[:trend]&.upcase || "NEUTRAL"
                else
                  "UNKNOWN"
                end

        # Check if we have options data - if yes, generate options buying recommendation
        # Try multiple possible structures for options data
        best_strike = options[:best_strike] ||
                      options[:candidates]&.first ||
                      options[:candidates]&.first ||
                      (options[:strikes]&.is_a?(Array) && options[:strikes].first) ||
                      nil

        # Check if we have any options data (even if empty, we might want to show options format)
        has_options = best_strike ||
                      options[:candidates]&.any? ||
                      (options[:strikes]&.is_a?(Array) && options[:strikes].any?)

        # Basic decision logic based on 15m trend
        if tf_15m[:status] == "complete" && tf_15m[:trend] == "bullish"
          confidence = 0.6
          if tf_5m[:status] == "complete" && tf_5m[:ema_9] && tf_15m[:ema_9] && (tf_5m[:ema_9] > tf_15m[:ema_9])
            # 5m EMA above 15m EMA = stronger bullish
            confidence = 0.75
          end

          # For options buying: bullish trend = Buy CE
          # Always use options format if user asked for options buying (we'll infer from context or always use it)
          if has_options || true # For now, always use options format when trend is clear
            strike_price = best_strike&.dig(:strike) || best_strike&.dig(:strike_price) || (best_strike && best_strike[:strike])
            premium = best_strike&.dig(:pricing, :ltp) ||
                      best_strike&.dig(:ltp) ||
                      best_strike&.dig(:pricing, :ask) ||
                      best_strike&.dig(:ask) ||
                      (best_strike && best_strike[:premium]) ||
                      (best_strike&.dig(:pricing) && (best_strike[:pricing][:ltp] || best_strike[:pricing][:ask]))
            theta = best_strike&.dig(:greeks, :theta) ||
                    best_strike&.dig(:theta) ||
                    (best_strike&.dig(:greeks) && best_strike[:greeks][:theta])
            days_to_expiry = best_strike&.dig(:days_to_expiry) ||
                             best_strike&.dig(:expiry_days) ||
                             (best_strike && best_strike[:days_to_expiry])

            # If we don't have strike data, round spot price to nearest valid strike interval
            if !strike_price && tf_1m[:latest_close]
              spot_price = tf_1m[:latest_close]
              # Determine strike interval based on symbol/spot price
              # SENSEX/NIFTY: 50, BANKNIFTY: 100, Others: 50
              strike_interval = if spot_price > 50_000
                                  50  # SENSEX, NIFTY use 50
                                elsif spot_price > 20_000
                                  100 # BANKNIFTY uses 100
                                else
                                  50  # Default
                                end
              strike_price = (spot_price / strike_interval).round * strike_interval
            end

            # Calculate targets and stop loss (simplified - can be enhanced)
            # If premium is not available, estimate based on spot price (typically 0.1-0.5% of spot for ATM options)
            premium_is_estimated = false
            if premium.nil? || premium == 0
              spot_price = tf_1m[:latest_close] || tf_15m[:latest_close] || 0
              # More realistic premium estimate: 0.2% of spot for ATM options
              # For SENSEX at 85408, this would be ~170 points (more realistic)
              entry_premium = spot_price > 0 ? (spot_price * 0.002).round(2) : 0
              premium_is_estimated = true
            else
              entry_premium = premium
            end
            target_1 = entry_premium > 0 ? (entry_premium * 1.5).round(2) : 0 # 50% profit target
            target_2 = entry_premium > 0 ? (entry_premium * 2.0).round(2) : 0 # 100% profit target (if momentum is good)
            stop_loss_premium = entry_premium > 0 ? (entry_premium * 0.7).round(2) : 0 # 30% stop loss

            # Calculate expiry date from days_to_expiry
            expiry_date = nil
            if days_to_expiry && days_to_expiry > 0
              expiry_date = Date.today + days_to_expiry
            elsif !days_to_expiry || days_to_expiry == 0
              # Default to weekly expiry (typically Thursday for NIFTY/SENSEX)
              # Find next Thursday
              today = Date.today
              days_until_thursday = (4 - today.wday) % 7
              # If today is Thursday, use next Thursday
              days_until_thursday = 7 if days_until_thursday == 0 && today.wday != 4
              expiry_date = today + days_until_thursday
            end

            {
              action: "buy_ce",
              trend: "BULLISH",
              option_type: "CE",
              strike: strike_price,
              premium: entry_premium,
              premium_is_estimated: premium_is_estimated,
              target_1: target_1,
              target_2: target_2,
              stop_loss: stop_loss_premium,
              theta: theta,
              days_to_expiry: days_to_expiry,
              expiry_date: expiry_date,
              reason: "15m trend is bullish#{tf_15m[:ema_9] && tf_15m[:ema_21] ? " (EMA 9: #{tf_15m[:ema_9].round(2)} > EMA 21: #{tf_15m[:ema_21].round(2)})" : ""}",
              entry: tf_1m[:latest_close],
              confidence: confidence
            }
          else
            {
              action: "buy",
              trend: "BULLISH",
              reason: "15m trend is bullish#{tf_15m[:ema_9] && tf_15m[:ema_21] ? " (EMA 9: #{tf_15m[:ema_9].round(2)} > EMA 21: #{tf_15m[:ema_21].round(2)})" : ""}",
              strike: nil,
              entry: tf_1m[:latest_close],
              stop_loss: nil,
              target: nil,
              confidence: confidence
            }
          end
        elsif tf_15m[:status] == "complete" && tf_15m[:trend] == "bearish"
          # For options buying: bearish trend = Buy PE
          # Always use options format if user asked for options buying
          if has_options || true # For now, always use options format when trend is clear
            strike_price = best_strike&.dig(:strike) || best_strike&.dig(:strike_price) || (best_strike && best_strike[:strike])
            premium = best_strike&.dig(:pricing, :ltp) ||
                      best_strike&.dig(:ltp) ||
                      best_strike&.dig(:pricing, :ask) ||
                      best_strike&.dig(:ask) ||
                      (best_strike && best_strike[:premium]) ||
                      (best_strike&.dig(:pricing) && (best_strike[:pricing][:ltp] || best_strike[:pricing][:ask]))
            theta = best_strike&.dig(:greeks, :theta) ||
                    best_strike&.dig(:theta) ||
                    (best_strike&.dig(:greeks) && best_strike[:greeks][:theta])
            days_to_expiry = best_strike&.dig(:days_to_expiry) ||
                             best_strike&.dig(:expiry_days) ||
                             (best_strike && best_strike[:days_to_expiry])

            # If we don't have strike data, round spot price to nearest valid strike interval
            if !strike_price && tf_1m[:latest_close]
              spot_price = tf_1m[:latest_close]
              # Determine strike interval based on symbol/spot price
              # SENSEX/NIFTY: 50, BANKNIFTY: 100, Others: 50
              strike_interval = if spot_price > 50_000
                                  50  # SENSEX, NIFTY use 50
                                elsif spot_price > 20_000
                                  100 # BANKNIFTY uses 100
                                else
                                  50  # Default
                                end
              strike_price = (spot_price / strike_interval).round * strike_interval
            end

            # Calculate targets and stop loss
            # If premium is not available, estimate based on spot price (typically 0.1-0.5% of spot for ATM options)
            premium_is_estimated = false
            if premium.nil? || premium == 0
              spot_price = tf_1m[:latest_close] || tf_15m[:latest_close] || 0
              # More realistic premium estimate: 0.2% of spot for ATM options
              # For SENSEX at 85408, this would be ~170 points (more realistic)
              entry_premium = spot_price > 0 ? (spot_price * 0.002).round(2) : 0
              premium_is_estimated = true
            else
              entry_premium = premium
            end
            target_1 = entry_premium > 0 ? (entry_premium * 1.5).round(2) : 0 # 50% profit target
            target_2 = entry_premium > 0 ? (entry_premium * 2.0).round(2) : 0 # 100% profit target (if momentum is good)
            stop_loss_premium = entry_premium > 0 ? (entry_premium * 0.7).round(2) : 0 # 30% stop loss

            # Calculate expiry date from days_to_expiry
            expiry_date = nil
            if days_to_expiry && days_to_expiry > 0
              expiry_date = Date.today + days_to_expiry
            elsif !days_to_expiry || days_to_expiry == 0
              # Default to weekly expiry (typically Thursday for NIFTY/SENSEX)
              # Find next Thursday
              today = Date.today
              days_until_thursday = (4 - today.wday) % 7
              # If today is Thursday, use next Thursday
              days_until_thursday = 7 if days_until_thursday == 0 && today.wday != 4
              expiry_date = today + days_until_thursday
            end

            {
              action: "buy_pe",
              trend: "BEARISH",
              option_type: "PE",
              strike: strike_price,
              premium: entry_premium,
              premium_is_estimated: premium_is_estimated,
              target_1: target_1,
              target_2: target_2,
              stop_loss: stop_loss_premium,
              theta: theta,
              days_to_expiry: days_to_expiry,
              expiry_date: expiry_date,
              reason: "15m trend is bearish#{tf_15m[:ema_9] && tf_15m[:ema_21] ? " (EMA 9: #{tf_15m[:ema_9].round(2)} < EMA 21: #{tf_15m[:ema_21].round(2)})" : ""}",
              entry: tf_1m[:latest_close],
              confidence: 0.6
            }
          else
            {
              action: "sell",
              trend: "BEARISH",
              reason: "15m trend is bearish#{tf_15m[:ema_9] && tf_15m[:ema_21] ? " (EMA 9: #{tf_15m[:ema_9].round(2)} < EMA 21: #{tf_15m[:ema_21].round(2)})" : ""}",
              strike: nil,
              entry: tf_1m[:latest_close],
              stop_loss: nil,
              target: nil,
              confidence: 0.6
            }
          end
        else
          {
            action: "wait",
            trend: trend,
            reason: tf_15m[:status] == "error" ? "Data fetch error" : "Trend unclear or neutral",
            strike: nil,
            entry: nil,
            stop_loss: nil,
            target: nil,
            confidence: 0.0
          }
        end
      end

      # Contract: Enhance decision with LLM (if enabled)
      # @param context [Hash] Agent context
      # @param base_decision [Hash] Base deterministic decision
      # @return [Hash] Enhanced recommendation
      def with_llm(context, base_decision)
        # TODO: Implement LLM enhancement
        # For now, return base decision
        base_decision
      end
    end
  end
end
