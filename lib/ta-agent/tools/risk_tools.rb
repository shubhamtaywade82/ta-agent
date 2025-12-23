# frozen_string_literal: true

require_relative "market_data_tools"
require_relative "../market/session"
require_relative "../market/vix"

# TaAgent::Tools::RiskTools
#
# Category 6: Market Condition & Risk Tools (GLOBAL KILL SWITCHES)
#
# Responsibilities:
# - Check expiry risk
# - Check time windows
# - Check volatility regime
# - Global kill switches
#
# Design:
# - If any returns no_trade = true → ABORT
# - Applied BEFORE LLM call
module TaAgent
  module Tools
    module RiskTools
      # Check expiry risk
      # @return [Hash] Expiry risk assessment
      def self.check_expiry_risk
        today = Date.today
        # TODO: Calculate actual expiry date
        # For now, placeholder
        {
          expiry_day: false,
          days_to_expiry: 0,
          risk: "low"
        }
      end

      # Check time window
      # @return [Hash] Time window assessment
      def self.check_time_window
        session = Market::Session.current
        hour = Time.now.hour
        minute = Time.now.min

        # No trade in last 30 minutes if no clear trend
        no_trade = if hour >= 15 && minute >= 30
                     true
                   else
                     false
                   end

        {
          no_trade: no_trade,
          reason: no_trade ? "Last 30 minutes - avoid" : nil,
          session_phase: session[:type]
        }
      end

      # Check volatility regime
      # @param client [TaAgent::DhanHQ::Client] DhanHQ client
      # @return [Hash] Volatility regime assessment
      def self.check_volatility_regime(client)
        vix_data = MarketDataTools.fetch_india_vix(client)
        vix_value = vix_data[:value]

        return { no_trade: false, reason: nil } unless vix_value

        # Low VIX + sideways = no trade
        no_trade = vix_value < 12

        {
          no_trade: no_trade,
          reason: no_trade ? "Low VIX regime" : nil,
          vix: vix_value,
          regime: if vix_value < 12
                    "low"
                  else
                    (vix_value > 20 ? "high" : "normal")
                  end
        }
      end

      # Check profit lock (if target achieved today)
      # @return [Hash] Profit lock assessment
      def self.check_profit_lock
        # TODO: Implement profit tracking
        {
          no_trade: false,
          reason: nil
        }
      end

      # Run all risk checks
      # @param client [TaAgent::DhanHQ::Client] DhanHQ client
      # @return [Hash] Combined risk assessment
      def self.run_all_checks(client)
        expiry_risk = check_expiry_risk
        time_window = check_time_window
        volatility = check_volatility_regime(client)
        profit_lock = check_profit_lock

        no_trade = expiry_risk[:risk] == "high" ||
                   time_window[:no_trade] ||
                   volatility[:no_trade] ||
                   profit_lock[:no_trade]

        reasons = []
        reasons << expiry_risk[:reason] if expiry_risk[:risk] == "high"
        reasons << time_window[:reason] if time_window[:no_trade]
        reasons << volatility[:reason] if volatility[:no_trade]
        reasons << profit_lock[:reason] if profit_lock[:no_trade]

        {
          no_trade: no_trade,
          reasons: reasons.compact,
          checks: {
            expiry: expiry_risk,
            time_window: time_window,
            volatility: volatility,
            profit_lock: profit_lock
          }
        }
      end
    end
  end
end

