# frozen_string_literal: true

# TaAgent::Agent::Gates
#
# Gate logic (kill switches, filters) for agent execution.
#
# Responsibilities:
# - Apply gates before/after context building
# - Block execution if conditions not met
# - Provide gate status
#
# Contract:
# - Input: Context hash
# - Output: Gate status (pass/block)
#
# @example
#   gates = TaAgent::Agent::Gates.new
#   return if gates.blocked?(context)
module TaAgent
  module Agent
    class Gates
      # Contract: Check if context should be blocked
      # @param context [Hash] Agent context
      # @return [Boolean] True if execution should be blocked
      def blocked?(context)
        # Check if any critical gates are blocking
        abort_after_15m?(context) || abort_after_5m?(context) || abort_if_empty_options?(context)
      end

      # Contract: Get gate status with reasons
      # @param context [Hash] Agent context
      # @return [Hash] Status with :blocked?, :reasons keys
      def status(context)
        reasons = []
        reasons << "15m data unavailable" if abort_after_15m?(context)
        reasons << "5m data unavailable" if abort_after_5m?(context)
        reasons << "Options data unavailable" if abort_if_empty_options?(context)

        {
          blocked?: !reasons.empty?,
          reasons: reasons
        }
      end

      # Contract: Check 15m gate (after 15m context built)
      # @param context [Hash] Agent context
      # @return [Boolean] True if should abort
      def abort_after_15m?(context)
        tf_15m = context[:timeframes][:tf_15m] || {}
        # Abort if 15m data fetch failed or no data
        tf_15m[:status] == "error" || tf_15m[:status] == "no_data"
      end

      # Contract: Check 5m gate (after 5m context built)
      # @param context [Hash] Agent context
      # @return [Boolean] True if should abort
      def abort_after_5m?(context)
        tf_5m = context[:timeframes][:tf_5m] || {}
        # Abort if 5m data fetch failed or no data
        tf_5m[:status] == "error" || tf_5m[:status] == "no_data"
      end

      # Contract: Check option chain gate (after options context built)
      # @param context [Hash] Agent context
      # @return [Boolean] True if should abort
      def abort_if_empty_options?(context)
        options = context[:options] || {}
        # For now, don't abort on empty options (they're optional)
        # TODO: Add logic to abort if options are required but empty
        false
      end
    end
  end
end
