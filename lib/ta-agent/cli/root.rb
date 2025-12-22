# frozen_string_literal: true

require_relative "analyse"
require_relative "watch"
require_relative "config"
require_relative "console"

# TaAgent::CLI::Root
#
# Main CLI command router.
#
# Commands:
# - analyse SYMBOL    → Run one-time analysis
# - watch SYMBOL      → Continuous monitoring mode
# - config            → Interactive configuration
#
# Global flags:
# - --help, -h        → Show help
# - --version, -v     → Show version
# - --debug           → Enable debug logging
#
# Design:
# - Simple argument parsing (no heavy dependencies)
# - Delegate to specific command classes
# - Handle global flags (--help, --version, --debug)
#
# @example
#   TaAgent::CLI::Root.call(ARGV)
module TaAgent
  module CLI
    class Root
      def self.call(argv = ARGV)
        new(argv).call
      end

      def initialize(argv)
        @argv = argv.dup
        @global_opts = {}
      end

      def call
        parse_global_options

        return show_version if @global_opts[:version]
        return show_help if @global_opts[:help] || @argv.empty?

        command = @argv.shift

        case command
        when "analyse", "analyze"
          Analyse.call(@argv, @global_opts)
        when "watch"
          Watch.call(@argv, @global_opts)
        when "config"
          Config.call(@argv, @global_opts)
        when "console"
          Console.call(@argv, @global_opts)
        else
          show_help
          exit 1
        end
      rescue Interrupt
        puts "\nInterrupted."
        exit 130
      rescue StandardError => e
        if @global_opts[:debug]
          raise
        else
          puts "Error: #{e.message}"
          exit 1
        end
      end

      private

      def parse_global_options
        @argv.reject! do |arg|
          case arg
          when "--version", "-v"
            @global_opts[:version] = true
            true
          when "--help", "-h"
            @global_opts[:help] = true
            true
          when "--debug"
            @global_opts[:debug] = true
            true
          else
            false
          end
        end
      end

      def show_version
        puts "ta-agent #{TaAgent::VERSION}"
      end

      def show_help
        puts <<~HELP
          ta-agent - CLI-first Technical Analysis Agent for Indian markets

          Usage:
            ta-agent analyse SYMBOL          Run one-time analysis
            ta-agent watch SYMBOL [OPTIONS]  Continuous monitoring mode
            ta-agent console                 Interactive console/REPL mode
            ta-agent config                  Interactive configuration

          Commands:
            analyse, analyze    Run technical analysis for SYMBOL (e.g., NIFTY)
            watch               Monitor SYMBOL continuously (prints only state changes)
            console             Start interactive console (like Rails console)
            config              Interactive configuration setup

          Options:
            --help, -h          Show this help message
            --version, -v       Show version
            --debug             Enable debug logging

          Examples:
            ta-agent analyse NIFTY
            ta-agent watch NIFTY --interval 60
            ta-agent console
            ta-agent config

          Environment Variables:
            DHANHQ_CLIENT_ID        DhanHQ API client ID (required)
            DHANHQ_ACCESS_TOKEN    DhanHQ API access token (required)
            OLLAMA_HOST_URL        Ollama server URL (optional, default: http://localhost:11434)

          Config File:
            ~/.ta-agent/config.yml (optional)
        HELP
      end
    end
  end
end
