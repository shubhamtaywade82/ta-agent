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
      MAX_STEPS = 10
      MAX_MEMORY_ITEMS = 50

      attr_reader :goal, :step_count, :memory, :last_tool_result, :conversation_history

      def initialize(goal:, initial_context: {})
        @goal = goal
        @step_count = 0
        @memory = []
        @last_tool_result = nil
        @conversation_history = []
        @initial_context = initial_context
        @stop_reason = nil
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

        new_state.conversation_history << {
          role: "tool",
          name: tool_name.to_s,
          content: result.to_json
        }
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
        if @step_count >= MAX_STEPS
          return { stop?: true, reason: "Maximum steps (#{MAX_STEPS}) reached" }
        end

        # Stop condition 3: Confidence threshold (if in response)
        if response[:confidence] && response[:confidence] < 0.3
          return { stop?: true, reason: "Confidence too low (#{response[:confidence]})" }
        end

        # Stop condition 4: Error in tool execution
        if @last_tool_result && !@last_tool_result[:success]
          # Allow one retry, then stop
          error_count = @memory.count { |m| m[:result] && !m[:result][:success] }
          if error_count >= 2
            return { stop?: true, reason: "Too many tool errors" }
          end
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
            prompt_parts << "- #{item[:tool]}: #{item[:result][:success] ? 'Success' : 'Error: ' + item[:result][:error]}"
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

      protected

      attr_writer :step_count, :memory, :last_tool_result, :conversation_history
    end
  end
end


