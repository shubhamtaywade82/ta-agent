# frozen_string_literal: true

# TaAgent::Agent::LoopState
#
# State management for agent loop.
#
# Responsibilities:
# - Track conversation history
# - Track step count
# - Track tool results
# - Track stop conditions
#
# Design:
# - Immutable state updates (functional style)
# - Clear stop conditions
# - Memory discipline
module TaAgent
  module Agent
    class LoopState
      MAX_STEPS = 3
      MAX_MEMORY_ITEMS = 50

      attr_reader :goal, :step_count, :memory, :last_tool_result, :conversation_history, :tool_cache

      def initialize(goal:, initial_context: {})
        @goal = goal
        @step_count = 0
        @memory = []
        @last_tool_result = nil
        @conversation_history = []
        @initial_context = initial_context
        @stop_reason = nil
        @tool_cache = {} # Cache for tool results: { cache_key => result }
      end

      # Add LLM response to conversation
      # @param response [Hash] LLM response with :type, :content, :tool_name, :arguments
      # @return [LoopState] New state instance
      def add_llm_response(response)
        new_state = dup
        new_state.step_count += 1
        new_state.conversation_history << {
          role: "assistant",
          content: response[:content],
          tool_calls: response[:tool_calls] || []
        }
        new_state
      end

      # Add tool result to conversation
      # @param tool_name [Symbol] Tool name
      # @param result [Hash] Tool execution result
      # @return [LoopState] New state instance
      def add_tool_result(tool_name, result)
        new_state = dup
        new_state.last_tool_result = result
        new_state.memory << {
          tool: tool_name,
          result: result,
          timestamp: Time.now
        }
        # Trim memory if too large
        new_state.memory = new_state.memory.last(MAX_MEMORY_ITEMS)

        # Store concise tool result to reduce token usage
        tool_content = if result[:success] && result[:data]
                         # Extract essential data including recommendation and stop signals
                         essential_data = if result[:data].is_a?(Hash)
                                            # Build data hash with all important fields
                                            data_hash = {}

                                            # Always include these fields if they exist
                                            %i[symbol timeframes recommendation confidence timestamp errors
                                               status trend suitable value error stop_calling_tools message has_data].each do |key|
                                              data_hash[key] = result[:data][key] if result[:data].key?(key)
                                            end

                                            # Ensure recommendation is fully included (it's a hash, so include all its keys)
                                            if result[:data][:recommendation]
                                              data_hash[:recommendation] = result[:data][:recommendation]
                                            end

                                            # Ensure timeframes is included (it's a hash, so include all its keys)
                                            if result[:data][:timeframes]
                                              data_hash[:timeframes] = result[:data][:timeframes]
                                            end

                                            # Add explicit success indicator
                                            data_hash[:tool_execution_status] = "SUCCESS"
                                            data_hash[:data_available] = true
                                            data_hash
                                          else
                                            { tool_execution_status: "SUCCESS", data_available: true,
                                              value: result[:data] }
                                          end
                         { success: true, status: "SUCCESS", data: essential_data,
                           message: "Tool executed successfully. Data is available below." }.to_json
                       else
                         # Keep error messages concise
                         { success: false, status: "ERROR", error: result[:error] || "Unknown error",
                           message: "Tool execution failed." }.to_json
                       end

        new_state.conversation_history << {
          role: "tool",
          name: tool_name.to_s,
          content: tool_content
        }
        # Keep conversation history manageable - only last 10 messages
        new_state.conversation_history = new_state.conversation_history.last(10)
        new_state
      end

      # Check if loop should stop
      # @param response [Hash] Latest LLM response
      # @return [Hash] { stop?: Boolean, reason: String }
      def should_stop?(response)
        # Stop condition 1: Explicit final answer
        if response[:type] == "final" || response[:content]&.match?(/final.*answer|conclusion|recommendation/i)
          return { stop?: true, reason: "Explicit final answer" }
        end

        # Stop condition 2: Step limit
        return { stop?: true, reason: "Maximum steps (#{MAX_STEPS}) reached" } if @step_count >= MAX_STEPS

        # Stop condition 3: Confidence threshold (if in response)
        if response[:confidence] && response[:confidence] < 0.3
          return { stop?: true, reason: "Confidence too low (#{response[:confidence]})" }
        end

        # Stop condition 4: Error in tool execution
        if @last_tool_result && !@last_tool_result[:success]
          # Allow one retry, then stop
          error_count = @memory.count { |m| m[:result] && !m[:result][:success] }
          return { stop?: true, reason: "Too many tool errors" } if error_count >= 2
        end

        { stop?: false, reason: nil }
      end

      # Build prompt for LLM with full context
      # @return [String] Formatted prompt
      def build_prompt
        prompt_parts = []

        # System instruction
        prompt_parts << "You are a technical analysis assistant for Indian markets."
        prompt_parts << "Your goal: #{@goal}"
        prompt_parts << ""

        # Initial context
        if @initial_context.any?
          prompt_parts << "Initial Context:"
          prompt_parts << JSON.pretty_generate(@initial_context)
          prompt_parts << ""
        end

        # Memory summary (last 5 items)
        if @memory.any?
          prompt_parts << "Recent Tool Results:"
          @memory.last(5).each do |item|
            prompt_parts << "- #{item[:tool]}: #{item[:result][:success] ? "Success" : "Error: " + item[:result][:error]}"
          end
          prompt_parts << ""
        end

        # Conversation history
        if @conversation_history.any?
          prompt_parts << "Conversation History:"
          @conversation_history.last(10).each do |msg|
            role = msg[:role]
            if role == "assistant"
              prompt_parts << "Assistant: #{msg[:content]}"
            elsif role == "tool"
              prompt_parts << "Tool (#{msg[:name]}): #{msg[:content]}"
            end
          end
          prompt_parts << ""
        end

        prompt_parts << "Step: #{@step_count + 1}/#{MAX_STEPS}"
        prompt_parts << ""
        prompt_parts << "What would you like to do next? You can call tools or provide a final answer."

        prompt_parts.join("\n")
      end

      # Generate cache key from tool name and arguments
      # @param tool_name [Symbol, String] Tool name
      # @param arguments [Hash] Tool arguments
      # @return [String] Cache key
      def cache_key(tool_name, arguments)
        # Normalize arguments: convert to hash, sort keys, normalize symbol values
        normalized_args = if arguments.is_a?(Hash)
                            args_hash = {}
                            arguments.each do |k, v|
                              key = k.is_a?(Symbol) ? k.to_s : k.to_s
                              # Normalize symbol values (e.g., "SENSEX" vs "sensex")
                              value = if v.is_a?(String) && v.match?(/^[A-Z0-9]+$/)
                                        v.upcase
                                      else
                                        v
                                      end
                              args_hash[key] = value
                            end
                            # Sort keys for consistent cache keys
                            args_hash.sort.to_h
                          else
                            arguments
                          end

        # Create cache key: tool_name + sorted normalized arguments
        "#{tool_name}:#{normalized_args.to_json}"
      end

      # Get cached tool result if available
      # @param tool_name [Symbol, String] Tool name
      # @param arguments [Hash] Tool arguments
      # @return [Hash, nil] Cached result or nil
      def get_cached_result(tool_name, arguments)
        key = cache_key(tool_name, arguments)
        @tool_cache[key]
      end

      # Store tool result in cache
      # @param tool_name [Symbol, String] Tool name
      # @param arguments [Hash] Tool arguments
      # @param result [Hash] Tool result
      def cache_result(tool_name, arguments, result)
        key = cache_key(tool_name, arguments)
        @tool_cache[key] = result
      end

      protected

      attr_writer :step_count, :memory, :last_tool_result, :conversation_history, :tool_cache
    end
  end
end
