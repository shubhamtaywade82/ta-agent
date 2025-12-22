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
      # TODO: Implement analyse command
      # - Parse symbol argument
      # - Initialize runner
      # - Execute and format output
    end
  end
end

