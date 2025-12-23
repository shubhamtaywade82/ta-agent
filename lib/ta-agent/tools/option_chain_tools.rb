# frozen_string_literal: true

require_relative "market_data_tools"
require_relative "../options/strike_scorer"

# TaAgent::Tools::OptionChainTools
#
# Category 5: Option Chain Processing Tools (MOST IMPORTANT)
#
# Responsibilities:
# - Filter strikes (ATM, ATM+1 only)
# - Score strikes (deterministic)
# - Detect liquidity/theta risks
# - NOT LLM jobs
#
# Design:
# - Pre-filter before LLM sees them
# - Pre-score before LLM sees them
# - LLM sees only survivors
module TaAgent
  module Tools
    module OptionChainTools
      # Filter strikes (STRICT)
      # Only: ATM, ATM+1
      # Ignore: Deep ITM, Far OTM
      # @param chain [Hash] Raw option chain data
      # @param spot_price [Float] Current spot price
      # @return [Array<Hash>] Filtered strikes
      def self.filter_strikes(chain, spot_price:)
        strikes = chain[:strikes] || []
        return [] if strikes.empty? || !spot_price

        # Filter: Only ATM and ATM+1
        # TODO: Implement proper ATM detection
        # For now, filter by strike proximity to spot
        strikes.select do |strike|
          strike_value = extract_strike_value(strike)
          next false unless strike_value

          # Allow strikes within 1% of spot (ATM) or next strike
          distance_pct = ((strike_value - spot_price).abs / spot_price * 100.0)
          distance_pct <= 1.0
        end
      end

      # Score strikes (NON-LLM)
      # @param strikes [Array<Hash>] Filtered strikes
      # @param context [Hash] Market context (optional)
      # @return [Array<Hash>] Scored strikes with score field
      def self.score_strikes(strikes, context: {})
        scorer = Options::StrikeScorer.new

        strikes.map do |strike|
          score = scorer.score(strike, context: context)
          strike.merge(score: score)
        end
      end

      # Detect liquidity risk
      # @param strike [Hash] Strike data
      # @return [Hash] Liquidity assessment
      def self.detect_liquidity_risk(strike)
        spread_pct = calculate_spread_pct(strike)
        volume = strike[:volume] || 0

        liquidity = if spread_pct < 1.0 && volume > 100
                      "good"
                    elsif spread_pct < 2.0 && volume > 50
                      "acceptable"
                    else
                      "poor"
                    end

        {
          liquidity: liquidity,
          spread_pct: spread_pct,
          volume: volume,
          risk: liquidity == "poor"
        }
      end

      # Detect theta risk
      # @param strike [Hash] Strike data
      # @return [Hash] Theta risk assessment
      def self.detect_theta_risk(strike)
        theta = strike[:theta]&.abs || 0.0
        days_to_expiry = strike[:days_to_expiry] || 0

        risk = if theta > 10.0 || days_to_expiry < 1
                 "high"
               elsif theta > 5.0 || days_to_expiry < 3
                 "moderate"
               else
                 "acceptable"
               end

        {
          theta_risk: risk,
          theta: theta,
          days_to_expiry: days_to_expiry
        }
      end

      # Process option chain (complete pipeline)
      # @param client [TaAgent::DhanHQ::Client] DhanHQ client
      # @param symbol [String] Symbol name
      # @param spot_price [Float] Current spot price
      # @return [Array<Hash>] Pre-filtered, pre-scored strikes (top 1-2)
      def self.process_option_chain(client, symbol:, spot_price:)
        # Step 1: Fetch raw chain
        chain = MarketDataTools.fetch_option_chain(client, symbol: symbol)
        return [] if chain[:error] || chain[:strikes].empty?

        # Step 2: Filter strikes
        filtered = filter_strikes(chain, spot_price: spot_price)
        return [] if filtered.empty?

        # Step 3: Score strikes
        scored = score_strikes(filtered)

        # Step 4: Sort by score and return top 1-2
        scored.sort_by { |s| -s[:score] }.first(2)
      end

      private

      def self.extract_strike_value(strike)
        # Extract strike value from strike hash
        # Format might be "22500 CE" or {strike: 22500}
        if strike.is_a?(Hash)
          strike[:strike] || strike[:strike_price]
        elsif strike.is_a?(String)
          strike.match(/(\d+)/)&.captures&.first&.to_f
        end
      end

      def self.calculate_spread_pct(strike)
        return 100.0 unless strike[:bid] && strike[:ask]

        spread = (strike[:ask] - strike[:bid]).abs
        mid = (strike[:bid] + strike[:ask]) / 2.0
        return 100.0 if mid.zero?

        (spread / mid) * 100.0
      end
    end
  end
end

