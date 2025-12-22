# frozen_string_literal: true

# TaAgent::CLI::Analyse
#
# One-time analysis command.
#
# Usage: ta-agent analyse NIFTY
#
# Flow:
# 1. Validate config
# 2. Build agent context
# 3. Run deterministic pipelines
# 4. Apply gates
# 5. Call LLM (optional)
# 6. Render output
#
# Design:
# - Takes symbol as argument
# - Creates TaAgent::Agent::Runner instance
# - Formats and prints results
module TaAgent
  module CLI
    class Analyse
      def self.call(argv, global_opts)
        new(argv, global_opts).call
      end

      def initialize(argv, global_opts)
        @argv = argv
        @global_opts = global_opts
      end

      def call
        symbol = @argv.shift

        unless symbol
          puts "Error: SYMBOL is required"
          puts "Usage: ta-agent analyse SYMBOL"
          exit 1
        end

        # TODO: Implement analysis
        # - Validate config via TaAgent::Config
        # - Initialize TaAgent::Agent::Runner with symbol
        # - Run analysis
        # - Format output
        puts "Analyse command - Implementation pending"
        puts "Symbol: #{symbol}"
        puts "This will run technical analysis for #{symbol}"
        exit 0
      end
    end
  end
end

