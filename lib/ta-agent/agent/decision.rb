# frozen_string_literal: true

require "date"
require_relative "../dhanhq/client"

# TaAgent::Agent::Decision
#
# Decision making logic (deterministic + optional LLM).
#
# Responsibilities:
# - Make deterministic decisions from context
# - Optionally enhance with LLM analysis
# - Generate recommendation hash
# - Fetch option chain data when needed
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
      # @param dhanhq_client [TaAgent::DhanHQ::Client, nil] Optional DhanHQ client for fetching option chain
      def initialize(config, dhanhq_client: nil)
        @config = config
        @dhanhq_client = dhanhq_client
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
        symbol = context[:symbol]
        options = context[:options] || {}

        # If we don't have option chain data, try to fetch it
        if @dhanhq_client && (!options || options.empty? || options[:strikes]&.empty?)
          spot_price = tf_1m[:latest_close] || tf_15m[:latest_close]
          trend_direction = tf_15m[:trend] if tf_15m[:status] == "complete"
          options = fetch_option_chain_data(symbol, spot_price, trend_direction)
        end

        # Determine trend
        trend = if tf_15m[:status] == "complete"
                  tf_15m[:trend]&.upcase || "NEUTRAL"
                else
                  "UNKNOWN"
                end

        # Extract best strike from options data
        best_strike = options[:best_strike] ||
                      options[:candidates]&.first ||
                      (options[:strikes]&.is_a?(Array) && options[:strikes].first) ||
                      nil

        # Check if we have any options data (even if empty, we might want to show options format)
        has_options = best_strike ||
                      options[:candidates]&.any? ||
                      (options[:strikes]&.is_a?(Array) && options[:strikes].any?)

        # Get expiry info from options
        days_to_expiry_from_options = options[:days_to_expiry]
        expiry_date_from_options = options[:selected_expiry]

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
            strike_price = best_strike&.dig(:strike) || best_strike&.dig(:strike_price) || (best_strike.is_a?(Hash) && best_strike[:strike])

            # Try to get premium from option chain data - for CE (Call) options
            # Check if we have call option data (from the new structure)
            call_option = best_strike&.dig(:call) ||
                          best_strike&.dig("call") ||
                          options[:calls]&.find do |c|
                            (c[:strike] || c["strike"] || c[:strike_price] || c["strike_price"]) == strike_price
                          end ||
                          options["calls"]&.find do |c|
                            (c[:strike] || c["strike"] || c[:strike_price] || c["strike_price"]) == strike_price
                          end

            premium = if call_option
                        # Extract premium from call option - check all possible field names
                        call_option[:ltp] ||
                          call_option["ltp"] ||
                          call_option[:last_price] ||
                          call_option["last_price"] ||
                          call_option[:pricing]&.dig(:ltp) ||
                          call_option[:pricing]&.dig("ltp") ||
                          call_option[:ask] ||
                          call_option["ask"] ||
                          call_option[:pricing]&.dig(:ask) ||
                          call_option[:pricing]&.dig("ask") ||
                          call_option[:bid] ||
                          call_option["bid"] ||
                          call_option[:pricing]&.dig(:bid) ||
                          call_option[:pricing]&.dig("bid") ||
                          call_option[:premium] ||
                          call_option["premium"]
                      else
                        # Fallback to best_strike structure - check both symbol and string keys
                        best_strike&.dig(:pricing, :ltp) ||
                          best_strike&.dig("pricing", "ltp") ||
                          best_strike&.dig(:ltp) ||
                          best_strike&.dig("ltp") ||
                          best_strike&.dig(:last_price) ||
                          best_strike&.dig("last_price") ||
                          best_strike&.dig(:pricing, :ask) ||
                          best_strike&.dig("pricing", "ask") ||
                          best_strike&.dig(:ask) ||
                          best_strike&.dig("ask") ||
                          best_strike&.dig(:bid) ||
                          best_strike&.dig("bid") ||
                          best_strike&.dig(:pricing, :bid) ||
                          best_strike&.dig("pricing", "bid") ||
                          (best_strike.is_a?(Hash) && (best_strike[:premium] || best_strike["premium"])) ||
                          (best_strike&.dig(:pricing) && (best_strike[:pricing][:ltp] || best_strike[:pricing]["ltp"] ||
                                                           best_strike[:pricing][:ask] || best_strike[:pricing]["ask"] ||
                                                           best_strike[:pricing][:bid] || best_strike[:pricing]["bid"]))
                      end

            # Extract theta from call option (for CE)
            theta = if call_option
                      call_option[:theta] ||
                        call_option[:greeks]&.dig(:theta) ||
                        call_option[:greeks]&.dig("theta")
                    else
                      best_strike&.dig(:greeks, :theta) ||
                        best_strike&.dig(:theta) ||
                        (best_strike&.dig(:greeks) && best_strike[:greeks][:theta])
                    end

            days_to_expiry = days_to_expiry_from_options ||
                             best_strike&.dig(:days_to_expiry) ||
                             best_strike&.dig(:expiry_days) ||
                             (best_strike.is_a?(Hash) && best_strike[:days_to_expiry])

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
            # If premium is not available, estimate based on spot price and symbol type
            premium_is_estimated = false
            if premium.nil? || premium == 0
              spot_price = tf_1m[:latest_close] || tf_15m[:latest_close] || 0

              # Better premium estimation based on symbol type and spot price
              # BANKNIFTY: typically 0.3-0.5% of spot for ATM options
              # NIFTY: typically 0.2-0.4% of spot for ATM options
              # SENSEX: typically 0.2-0.3% of spot for ATM options
              premium_percentage = if spot_price > 50_000
                                     0.0025  # SENSEX: 0.25% of spot
                                   elsif spot_price > 20_000
                                     0.004   # BANKNIFTY: 0.4% of spot (more volatile)
                                   else
                                     0.003   # NIFTY: 0.3% of spot
                                   end

              entry_premium = spot_price > 0 ? (spot_price * premium_percentage).round(2) : 0
              premium_is_estimated = true
            else
              entry_premium = premium
            end
            target_1 = entry_premium > 0 ? (entry_premium * 1.5).round(2) : 0 # 50% profit target
            target_2 = entry_premium > 0 ? (entry_premium * 2.0).round(2) : 0 # 100% profit target (if momentum is good)
            stop_loss_premium = entry_premium > 0 ? (entry_premium * 0.7).round(2) : 0 # 30% stop loss

            # Calculate expiry date from days_to_expiry or use fetched expiry
            expiry_date = nil
            if expiry_date_from_options
              # Use the expiry date from option chain
              expiry_date = expiry_date_from_options.is_a?(Date) ? expiry_date_from_options : Date.parse(expiry_date_from_options.to_s)
            elsif days_to_expiry && days_to_expiry > 0
              expiry_date = Date.today + days_to_expiry
            elsif !days_to_expiry || days_to_expiry == 0
              # Default to weekly expiry (typically Thursday for NIFTY/SENSEX/BANKNIFTY)
              # Find next Thursday (weekly expiry)
              today = Date.today
              # Thursday is wday = 4 (Monday = 1, Sunday = 0)
              if today.wday == 4
                # If today is Thursday, use next Thursday (7 days)
                days_until_thursday = 7
              else
                # Calculate days until next Thursday
                days_until_thursday = (4 - today.wday) % 7
                # If result is 0, it means we're past Thursday, so use next week's Thursday
                days_until_thursday = 7 if days_until_thursday == 0
              end
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
            strike_price = best_strike&.dig(:strike) || best_strike&.dig(:strike_price) || (best_strike.is_a?(Hash) && best_strike[:strike])

            # Try to get premium from option chain data - for PE (Put) options
            # Check if we have put option data (from the new structure)
            put_option = best_strike&.dig(:put) ||
                         best_strike&.dig("put") ||
                         options[:puts]&.find do |p|
                           (p[:strike] || p["strike"] || p[:strike_price] || p["strike_price"]) == strike_price
                         end ||
                         options["puts"]&.find do |p|
                           (p[:strike] || p["strike"] || p[:strike_price] || p["strike_price"]) == strike_price
                         end

            premium = if put_option
                        # Extract premium from put option - check all possible field names
                        put_option[:ltp] ||
                          put_option["ltp"] ||
                          put_option[:last_price] ||
                          put_option["last_price"] ||
                          put_option[:pricing]&.dig(:ltp) ||
                          put_option[:pricing]&.dig("ltp") ||
                          put_option[:ask] ||
                          put_option["ask"] ||
                          put_option[:pricing]&.dig(:ask) ||
                          put_option[:pricing]&.dig("ask") ||
                          put_option[:bid] ||
                          put_option["bid"] ||
                          put_option[:pricing]&.dig(:bid) ||
                          put_option[:pricing]&.dig("bid") ||
                          put_option[:premium] ||
                          put_option["premium"]
                      else
                        # Fallback to best_strike structure - check both symbol and string keys
                        best_strike&.dig(:pricing, :ltp) ||
                          best_strike&.dig("pricing", "ltp") ||
                          best_strike&.dig(:ltp) ||
                          best_strike&.dig("ltp") ||
                          best_strike&.dig(:last_price) ||
                          best_strike&.dig("last_price") ||
                          best_strike&.dig(:pricing, :ask) ||
                          best_strike&.dig("pricing", "ask") ||
                          best_strike&.dig(:ask) ||
                          best_strike&.dig("ask") ||
                          best_strike&.dig(:bid) ||
                          best_strike&.dig("bid") ||
                          best_strike&.dig(:pricing, :bid) ||
                          best_strike&.dig("pricing", "bid") ||
                          (best_strike.is_a?(Hash) && (best_strike[:premium] || best_strike["premium"])) ||
                          (best_strike&.dig(:pricing) && (best_strike[:pricing][:ltp] || best_strike[:pricing]["ltp"] ||
                                                           best_strike[:pricing][:ask] || best_strike[:pricing]["ask"] ||
                                                           best_strike[:pricing][:bid] || best_strike[:pricing]["bid"]))
                      end

            # Extract theta from put option (for PE)
            theta = if put_option
                      put_option[:theta] ||
                        put_option[:greeks]&.dig(:theta) ||
                        put_option[:greeks]&.dig("theta")
                    else
                      best_strike&.dig(:greeks, :theta) ||
                        best_strike&.dig(:theta) ||
                        (best_strike&.dig(:greeks) && best_strike[:greeks][:theta])
                    end

            days_to_expiry = days_to_expiry_from_options ||
                             best_strike&.dig(:days_to_expiry) ||
                             best_strike&.dig(:expiry_days) ||
                             (best_strike.is_a?(Hash) && best_strike[:days_to_expiry])

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
            # If premium is not available, estimate based on spot price and symbol type
            premium_is_estimated = false
            if premium.nil? || premium == 0
              spot_price = tf_1m[:latest_close] || tf_15m[:latest_close] || 0

              # Better premium estimation based on symbol type and spot price
              # BANKNIFTY: typically 0.3-0.5% of spot for ATM options
              # NIFTY: typically 0.2-0.4% of spot for ATM options
              # SENSEX: typically 0.2-0.3% of spot for ATM options
              premium_percentage = if spot_price > 50_000
                                     0.0025  # SENSEX: 0.25% of spot
                                   elsif spot_price > 20_000
                                     0.004   # BANKNIFTY: 0.4% of spot (more volatile)
                                   else
                                     0.003   # NIFTY: 0.3% of spot
                                   end

              entry_premium = spot_price > 0 ? (spot_price * premium_percentage).round(2) : 0
              premium_is_estimated = true
            else
              entry_premium = premium
            end
            target_1 = entry_premium > 0 ? (entry_premium * 1.5).round(2) : 0 # 50% profit target
            target_2 = entry_premium > 0 ? (entry_premium * 2.0).round(2) : 0 # 100% profit target (if momentum is good)
            stop_loss_premium = entry_premium > 0 ? (entry_premium * 0.7).round(2) : 0 # 30% stop loss

            # Calculate expiry date from days_to_expiry or use fetched expiry
            expiry_date = nil
            if expiry_date_from_options
              # Use the expiry date from option chain
              expiry_date = expiry_date_from_options.is_a?(Date) ? expiry_date_from_options : Date.parse(expiry_date_from_options.to_s)
            elsif days_to_expiry && days_to_expiry > 0
              expiry_date = Date.today + days_to_expiry
            elsif !days_to_expiry || days_to_expiry == 0
              # Default to weekly expiry (typically Thursday for NIFTY/SENSEX/BANKNIFTY)
              # Find next Thursday (weekly expiry)
              today = Date.today
              # Thursday is wday = 4 (Monday = 1, Sunday = 0)
              if today.wday == 4
                # If today is Thursday, use next Thursday (7 days)
                days_until_thursday = 7
              else
                # Calculate days until next Thursday
                days_until_thursday = (4 - today.wday) % 7
                # If result is 0, it means we're past Thursday, so use next week's Thursday
                days_until_thursday = 7 if days_until_thursday == 0
              end
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

      private

      # Fetch option chain data for the symbol and find ATM strike with premium
      # @param symbol [String] Symbol name
      # @param spot_price [Float, nil] Current spot price (for finding ATM strike)
      # @param trend [String, nil] Trend direction ("bullish" or "bearish") to select CE or PE
      # @return [Hash] Option chain data with best_strike, expiry, etc.
      def fetch_option_chain_data(symbol, spot_price = nil, trend = nil)
        return {} unless @dhanhq_client

        begin
          # Fetch option chain for nearest expiry
          chain_data = @dhanhq_client.fetch_option_chain(symbol: symbol, expiry: nil)

          strikes = chain_data[:strikes] || []
          calls = chain_data[:calls] || []
          puts = chain_data[:puts] || []
          expiry_date = chain_data[:selected_expiry]

          return {} if strikes.empty? && calls.empty? && puts.empty?

          # Find ATM (At The Money) strike - closest to spot price
          best_strike_data = nil
          if spot_price && spot_price > 0
            # Find strike closest to spot price
            if strikes.any?
              # If we have structured strikes with call/put
              best_strike_obj = strikes.min_by do |strike|
                strike_value = if strike.is_a?(Hash)
                                 strike[:strike] || strike[:strike_price] || 0
                               else
                                 strike.to_f
                               end
                (strike_value - spot_price).abs
              end

              # Extract the appropriate option (CE for bullish, PE for bearish)
              if best_strike_obj.is_a?(Hash)
                option_type = trend&.downcase == "bullish" ? :call : :put
                option_data = best_strike_obj[option_type] || best_strike_obj[:call] || best_strike_obj[:put]

                best_strike_data = if option_data
                                     option_data.merge(
                                       strike: best_strike_obj[:strike] || best_strike_obj[:strike_price],
                                       strike_price: best_strike_obj[:strike] || best_strike_obj[:strike_price]
                                     )
                                   else
                                     best_strike_obj
                                   end
              else
                best_strike_data = { strike: best_strike_obj, strike_price: best_strike_obj }
              end
            elsif calls.any? || puts.any?
              # If we have separate calls and puts arrays
              option_list = trend&.downcase == "bullish" ? calls : puts
              option_list = calls + puts if option_list.empty?

              best_option = option_list.min_by do |opt|
                strike_value = opt[:strike] || opt[:strike_price] || 0
                (strike_value - spot_price).abs
              end

              best_strike_data = best_option if best_option
            end
          end

          # If we still don't have strike data, use first available
          unless best_strike_data
            if strikes.any?
              best_strike_data = if strikes.first.is_a?(Hash)
                                   strikes.first
                                 else
                                   { strike: strikes.first,
                                     strike_price: strikes.first }
                                 end
            elsif calls.any?
              best_strike_data = calls.first
            elsif puts.any?
              best_strike_data = puts.first
            end
          end

          # Calculate days to expiry
          days_to_expiry = nil
          if expiry_date
            expiry = expiry_date.is_a?(Date) ? expiry_date : Date.parse(expiry_date.to_s)
            days_to_expiry = (expiry - Date.today).to_i
            days_to_expiry = nil if days_to_expiry < 0
          end

          {
            strikes: strikes,
            calls: calls,
            puts: puts,
            best_strike: best_strike_data,
            expiry_dates: chain_data[:expiry_dates] || [],
            selected_expiry: expiry_date,
            days_to_expiry: days_to_expiry
          }
        rescue StandardError => e
          # If option chain fetch fails, return empty hash (will fall back to estimation)
          {}
        end
      end
    end
  end
end
