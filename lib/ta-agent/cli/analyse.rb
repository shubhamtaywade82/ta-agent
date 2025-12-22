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
        # Load and validate config
        begin
          config = TaAgent::Config.load
        rescue TaAgent::ConfigurationError => e
          puts "Configuration Error:"
          puts e.message
          exit 1
        end

        symbol = @argv.shift || config.default_symbol
        symbol = symbol.upcase

        require_relative "../agent/runner"

        puts "Analyzing #{symbol}..."
        puts "Config loaded: ✓"

        # Run analysis
        runner = TaAgent::Agent::Runner.new(symbol: symbol, config: config)
        result = runner.run

        # Format output
        format_result(result, config)
      end

      private

      def format_result(result, config)
        puts "\n" + "=" * 60
        puts "Analysis Results for #{result[:symbol]}"
        puts "=" * 60

        if result[:errors].any?
          puts "\n⚠ Errors:"
          result[:errors].each { |error| puts "  - #{error}" }
          puts
        end

        # Show timeframe status
        puts "\nTimeframes:"
        result[:timeframes].each do |tf, data|
          puts "  #{tf.to_s.upcase}: #{data[:status] || 'pending'}"
        end

        # Show recommendation
        if result[:recommendation]
          rec = result[:recommendation]
          puts "\nRecommendation:"
          puts "  Action: #{rec[:action].upcase}"
          puts "  Reason: #{rec[:reason]}"
          if rec[:strike]
            puts "  Strike: #{rec[:strike]}"
            puts "  Entry: #{rec[:entry]}" if rec[:entry]
            puts "  Stop Loss: #{rec[:stop_loss]}" if rec[:stop_loss]
            puts "  Target: #{rec[:target]}" if rec[:target]
          end
        end

        puts "\nConfidence: #{(result[:confidence] * 100).round(1)}%"
        puts "=" * 60
      end
    end
  end
end

