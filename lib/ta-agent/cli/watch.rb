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

        # Load and validate config
        begin
          config = TaAgent::Config.load
        rescue TaAgent::ConfigurationError => e
          puts "Configuration Error:"
          puts e.message
          exit 1
        end

        symbol = symbol.upcase
        require_relative "../agent/runner"

        puts "Watching #{symbol} (interval: #{@interval}s)"
        puts "Press Ctrl+C to stop\n"

        # Set up signal handler for graceful shutdown
        @running = true
        Signal.trap("INT") do
          @running = false
          puts "\n\nStopping watch mode..."
        end

        previous_state = nil
        iteration = 0

        begin
          while @running
            iteration += 1

            # Show spinner if TTY::Spinner is available, otherwise simple message
            spinner = nil
            begin
              require "tty-spinner"
              spinner = TTY::Spinner.new("[:spinner] Monitoring #{symbol}...", format: :dots)
              spinner.auto_spin
            rescue LoadError
              print "Monitoring #{symbol}... "
              $stdout.flush
            end

            # Run analysis
            begin
              runner = TaAgent::Agent::Runner.new(symbol: symbol, config: config)
              result = runner.run

              # Stop spinner if used
              if spinner
                spinner.stop("Analysis complete")
              else
                puts "done"
              end

              # Check if state changed
              current_state = build_state_summary(result)
              state_changed = previous_state.nil? || state_different?(previous_state, current_state)

              if state_changed || iteration == 1
                puts "\n" + "=" * 60
                puts "[#{Time.now.strftime("%H:%M:%S")}] Update ##{iteration} - #{symbol}"
                puts "=" * 60

                # Show errors if any
                if result[:errors].any?
                  puts "\n⚠ Errors:"
                  result[:errors].each { |error| puts "  - #{error}" }
                end

                # Show timeframe status
                puts "\nTimeframes:"
                result[:timeframes].each do |tf_key, tf_data|
                  tf_name = tf_key.to_s.gsub(/^tf_/, "").upcase
                  status = tf_data[:status] || "pending"
                  puts "  #{tf_name}: #{status}"
                end

                # Show recommendation if available
                if result[:recommendation]
                  rec = result[:recommendation]
                  puts "\nRecommendation: #{rec[:action].upcase}"
                  puts "  #{rec[:reason]}"
                  if rec[:strike]
                    puts "  Strike: #{rec[:strike]}"
                    puts "  Entry: #{rec[:entry]}" if rec[:entry]
                    puts "  Stop Loss: #{rec[:stop_loss]}" if rec[:stop_loss]
                    puts "  Target: #{rec[:target]}" if rec[:target]
                  end
                  puts "  Confidence: #{(result[:confidence] * 100).round(1)}%"
                else
                  puts "\nNo recommendation available"
                end

                puts "=" * 60
              else
                spinner.stop("No changes detected") if spinner
                puts "  [#{Time.now.strftime("%H:%M:%S")}] No significant changes"
              end

              previous_state = current_state
            rescue StandardError => e
              if spinner
                spinner.stop("Error!")
              else
                puts "error!"
              end
              puts "\n[#{Time.now.strftime("%H:%M:%S")}] Error: #{e.message}"
              puts e.backtrace.join("\n") if @global_opts[:debug]
            end

            # Sleep for interval (unless interrupted)
            break unless @running

            # Sleep in small increments to allow SIGINT to be caught
            sleep_remaining = @interval
            while sleep_remaining > 0 && @running
              sleep([sleep_remaining, 1].min)
              sleep_remaining -= 1
            end
          end
        rescue Interrupt
          # Already handled by signal trap
        end

        puts "\nWatch mode stopped."
      end

      private

      def build_state_summary(result)
        {
          recommendation: result[:recommendation]&.dig(:action),
          confidence: result[:confidence]&.round(2),
          timeframes: result[:timeframes]&.transform_values { |v| v[:status] },
          errors: result[:errors]&.any?
        }
      end

      def state_different?(prev, curr)
        return true if prev[:recommendation] != curr[:recommendation]
        return true if (prev[:confidence] || 0).round(2) != (curr[:confidence] || 0).round(2)
        return true if prev[:timeframes] != curr[:timeframes]
        return true if prev[:errors] != curr[:errors]

        false
      end

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

        return unless @interval < 1

        puts "Error: interval must be at least 1 second"
        exit 1
      end
    end
  end
end
