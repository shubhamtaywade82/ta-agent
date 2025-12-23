# frozen_string_literal: true

# TaAgent::CLI::Console
#
# Interactive console/REPL mode (like Rails console).
#
# Usage: ta-agent console
#
# Features:
# - Interactive prompt with Readline/Reline support
# - Command history with arrow key navigation
# - Tab completion for commands
# - Run analysis commands interactively
# - Explore data and results
# - Real-time monitoring with interactive controls
#
# Design:
# - Uses Readline/Reline for command history and completion
# - Uses TTY::Prompt for interactive menus
# - Supports all analysis commands in interactive mode
module TaAgent
  module CLI
    class Console
      def self.call(argv, global_opts)
        new(argv, global_opts).call
      end

      def initialize(argv, global_opts)
        @argv = argv
        @global_opts = global_opts
        @prompt = nil # Will be initialized with TTY::Prompt
        @readline_module = nil # Will be initialized with Readline or Reline
        @readline_method = :readline
        @running = true
        @history_file = File.expand_path("~/.ta-agent/history")
        @commands = %w[analyse analyze watch menu help version clear exit quit]
      end

      def call
        require "tty-prompt"
        require "tty-spinner"
        require "tty-table"
        require "fileutils"
        setup_readline

        @prompt = TTY::Prompt.new

        puts <<~BANNER
          ╔═══════════════════════════════════════════════════════════╗
          ║         ta-agent Interactive Console                      ║
          ║         Technical Analysis Agent for Indian Markets       ║
          ╚═══════════════════════════════════════════════════════════╝

          Type 'help' for available commands, 'exit' to quit.
          Use ↑↓ arrow keys for command history, Tab for completion.
        BANNER

        main_loop
      ensure
        save_history
      end

      private

      def setup_readline
        # Try to use Reline (Ruby 3.1+) or fallback to Readline
        begin
          require "reline"
          @readline_module = Reline
          @readline_method = :readline
        rescue LoadError
          require "readline"
          @readline_module = Readline
          @readline_method = :readline
        end

        # Set up completion
        @readline_module.completion_proc = proc do |input|
          return [] if input.nil? || input.empty?

          input_lower = input.downcase
          matches = @commands.select { |cmd| cmd.downcase.start_with?(input_lower) }

          # If we have a partial match, also check for commands that might be in progress
          # (e.g., "analyse NIFTY" - we want to complete "analyse" first)
          if matches.empty? && input.include?(" ")
            # Command already entered, no completion needed
            []
          else
            matches
          end
        end

        # Load history
        load_history
      end

      def load_history
        return unless File.exist?(@history_file)
        return unless @readline_module.const_defined?(:HISTORY)

        File.readlines(@history_file, chomp: true).each do |line|
          next if line.strip.empty?

          history = @readline_module::HISTORY
          history.push(line) unless history.include?(line)
        end
      rescue StandardError => e
        warn "Warning: Could not load history: #{e.message}" if @global_opts[:debug]
      end

      def save_history
        return unless @readline_module
        return unless @readline_module.const_defined?(:HISTORY)

        # Ensure directory exists
        FileUtils.mkdir_p(File.dirname(@history_file))

        # Save last 1000 lines of history
        history = @readline_module::HISTORY
        history_lines = history.to_a.last(1000)
        File.write(@history_file, history_lines.join("\n") + "\n")
      rescue StandardError => e
        warn "Warning: Could not save history: #{e.message}" if @global_opts[:debug]
      end

      def main_loop
        while @running
          begin
            command = @readline_module.public_send(@readline_method, "ta-agent> ", true)

            # Handle EOF (Ctrl+D)
            break if command.nil?

            command = command.strip
            next if command.empty?

            # Add to history (Readline does this automatically, but ensure it's saved)
            handle_command(command)
          rescue Interrupt
            puts "\nUse 'exit' to quit or Ctrl+D"
          rescue StandardError => e
            if @global_opts[:debug]
              puts "Error: #{e.class}: #{e.message}"
              puts e.backtrace.join("\n")
            else
              puts "Error: #{e.message}"
            end
          end
        end
        puts "\nGoodbye!" if @running
      end

      def handle_command(cmd)
        case cmd.downcase
        when "exit", "quit", "q"
          @running = false
          puts "Goodbye!"
        when "help", "h"
          show_help
        when "version", "v"
          puts "ta-agent #{TaAgent::VERSION}"
        when "clear"
          system("clear") || system("cls")
        when /^analyse\s+(.+)/i, /^analyze\s+(.+)/i
          symbol = Regexp.last_match(1).strip
          run_analyse(symbol)
        when /^watch\s+(.+)/i
          symbol = Regexp.last_match(1).strip
          run_watch_interactive(symbol)
        when "menu", "m"
          show_menu
        else
          puts "Unknown command: #{cmd}"
          puts "Type 'help' for available commands"
        end
      end

      def show_help
        puts <<~HELP
          Available Commands:
            analyse SYMBOL    - Run one-time analysis for SYMBOL (e.g., NIFTY)
            watch SYMBOL       - Start interactive monitoring for SYMBOL
            menu              - Show interactive menu
            version           - Show version
            clear             - Clear screen
            help              - Show this help
            exit              - Exit console

          Examples:
            ta-agent> analyse NIFTY
            ta-agent> watch NIFTY
            ta-agent> menu
        HELP
      end

      def show_menu
        choice = @prompt.select("What would you like to do?") do |menu|
          menu.choice "Run Analysis", :analyse
          menu.choice "Watch Symbol", :watch
          menu.choice "Show Version", :version
          menu.choice "Help", :help
          menu.choice "Exit", :exit
        end

        case choice
        when :analyse
          symbol = @prompt.ask("Enter symbol (e.g., NIFTY):", default: "NIFTY")
          run_analyse(symbol)
        when :watch
          symbol = @prompt.ask("Enter symbol (e.g., NIFTY):", default: "NIFTY")
          interval = @prompt.ask("Interval in seconds:", default: "60").to_i
          run_watch_interactive(symbol, interval)
        when :version
          puts "ta-agent #{TaAgent::VERSION}"
        when :help
          show_help
        when :exit
          @running = false
          puts "Goodbye!"
        end
      end

      def run_analyse(symbol)
        puts "\n[Analysis] Running analysis for #{symbol}..."

        # Load config
        begin
          config = TaAgent::Config.load
        rescue TaAgent::ConfigurationError => e
          puts "Error: #{e.message}"
          return
        end

        symbol = symbol.upcase

        # Run analysis
        require_relative "../agent/runner"
        spinner = TTY::Spinner.new("[:spinner] Analyzing...", format: :dots)
        spinner.auto_spin

        begin
          runner = TaAgent::Agent::Runner.new(symbol: symbol, config: config)
          result = runner.run
          spinner.stop("Done!")

          # Format results
          puts "\n" + "=" * 60
          puts "Analysis Results for #{result[:symbol]}"
          puts "=" * 60

          if result[:errors].any?
            puts "\n⚠ Errors:"
            result[:errors].each { |error| puts "  - #{error}" }
          end

          puts "\nTimeframes:"
          result[:timeframes].each do |tf, data|
            puts "  #{tf.to_s.upcase}: #{data[:status] || 'pending'}"
          end

          if result[:recommendation]
            rec = result[:recommendation]
            puts "\nRecommendation: #{rec[:action].upcase}"
            puts "  #{rec[:reason]}"
            puts "  Confidence: #{(result[:confidence] * 100).round(1)}%"
          end

          puts "=" * 60 + "\n"
        rescue StandardError => e
          spinner.stop("Error!")
          puts "\nError: #{e.message}"
          if @global_opts[:debug]
            puts e.backtrace.join("\n")
          end
        end
      end

      def run_watch_interactive(symbol, interval = 60)
        puts "\n[Watch] Starting interactive monitoring for #{symbol} (interval: #{interval}s)"
        puts "Press Ctrl+C to stop\n"

        # Load config
        begin
          config = TaAgent::Config.load
        rescue TaAgent::ConfigurationError => e
          puts "Error: #{e.message}"
          return
        end

        symbol = symbol.upcase
        require_relative "../agent/runner"

        previous_state = nil
        iteration = 0

        begin
          loop do
            iteration += 1
            spinner = TTY::Spinner.new("[:spinner] Monitoring #{symbol}...", format: :dots)
            spinner.auto_spin

            # Run analysis
            begin
              runner = TaAgent::Agent::Runner.new(symbol: symbol, config: config)
              result = runner.run
              spinner.stop("Analysis complete")

              # Check if state changed
              current_state = build_state_summary(result)
              state_changed = previous_state.nil? || state_different?(previous_state, current_state)

              if state_changed || iteration == 1
                puts "\n" + "=" * 60
                puts "[#{Time.now.strftime('%H:%M:%S')}] Update ##{iteration} - #{symbol}"
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
                spinner.stop("No changes detected")
                puts "  [#{Time.now.strftime('%H:%M:%S')}] No significant changes"
              end

              previous_state = current_state

            rescue StandardError => e
              spinner.stop("Error!")
              puts "\n[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
              if @global_opts[:debug]
                puts e.backtrace.join("\n")
              end
            end

            # Ask if user wants to continue
            continue = @prompt.yes?("Continue monitoring?")
            break unless continue
          end
        rescue Interrupt
          puts "\n\nMonitoring stopped."
        end
      end

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
    end
  end
end

