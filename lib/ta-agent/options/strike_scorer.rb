# frozen_string_literal: true

# TaAgent::Options::StrikeScorer
#
# Option strike scoring logic (NON-LLM).
#
# Responsibilities:
# - Score strikes based on multiple factors
# - Pre-rank strikes before LLM sees them
# - Formula: delta_weight + gamma_weight + spread_penalty + iv_behavior + oi_confirmation
#
# Design:
# - Deterministic scoring (no LLM)
# - Only top 1-2 strikes go to LLM
# - Prevents LLM from hallucinating strikes
#
# @example
#   scorer = StrikeScorer.new
#   score = scorer.score(strike, context: market_context)
module TaAgent
  module Options
    class StrikeScorer
      # Score a strike based on multiple factors
      # @param strike [Hash] Strike data with :delta, :gamma, :theta, :iv, :spread, :oi keys
      # @param context [Hash] Market context (optional)
      # @return [Float] Score (0-10, higher is better)
      def score(strike, context: {})
        return 0.0 unless strike.is_a?(Hash)

        score = 0.0

        # Delta weight (0-3 points)
        # Optimal delta for options buying: 0.3-0.5
        delta = strike[:delta]&.abs || 0.0
        if delta >= 0.3 && delta <= 0.5
          score += 3.0
        elsif delta >= 0.2 && delta <= 0.6
          score += 2.0
        elsif delta >= 0.1 && delta <= 0.7
          score += 1.0
        end

        # Gamma weight (0-2 points)
        # Higher gamma = more momentum sensitivity
        gamma = strike[:gamma]&.abs || 0.0
        if gamma > 0.01
          score += 2.0
        elsif gamma > 0.005
          score += 1.0
        end

        # Spread penalty (0 to -2 points)
        # Wide spreads = bad liquidity
        spread_pct = calculate_spread_percentage(strike)
        if spread_pct > 2.0
          score -= 2.0
        elsif spread_pct > 1.0
          score -= 1.0
        elsif spread_pct < 0.5
          score += 0.5 # Bonus for tight spreads
        end

        # IV behavior bonus (0-1.5 points)
        # Expanding IV = good for buying
        iv_change = strike[:iv_change] || 0.0
        if iv_change > 0.05
          score += 1.5
        elsif iv_change > 0.02
          score += 1.0
        elsif iv_change < -0.05
          score -= 1.0 # Penalty for dropping IV
        end

        # OI confirmation (0-1.5 points)
        # Increasing OI = confirmation
        oi_change = strike[:oi_change] || 0.0
        if oi_change > 0.1
          score += 1.5
        elsif oi_change > 0.05
          score += 1.0
        end

        # Theta risk penalty (0 to -1 points)
        # High theta = time decay risk
        theta = strike[:theta]&.abs || 0.0
        if theta > 10.0
          score -= 1.0
        end

        # Normalize to 0-10 scale
        [score, 0.0].max
      end

      private

      def calculate_spread_percentage(strike)
        return 100.0 unless strike[:bid] && strike[:ask] && strike[:ltp]

        spread = (strike[:ask] - strike[:bid]).abs
        mid_price = (strike[:bid] + strike[:ask]) / 2.0
        return 100.0 if mid_price.zero?

        (spread / mid_price) * 100.0
      end
    end
  end
end


