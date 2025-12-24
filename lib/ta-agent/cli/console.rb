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
        @commands = %w[analyse analyze watch menu help version clear exit quit mode models list_models set_model]
        @current_mode = nil # nil = command mode, :chat, :agent, :planning, :deep_research
        @mode_history = {} # Store conversation history per mode
        @config = nil # Will be loaded when needed
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
          Use 'mode <name>' to switch modes (chat, agent, planning, deep_research).
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
            prompt_text = build_prompt
            command = @readline_module.public_send(@readline_method, prompt_text, true)

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

      def build_prompt
        if @current_mode
          "ta-agent[#{@current_mode}]> "
        else
          "ta-agent> "
        end
      end

      def handle_command(cmd)
        # Check if it's a single-letter command (like 'v' for version, 'h' for help)
        # These should work even in modes
        if cmd.length == 1
          case cmd.downcase
          when "v"
            puts "ta-agent #{TaAgent::VERSION}"
            return
          when "h"
            show_help
            return
          when "q"
            @running = false
            puts "Goodbye!"
            return
          when "c"
            system("clear") || system("cls")
            return
          end
        end

        # If in a mode, treat input as a prompt for that mode (unless it's a mode command)
        if @current_mode && !cmd.downcase.start_with?("mode ")
          handle_mode_prompt(cmd)
          return
        end

        # Handle mode switching
        if cmd.downcase.start_with?("mode ")
          mode_name = cmd.downcase.sub(/^mode\s+/, "").strip.to_sym
          switch_mode(mode_name)
          return
        end

        # Regular commands
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
        when "models", "list_models"
          list_available_models
        when /^set_model(?:\s+(.+))?$/i
          model_name = Regexp.last_match(1)&.strip
          if model_name
            set_model_direct(model_name)
          else
            set_model_interactive
          end
        else
          puts "Unknown command: #{cmd}"
          puts "Type 'help' for available commands"
          puts "Or use 'mode <name>' to enter a mode (chat, agent, planning, deep_research)"
        end
      end

      def show_help
        puts <<~HELP
          Available Commands:
            mode <name>      - Switch to a mode (chat, agent, planning, deep_research)
            analyse SYMBOL    - Run one-time analysis for SYMBOL (e.g., NIFTY)
            watch SYMBOL      - Start interactive monitoring for SYMBOL
            models            - List available Ollama models
            set_model [NAME]  - Set/change the Ollama model (interactive if no name provided)
            menu              - Show interactive menu
            version           - Show version (or 'v')
            clear             - Clear screen (or 'c')
            help              - Show this help (or 'h')
            exit              - Exit console (or 'q')

          Modes:
            mode chat         - Enter chat mode (direct prompts to LLM)
            mode agent        - Enter agent mode (tool-assisted reasoning)
            mode planning     - Enter planning mode (strategic analysis)
            mode deep_research - Enter deep research mode (comprehensive analysis)
            mode off          - Exit current mode and return to command mode

          Examples:
            ta-agent> mode chat
            ta-agent[chat]> What is RSI?
            ta-agent[chat]> mode off

            ta-agent> mode agent
            ta-agent[agent]> Analyze NIFTY and explain the trend

            ta-agent> analyse NIFTY
            ta-agent> watch NIFTY
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
            puts "  #{tf.to_s.upcase}: #{data[:status] || "pending"}"
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
          puts e.backtrace.join("\n") if @global_opts[:debug]
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
                spinner.stop("No changes detected")
                puts "  [#{Time.now.strftime("%H:%M:%S")}] No significant changes"
              end

              previous_state = current_state
            rescue StandardError => e
              spinner.stop("Error!")
              puts "\n[#{Time.now.strftime("%H:%M:%S")}] Error: #{e.message}"
              puts e.backtrace.join("\n") if @global_opts[:debug]
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

      def switch_mode(mode_name)
        case mode_name
        when :off, "off"
          if @current_mode
            puts "Exiting #{@current_mode} mode"
            @current_mode = nil
          else
            puts "Not in any mode"
          end
        when :chat, "chat"
          @current_mode = :chat
          puts "Entered chat mode. Type your questions directly, or 'mode off' to exit."
          puts "Example: What is RSI?"
        when :agent, "agent"
          @current_mode = :agent
          puts "Entered agent mode. Type your goals/tasks directly, or 'mode off' to exit."
          puts "Example: Analyze NIFTY and explain the current trend"
        when :planning, "planning"
          @current_mode = :planning
          puts "Entered planning mode. Type your strategic questions directly, or 'mode off' to exit."
          puts "Example: What's the best strategy for trading NIFTY options today?"
        when :deep_research, "deep_research", "deepresearch"
          @current_mode = :deep_research
          puts "Entered deep research mode. Type your research questions directly, or 'mode off' to exit."
          puts "Example: Research the correlation between NIFTY and VIX"
        else
          puts "Unknown mode: #{mode_name}"
          puts "Available modes: chat, agent, planning, deep_research"
        end
      end

      def handle_mode_prompt(prompt)
        case @current_mode
        when :chat
          handle_chat_mode(prompt)
        when :agent
          handle_agent_mode(prompt)
        when :planning
          handle_planning_mode(prompt)
        when :deep_research
          handle_deep_research_mode(prompt)
        end
      end

      def handle_chat_mode(prompt)
        load_config_if_needed
        return unless @config&.ollama_enabled?

        require_relative "../llm/ollama_client"
        spinner = TTY::Spinner.new("[:spinner] Thinking...", format: :dots)
        spinner.auto_spin

        begin
          # Use longer timeout for chat operations (60 seconds)
          client = TaAgent::LLM::OllamaClient.new(
            host_url: @config.ollama_host_url,
            model: @config.ollama_model,
            timeout: 60
          )

          # Get conversation history for chat mode
          messages = @mode_history[:chat] || []
          messages << { role: "user", content: prompt }

          response = client.chat(messages: messages)
          spinner.stop("Done!")

          if response && !response[:content].empty?
            puts "\n#{response[:content]}\n"
            # Add to history
            messages << { role: "assistant", content: response[:content] }
            @mode_history[:chat] = messages.last(10) # Keep last 10 messages
          else
            puts "\n⚠️  Empty response received\n"
          end
        rescue TaAgent::OllamaError => e
          spinner.stop("Error!")
          error_msg = e.message
          puts "\n❌ Error: #{error_msg}\n"
          handle_ollama_error(error_msg)
        rescue StandardError => e
          spinner.stop("Error!")
          puts "\n❌ Error: #{e.message}\n"
          puts e.backtrace.join("\n") if @global_opts[:debug]
        end
      end

      def handle_agent_mode(prompt)
        load_config_if_needed
        return unless @config&.ollama_enabled?

        require_relative "../agent/loop"
        require_relative "../agent/tool_registry"
        spinner = TTY::Spinner.new("[:spinner] Agent working...", format: :dots)
        spinner.auto_spin

        begin
          registry = TaAgent::Agent::ToolRegistry.new(mode: :alert)
          loop = TaAgent::Agent::Loop.new(
            goal: prompt,
            initial_context: {},
            tool_registry: registry,
            config: @config
          )

          result = loop.run
          spinner.stop("Done!")

          if result[:success]
            puts "\n" + "=" * 60
            puts "Agent Result:"
            puts "=" * 60
            puts result[:answer] || "Task completed"
            puts "\nSteps taken: #{result[:steps]}" if result[:steps]
            puts "=" * 60 + "\n"
          else
            puts "\n❌ Agent error: #{result[:error]}\n"
          end
        rescue StandardError => e
          spinner.stop("Error!")
          puts "\n❌ Error: #{e.message}\n"
          puts e.backtrace.join("\n") if @global_opts[:debug]
        end
      end

      def handle_planning_mode(prompt)
        load_config_if_needed
        return unless @config&.ollama_enabled?

        require_relative "../llm/ollama_client"
        spinner = TTY::Spinner.new("[:spinner] Planning...", format: :dots)
        spinner.auto_spin

        begin
          # Use longer timeout for planning operations (60 seconds)
          client = TaAgent::LLM::OllamaClient.new(
            host_url: @config.ollama_host_url,
            model: @config.ollama_model,
            timeout: 60
          )

          system_prompt = <<~PROMPT
            You are a strategic trading analyst for Indian markets (NIFTY/options).
            Your role is to provide strategic planning, risk assessment, and trading strategy recommendations.
            Focus on:
            - Market context and timing
            - Risk management strategies
            - Entry and exit planning
            - Position sizing recommendations
            - Market condition analysis
          PROMPT

          messages = [
            { role: "system", content: system_prompt },
            { role: "user", content: prompt }
          ]

          response = client.chat(messages: messages)
          spinner.stop("Done!")

          if response && !response[:content].empty?
            puts "\n" + "=" * 60
            puts "Strategic Analysis:"
            puts "=" * 60
            puts response[:content]
            puts "=" * 60 + "\n"
          else
            puts "\n⚠️  Empty response received\n"
          end
        rescue TaAgent::OllamaError => e
          spinner.stop("Error!")
          error_msg = e.message
          puts "\n❌ Error: #{error_msg}\n"
          handle_ollama_error(error_msg)
        rescue StandardError => e
          spinner.stop("Error!")
          puts "\n❌ Error: #{e.message}\n"
          puts e.backtrace.join("\n") if @global_opts[:debug]
        end
      end

      def handle_deep_research_mode(prompt)
        load_config_if_needed
        return unless @config&.ollama_enabled?

        require_relative "../llm/ollama_client"
        spinner = TTY::Spinner.new("[:spinner] Researching...", format: :dots)
        spinner.auto_spin

        begin
          # Use longer timeout for research operations (90 seconds)
          client = TaAgent::LLM::OllamaClient.new(
            host_url: @config.ollama_host_url,
            model: @config.ollama_model,
            timeout: 90
          )

          system_prompt = <<~PROMPT
            You are a deep research analyst for Indian stock markets.
            Your role is to provide comprehensive, detailed analysis including:
            - Technical indicator analysis
            - Market structure and patterns
            - Historical context and comparisons
            - Multi-timeframe analysis
            - Correlation analysis
            - Risk factors and considerations
            Provide thorough, well-structured research with supporting reasoning.
          PROMPT

          messages = [
            { role: "system", content: system_prompt },
            { role: "user", content: prompt }
          ]

          response = client.chat(messages: messages)
          spinner.stop("Done!")

          if response && !response[:content].empty?
            puts "\n" + "=" * 60
            puts "Research Report:"
            puts "=" * 60
            puts response[:content]
            puts "=" * 60 + "\n"
          else
            puts "\n⚠️  Empty response received\n"
          end
        rescue TaAgent::OllamaError => e
          spinner.stop("Error!")
          error_msg = e.message
          puts "\n❌ Error: #{error_msg}\n"
          handle_ollama_error(error_msg)
        rescue StandardError => e
          spinner.stop("Error!")
          puts "\n❌ Error: #{e.message}\n"
          puts e.backtrace.join("\n") if @global_opts[:debug]
        end
      end

      def handle_ollama_error(error_msg)
        # Provide helpful suggestions for common Ollama errors
        if error_msg.include?("not found") || error_msg.include?("404")
          puts "💡 Model '#{@config&.ollama_model}' is not available."
          puts "   Try: 'models' to list available models"
          puts "   Or: 'mode off' to exit current mode and configure a different model"
          puts "   To install a model: ollama pull llama3.2:3b"
        elsif error_msg.include?("ReadTimeout") || error_msg.include?("timeout")
          puts "💡 Request timed out connecting to Ollama at #{@config&.ollama_host_url}"
          puts "   Possible causes:"
          puts "   - Ollama server is slow or overloaded"
          puts "   - Network connectivity issues"
          puts "   - Model is taking too long to respond"
          puts "   Try: Check if Ollama is running and responsive"
          puts "   Or: Use a smaller/faster model"
        elsif error_msg.include?("connection failed") || error_msg.include?("Connection refused") || error_msg.include?("closed")
          puts "💡 Cannot connect to Ollama at #{@config&.ollama_host_url}"
          puts "   Make sure Ollama is running: ollama serve"
          puts "   Or check if the host/port is correct"
        end
      end

      def load_config_if_needed
        return if @config

        begin
          @config = TaAgent::Config.load
        rescue TaAgent::ConfigurationError => e
          puts "Configuration Error: #{e.message}"
          puts "LLM features require Ollama to be configured."
          puts "Set OLLAMA_HOST_URL environment variable or configure in ~/.ta-agent/config.yml"
          @config = nil
        end
      end

      def list_available_models_quiet
        load_config_if_needed
        return [] unless @config&.ollama_enabled?

        require "faraday"
        require "json"

        host_url = @config.ollama_host_url

        begin
          conn = Faraday.new(url: host_url) do |c|
            c.request :json
            c.response :json
            c.options.timeout = 5
          end

          response = conn.get("/api/tags")
          return [] unless response.success?

          body = response.body
          models = if body.is_a?(Hash)
                     body["models"] || body[:models] || []
                   elsif body.is_a?(Array)
                     body
                   else
                     []
                   end

          models.map do |model|
            model["name"] || model[:name] || model["model"] || model[:model]
          end.compact
        rescue StandardError
          []
        end
      end

      def list_available_models
        load_config_if_needed
        return [] unless @config&.ollama_enabled?

        require "faraday"
        require "json"

        host_url = @config.ollama_host_url
        puts "🔍 Fetching models from: #{host_url}/api/tags"

        begin
          conn = Faraday.new(url: host_url) do |c|
            c.request :json
            c.response :json
            c.options.timeout = 5
          end

          response = conn.get("/api/tags")

          unless response.success?
            puts "❌ Failed to list models: HTTP #{response.status}"
            puts "💡 Make sure Ollama is running: ollama serve"
            return []
          end

          body = response.body
          models = if body.is_a?(Hash)
                     body["models"] || body[:models] || []
                   elsif body.is_a?(Array)
                     body
                   else
                     []
                   end

          if models.empty?
            puts "⚠️  No models found on this Ollama server."
            puts "\n💡 To install a model, run in terminal:"
            puts "   ollama pull llama3.2:3b"
            puts "   ollama pull mistral"
            puts "   ollama pull llama2"
            puts "\nOr check if models exist: ollama list"
            []
          else
            puts "\n📋 Available models (#{models.length}):"
            current_model = @config.ollama_model
            model_names = []
            models.each do |model|
              name = model["name"] || model[:name] || model["model"] || model[:model] || "unknown"
              size = model["size"] || model[:size]
              size_str = size ? " (#{(size / 1024.0 / 1024.0 / 1024.0).round(2)} GB)" : ""
              # Case-insensitive comparison for model names
              marker = name.downcase == current_model.downcase ? " ← current" : ""
              puts "  • #{name}#{size_str}#{marker}"
              model_names << name
            end
            puts "\n💡 Current model: #{current_model}"
            # Case-insensitive check for model availability
            if model_names.any? { |name| name.downcase == current_model.downcase }
              puts "   ✅ Model is available"
            else
              puts "   ⚠️  Model is NOT available on this server"
              puts "   💡 Use 'set_model' to change to an available model"
            end
            model_names
          end
        rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
          puts "❌ Connection failed: #{e.message}"
          puts "💡 Make sure Ollama is running at #{host_url}"
          puts "   Start it with: ollama serve"
          []
        rescue StandardError => e
          puts "❌ Error listing models: #{e.message}"
          puts e.backtrace.join("\n") if @global_opts[:debug]
          []
        end
      end

      def set_model_direct(model_name)
        load_config_if_needed
        return unless @config&.ollama_enabled?

        current_model = @config.ollama_model
        if model_name == current_model
          puts "Model is already set to #{model_name}"
          return
        end

        # Verify model exists (optional check, but helpful)
        available_models = list_available_models_quiet
        if available_models.any? && !available_models.any? { |name| name.downcase == model_name.downcase }
          puts "⚠️  Warning: Model '#{model_name}' not found in available models"
          puts "   Available models: #{available_models.join(", ")}"
          puts "   Continuing anyway (model might be available but not listed)"
        end

        # Update config file
        update_config_model(model_name)

        # Reload config
        @config = TaAgent::Config.load
        puts "\n✅ Model set to: #{model_name}"
        puts "💡 Changes saved to ~/.ta-agent/config.yml"
        puts "   Note: Restart console or use 'mode off' and re-enter mode to use new model"
      end

      def set_model_interactive
        load_config_if_needed
        return unless @config&.ollama_enabled?

        # Get available models
        available_models = list_available_models
        return if available_models.empty?

        current_model = @config.ollama_model
        puts "\n" + "=" * 60
        puts "Set Ollama Model"
        puts "=" * 60
        puts "Current model: #{current_model}"
        puts "=" * 60

        # Let user select
        selected = @prompt.select("Choose a model:", available_models, default: current_model)

        if selected == current_model
          puts "Model is already set to #{selected}"
          return
        end

        # Update config file
        update_config_model(selected)

        # Reload config
        @config = TaAgent::Config.load
        puts "\n✅ Model set to: #{selected}"
        puts "💡 Changes saved to ~/.ta-agent/config.yml"
        puts "   Note: Restart console or use 'mode off' and re-enter mode to use new model"
      end

      def update_config_model(new_model)
        require "yaml"
        require "fileutils"

        config_file = TaAgent::Config::CONFIG_FILE
        config_dir = File.dirname(config_file)

        # Ensure directory exists
        FileUtils.mkdir_p(config_dir)

        # Read existing config or create new
        config_data = if File.exist?(config_file)
                        YAML.safe_load(File.read(config_file), permitted_classes: [Symbol]) || {}
                      else
                        {}
                      end

        # Update model
        config_data["ollama"] ||= {}
        config_data["ollama"]["model"] = new_model

        # Write back
        File.write(config_file, YAML.dump(config_data))
      end
    end
  end
end
