# frozen_string_literal: true

# TaAgent::CLI::Config
#
# Interactive configuration command.
#
# Usage: ta-agent config
#
# Design:
# - Uses TTY::Prompt for interactive setup
# - Creates/updates ~/.ta-agent/config.yml
# - Validates ENV variables
# - Guides user through setup
module TaAgent
  module CLI
    class Config
      def self.call(argv, global_opts)
        new(argv, global_opts).call
      end

      def initialize(argv, global_opts)
        @argv = argv
        @global_opts = global_opts
      end

      def call
        # TODO: Implement interactive config
        # - Use TTY::Prompt
        # - Check ENV vars
        # - Create/update config file
        # - Validate and save
        puts "Config command - Implementation pending"
        puts "This will guide you through interactive configuration setup"
        exit 0
      end
    end
  end
end

