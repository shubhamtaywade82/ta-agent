# frozen_string_literal: true

require "json"
require_relative "tool_registry"
require_relative "loop_state"
require_relative "../llm/ollama_client"
require_relative "../llm/response_parser"

# TaAgent::Agent::Loop
#
# Agent loop implementation (ReAct pattern).
#
# Responsibilities:
# - Execute agent loop (Think → Tool → Observe → Repeat)
# - Manage state and memory
# - Enforce stop conditions
# - Execute tools based on LLM decisions
#
# Design:
# - LLM decides what tools to call (doesn't execute)
# - Runtime executes tools
# - Tool results fed back to LLM
# - Loop continues until stop condition
#
# @example
#   loop = Agent::Loop.new(
#     goal: "Analyze NIFTY and recommend best option strike",
#     initial_context: context,
#     tool_registry: registry,
#     config: config
#   )
#   result = loop.run
module TaAgent
  module Agent
    class Loop
      attr_reader :state, :tool_registry, :config, :llm_client

      def initialize(goal:, initial_context: {}, tool_registry: nil, config: nil)
        @goal = goal
        @initial_context = initial_context
        @tool_registry = tool_registry || ToolRegistry.new(mode: :alert)
        @config = config || TaAgent::Config.instance
        @state = LoopState.new(goal: goal, initial_context: initial_context)
        @llm_client = nil
        @response_parser = TaAgent::LLM::ResponseParser.new
      end

      # Run the agent loop
      # @return [Hash] Final result with :success, :answer, :steps, :memory keys
      def run
        return { success: false, error: "LLM not enabled" } unless @config.ollama_enabled?

        initialize_llm_client

        loop do
          # 1. Get LLM response
          response = get_llm_response
          break if response.nil?

          # 2. Update state with LLM response
          @state = @state.add_llm_response(response)

          # 3. Check stop conditions
          stop_check = @state.should_stop?(response)
          return build_final_result(stop_check[:reason]) if stop_check[:stop?]

          # 4. Execute tool if LLM requested one
          next unless response[:type] == "tool_call" && response[:tool_name]

          tool_result = execute_tool(response[:tool_name], response[:arguments])
          @state = @state.add_tool_result(response[:tool_name], tool_result)

          # Check if tool error should stop loop
          stop_check = @state.should_stop?({})
          return build_final_result(stop_check[:reason]) if stop_check[:stop?]
        end

        build_final_result("Loop completed")
      end

      private

      def initialize_llm_client
        @llm_client = TaAgent::LLM::OllamaClient.new(
          host_url: @config.ollama_host_url,
          model: @config.ollama_model
        )
      rescue StandardError => e
        raise TaAgent::OllamaError, "Failed to initialize LLM client: #{e.message}"
      end

      def get_llm_response
        prompt = @state.build_prompt
        tools_schema = @tool_registry.to_json_schema

        # Call LLM with prompt and tool schemas
        raw_response = @llm_client.chat(
          messages: build_messages(prompt),
          tools: tools_schema
        )

        return nil unless raw_response

        # Parse response
        @response_parser.parse(raw_response)
      end

      def build_messages(prompt)
        messages = [
          {
            role: "system",
            content: build_system_prompt
          },
          {
            role: "user",
            content: prompt
          }
        ]

        # Add conversation history
        @state.conversation_history.each do |msg|
          messages << {
            role: msg[:role],
            content: msg[:content],
            name: msg[:name]
          }
        end

        messages
      end

      def build_system_prompt
        <<~PROMPT
          You are a technical analysis assistant for Indian markets (NIFTY/options).

          Available tools:
          #{@tool_registry.to_json_schema.map { |t| "- #{t[:function][:name]}: #{t[:function][:description]}" }.join("\n")}

          Rules:
          1. You can call tools to gather data
          2. After gathering data, analyze and provide a final answer
          3. Use JSON format for tool calls: {"type": "tool_call", "tool_name": "...", "arguments": {...}}
          4. Use {"type": "final", "content": "..."} for final answers
          5. Maximum #{LoopState::MAX_STEPS} steps allowed

          Current mode: #{@tool_registry.mode}
          #{@tool_registry.mode == :alert ? "⚠️ Execution tools are DISABLED - analysis only" : "⚠️ Execution tools are ENABLED - use with extreme caution"}
        PROMPT
      end

      def execute_tool(tool_name, arguments)
        @tool_registry.execute(tool_name.to_sym, arguments)
      end

      def build_final_result(stop_reason)
        {
          success: true,
          answer: extract_final_answer,
          steps: @state.step_count,
          memory: @state.memory,
          stop_reason: stop_reason,
          conversation: @state.conversation_history
        }
      end

      def extract_final_answer
        # Extract final answer from last assistant message
        last_assistant = @state.conversation_history.reverse.find { |m| m[:role] == "assistant" }
        last_assistant&.dig(:content) || "No final answer provided"
      end
    end
  end
end
