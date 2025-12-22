# frozen_string_literal: true

# TaAgent::CLI::Root
#
# Main CLI command router using TTY::CommandRouter.
#
# Commands:
# - analyse SYMBOL    → Run one-time analysis
# - watch SYMBOL      → Continuous monitoring mode
# - config            → Interactive configuration
#
# Design:
# - Use TTY::CommandRouter for command parsing
# - Delegate to specific command classes
# - Handle global flags (--help, --version, --debug)
#
# @example
#   TaAgent::CLI::Root.call(ARGV)
module TaAgent
  module CLI
    class Root
      # TODO: Implement TTY::CommandRouter setup
      # - Define command routes
      # - Handle global options
      # - Dispatch to command classes
    end
  end
end

