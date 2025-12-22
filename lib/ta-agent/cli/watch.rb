# frozen_string_literal: true

# TaAgent::CLI::Watch
#
# Continuous monitoring command.
#
# Usage: ta-agent watch NIFTY --interval 60
#
# Flow:
# - Runs analysis every X seconds
# - Prints only state changes (no spam)
# - Uses TTY::Spinner for visual feedback
#
# Design:
# - Loop with interval
# - Compare previous state with current
# - Only output on changes
# - Graceful shutdown on SIGINT
module TaAgent
  module CLI
    class Watch
      def self.call(argv, global_opts)
        new(argv, global_opts).call
      end

      def initialize(argv, global_opts)
        @argv = argv
        @global_opts = global_opts
        @interval = 60 # default
      end

      def call
        parse_options

        symbol = @argv.shift

        unless symbol
          puts "Error: SYMBOL is required"
          puts "Usage: ta-agent watch SYMBOL [--interval SECONDS]"
          exit 1
        end

        # TODO: Implement watch mode
        # - Loop with @interval
        # - Run analysis each iteration
        # - Compare state, only print changes
        # - Handle SIGINT gracefully
        puts "Watch command - Implementation pending"
        puts "Symbol: #{symbol}"
        puts "Interval: #{@interval} seconds"
        puts "This will continuously monitor #{symbol} every #{@interval}s"
        exit 0
      end

      private

      def parse_options
        to_remove = []
        i = 0

        while i < @argv.length
          arg = @argv[i]
          if arg == "--interval"
            if @argv[i + 1]
              @interval = @argv[i + 1].to_i
              to_remove << i
              to_remove << i + 1
              i += 2
            else
              to_remove << i
              i += 1
            end
          elsif arg.start_with?("--interval=")
            @interval = arg.split("=", 2).last.to_i
            to_remove << i
            i += 1
          else
            i += 1
          end
        end

        to_remove.reverse_each { |idx| @argv.delete_at(idx) }

        if @interval < 1
          puts "Error: interval must be at least 1 second"
          exit 1
        end
      end
    end
  end
end

