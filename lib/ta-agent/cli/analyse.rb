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

        puts "Analyzing #{symbol}..."
        puts "Config loaded: ✓"
        puts "  DhanHQ Client ID: #{config.dhanhq_client_id[0..10]}..."
        puts "  Ollama: #{config.ollama_enabled? ? 'Enabled' : 'Disabled'}"
        puts "  Default Symbol: #{config.default_symbol}"
        puts "  Confidence Threshold: #{config.confidence_threshold}"

        # TODO: Implement actual analysis
        # - Initialize TaAgent::Agent::Runner with symbol
        # - Run analysis
        # - Format output
        puts "\n[Analysis] Running analysis for #{symbol}..."
        puts "Status: Implementation pending"
        puts "This will run technical analysis for #{symbol} when implemented"
        exit 0
      end
    end
  end
end

