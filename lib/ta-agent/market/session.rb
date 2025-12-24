# frozen_string_literal: true

require "date"

# TaAgent::Market::Session
#
# Market session management (pre-market, regular, post-market).
#
# Responsibilities:
# - Determine current market session
# - Check if market is open
# - Get session timings
# - Calculate last trading date
#
# Contract:
# - Input: Current time (defaults to Time.now)
# - Output: Session information hash
#
# @example
#   session = TaAgent::Market::Session.current
#   session.open? # => true/false
module TaAgent
  module Market
    class Session
      # Contract: Get current session information
      # @param time [Time] Current time (defaults to Time.now)
      # @return [Hash] Session info with :type, :open?, :start_time, :end_time keys
      def self.current(time: Time.now)
        # TODO: Implement session detection
        raise NotImplementedError, "Session detection not yet implemented"
      end

      # Contract: Check if market is open
      # @param time [Time] Current time
      # @return [Boolean] True if market is open
      def self.open?(time: Time.now)
        current(time: time)[:open?]
      end

      # Contract: Get session type
      # @param time [Time] Current time
      # @return [String] "pre_market", "regular", "post_market", or "closed"
      def self.type(time: Time.now)
        current(time: time)[:type]
      end

      # Get last trading date for Indian markets
      # Returns: Date that is <= today - 1 OR the actual last trading date
      # For Indian markets: Monday-Friday are trading days (excluding holidays)
      # @param date [Date] Reference date (defaults to Date.today)
      # @return [Date] Last trading date (minimum: date - 1)
      def self.last_trading_date(date: Date.today)
        yesterday = date - 1

        # If yesterday is a weekday (Monday=1, Friday=5), use it
        # Otherwise, go back to the last weekday
        if yesterday.wday.between?(1, 5) # Monday to Friday
          yesterday
        else
          # If yesterday is Saturday (6) or Sunday (0), go back to Friday
          days_back = yesterday.wday == 0 ? 2 : 1 # Sunday: go back 2 days, Saturday: go back 1 day
          date - days_back
        end
      end
    end
  end
end
