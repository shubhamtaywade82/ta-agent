# frozen_string_literal: true

# TaAgent::Market::Session
#
# Market session management (pre-market, regular, post-market).
#
# Responsibilities:
# - Determine current market session
# - Check if market is open
# - Get session timings
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
    end
  end
end
