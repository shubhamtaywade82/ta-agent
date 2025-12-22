# frozen_string_literal: true

# TaAgent::CLI::Console
#
# Interactive console/REPL mode (like Rails console).
#
# Usage: ta-agent console
#
# Features:
# - Interactive prompt with TTY tools
# - Run analysis commands interactively
# - Explore data and results
# - Real-time monitoring with interactive controls
#
# Design:
# - Uses TTY::Prompt for interactive menus
# - Provides command history
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
        @running = true
      end

      def call
        require "tty-prompt"
        require "tty-spinner"
        require "tty-table"

        @prompt = TTY::Prompt.new

        puts <<~BANNER
          ╔═══════════════════════════════════════════════════════════╗
          ║         ta-agent Interactive Console                      ║
          ║         Technical Analysis Agent for Indian Markets       ║
          ╚═══════════════════════════════════════════════════════════╝

          Type 'help' for available commands, 'exit' to quit.
        BANNER

        main_loop
      end

      private

      def main_loop
        while @running
          begin
            command = @prompt.ask("ta-agent> ", default: "")

            next if command.nil? || command.strip.empty?

            handle_command(command.strip)
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

        # TODO: Implement actual analysis
        # For now, show placeholder with config info
        spinner = TTY::Spinner.new("[:spinner] Analyzing...", format: :dots)
        spinner.auto_spin
        sleep(1) # Simulate work
        spinner.stop("Done!")

        puts "\nAnalysis results for #{symbol}:"
        puts "  Config: ✓ Loaded"
        puts "  Ollama: #{config.ollama_enabled? ? 'Enabled' : 'Disabled'}"
        puts "  Status: Implementation pending"
        puts "  This will show actual TA results when implemented\n"
      end

      def run_watch_interactive(symbol, interval = 60)
        puts "\n[Watch] Starting interactive monitoring for #{symbol} (interval: #{interval}s)"
        puts "Press Ctrl+C to stop\n"

        begin
          loop do
            spinner = TTY::Spinner.new("[:spinner] Monitoring #{symbol}...", format: :dots)
            spinner.auto_spin

            # TODO: Implement actual watch logic
            sleep(interval)

            spinner.stop("Update received")

            # Show update (placeholder)
            puts "  [#{Time.now.strftime('%H:%M:%S')}] #{symbol}: Status check - Implementation pending"

            # Ask if user wants to continue
            continue = @prompt.yes?("Continue monitoring?")
            break unless continue
          end
        rescue Interrupt
          puts "\n\nMonitoring stopped."
        end
      end
    end
  end
end

