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

      def initialize(goal:, initial_context: {}, tool_registry: nil, config: nil, logger: nil)
        @goal = goal
        @initial_context = initial_context
        @tool_registry = tool_registry || ToolRegistry.new(mode: :alert)
        @config = config || TaAgent::Config.instance
        @state = LoopState.new(goal: goal, initial_context: initial_context)
        @llm_client = nil
        @response_parser = TaAgent::LLM::ResponseParser.new
        @logger = logger || create_default_logger
      end

      def create_default_logger
        # Simple logger that outputs to stderr (can be enhanced with TTY::Logger later)
        Object.new.tap do |logger|
          def logger.info(msg)
            Kernel.warn "[INFO] #{Time.now.strftime("%H:%M:%S")} #{msg}"
          end

          def logger.debug(msg)
            Kernel.warn "[DEBUG] #{Time.now.strftime("%H:%M:%S")} #{msg}"
          end

          def logger.warn(msg)
            Kernel.warn "[WARN] #{Time.now.strftime("%H:%M:%S")} #{msg}"
          end

          def logger.error(msg)
            Kernel.warn "[ERROR] #{Time.now.strftime("%H:%M:%S")} #{msg}"
          end
        end
      end

      # Run the agent loop
      # @return [Hash] Final result with :success, :answer, :steps, :memory keys
      def run
        @logger.info "🚀 Agent loop starting"
        @logger.info "📋 Goal: #{@goal}"
        @logger.info "🔧 Tool registry mode: #{@tool_registry.mode}"
        @logger.info "⚙️  Initial context: #{@initial_context.inspect}" unless @initial_context.empty?

        return { success: false, error: "LLM not enabled" } unless @config.ollama_enabled?

        initialize_llm_client
        @logger.info "✅ LLM client initialized: #{@config.ollama_model}"

        loop do
          @logger.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          @logger.info "🔄 Step #{@state.step_count + 1}/#{LoopState::MAX_STEPS} - Starting iteration"
          # 1. Soft safety net - Ollama controls termination, this is just a safety limit
          if @state.step_count >= LoopState::MAX_STEPS
            @logger.warn "⚠️  Step limit reached (#{LoopState::MAX_STEPS}), checking if Ollama wants to continue..."
            # Check if Ollama explicitly wants to continue despite limit
            last_message = @state.conversation_history.last
            unless last_message && last_message[:content]&.match?(/continue|need more|still missing|one more/i)
              @logger.warn "🛑 Stopping: Soft safety limit reached (#{LoopState::MAX_STEPS} steps)"
              return build_final_result("Soft safety limit reached (#{LoopState::MAX_STEPS} steps). Ollama should provide final answer.")
            end
            # Allow one more iteration if Ollama explicitly requests it
            if @state.step_count >= LoopState::MAX_STEPS + 2
              @logger.warn "🛑 Stopping: Extended limit reached (#{LoopState::MAX_STEPS + 2} steps)"
              return build_final_result("Soft safety limit reached (#{LoopState::MAX_STEPS + 2} steps). Ollama should have terminated by now.")
            end
            @logger.info "✅ Ollama requested continuation, allowing one more iteration"
          end

          # 2. Get LLM response
          @logger.info "🤖 Querying LLM for response..."
          response = get_llm_response
          if response.nil?
            @logger.error "❌ LLM returned no response"
            return build_final_result("LLM returned no response")
          end

          @logger.info "📥 LLM Response Type: #{response[:type]}"
          if response[:type] == "tool_call"
            @logger.info "🔧 Tool Call Detected: #{response[:tool_name]}"
            @logger.debug "   Arguments: #{response[:arguments].inspect}"
          elsif response[:type] == "text"
            content = response[:content]
            content_preview = if content && content.length > 100
                                "#{content[0..100]}..."
                              else
                                content
                              end
            @logger.info "💬 Text Response: #{content_preview}"
          elsif response[:type] == "final"
            @logger.info "✅ Final Answer Detected"
          end

          # 3. Update state with LLM response
          @state = @state.add_llm_response(response)

          # 4. Check stop conditions (only stop if it's a final answer, NOT a tool call)
          # IMPORTANT: Do NOT stop if the response contains tool call JSON - that's not a final answer!
          if response[:type] == "final"
            @logger.info "🛑 Stopping: Final answer provided"
            return build_final_result("Final answer provided")
          end

          # Check for Ollama's explicit stop signals in text responses
          if response[:type] == "text" && response[:content]
            content = response[:content]
            content_lower = content.downcase

            # Ollama explicitly says it's done (Ollama controls termination)
            explicit_stop = content_lower.match?(/final answer|analysis complete|here's my|recommendation:|conclusion:|i have enough|sufficient information|all data collected|ready to provide|analysis done|complete analysis/i) &&
                            !content_lower.match?(/need|missing|require|call|tool|fetch|wait/i) # Not asking for more

            if explicit_stop
              @logger.info "🛑 Stopping: Ollama explicitly terminated - final answer provided"
              return build_final_result("Ollama explicitly terminated - final answer provided")
            end

            # First check: Is this clearly a tool call JSON?
            is_tool_call_json = content.match?(/^\s*\{[\s\n]*"name"\s*:/) || # {"name": ...}
                                content.match?(/^\s*\{[\s\n]*"tool_calls"/) || # {"tool_calls": ...}
                                content.match?(/^\s*\{[\s\n]*"function"/) || # {"function": ...}
                                content.match?(/```json\s*\{[\s\n]*"name"/) || # ```json {"name": ...}
                                (content.match?(/\{[\s\n]*"name"/) && content.length < 500) # JSON with "name" that's not too long

            # If it looks like a tool call JSON, try to extract and execute it
            if is_tool_call_json
              @logger.info "🔍 Detected tool call JSON in text response, attempting extraction..."
              tool_call_from_text = @response_parser.send(:extract_tool_call_from_text, content)
              if tool_call_from_text && tool_call_from_text[:name]
                @logger.info "✅ Extracted tool call: #{tool_call_from_text[:name]}"
                @logger.debug "   Arguments: #{tool_call_from_text[:arguments].inspect}"
                # It's actually a tool call - execute it
                tool_result = execute_tool(tool_call_from_text[:name].to_sym, tool_call_from_text[:arguments] || {})
                pp tool_result
                @state = @state.add_tool_result(tool_call_from_text[:name].to_sym, tool_result)

                # Check for errors - but allow more retries before stopping
                if tool_result && !tool_result[:success]
                  @logger.error "❌ Tool execution failed: #{tool_result[:error]}"
                  error_count = @state.memory.count { |m| m[:result] && !m[:result][:success] }
                  @logger.warn "⚠️  Total errors so far: #{error_count}/5"
                  # Only stop if we have many consecutive errors (increase threshold)
                  # Allow the agent to try different tools even if some fail
                  if error_count >= 5
                    @logger.error "🛑 Stopping: Too many tool errors (#{error_count})"
                    return build_final_result("Too many tool errors (#{error_count}). Agent may need different tools or parameters.")
                  end
                  @logger.info "✅ Continuing despite error - agent can try different approaches"
                  # Continue even with errors - let the agent try other approaches
                else
                  @logger.info "✅ Tool executed successfully"
                  if tool_result && tool_result[:data]
                    @logger.debug "   Result preview: #{tool_result[:data].inspect[0..200]}"
                  end
                end

                # Continue loop to get next response with tool results
                next
              else
                # Looks like tool call but couldn't extract - try manual extraction
                # This is a fallback for when the parser fails
                begin
                  require "json"
                  # Try to find and parse the JSON object
                  # Look for { ... } pattern and extract it
                  json_start = content.index("{")
                  if json_start
                    # Find matching closing brace
                    brace_count = 0
                    json_end = json_start
                    content[json_start..].each_char.with_index do |char, idx|
                      brace_count += 1 if char == "{"
                      brace_count -= 1 if char == "}"
                      if brace_count == 0
                        json_end = json_start + idx
                        break
                      end
                    end

                    if brace_count == 0
                      json_str = content[json_start..json_end]
                      parsed = JSON.parse(json_str)
                      if parsed["name"]
                        tool_result = execute_tool(parsed["name"].to_sym, parsed["arguments"] || {})
                        @state = @state.add_tool_result(parsed["name"].to_sym, tool_result)

                        if tool_result && !tool_result[:success]
                          error_count = @state.memory.count { |m| m[:result] && !m[:result][:success] }
                          # Allow more errors before stopping - agent should try different approaches
                          if error_count >= 5
                            return build_final_result("Too many tool errors (#{error_count}). Agent may need different tools or parameters.")
                          end
                          # Continue even with errors
                        end

                        # Continue loop to get next response with tool results
                        next
                      end
                    end
                  end
                rescue StandardError
                  # Continue anyway - don't stop on parsing errors
                end
                # Continue loop (don't stop on tool call JSON, even if we couldn't parse it)
                next
              end
            end

            # Only treat as final if it's substantial AND not a tool call AND looks like analysis
            if content.length > 100 && # Must be substantial
               !is_tool_call_json &&
               content.match?(/final.*answer|conclusion|recommendation|summary|analysis|based on|according to|the data shows|indicators show/i)
              @logger.info "🛑 Stopping: Substantial final answer detected in text response"
              return build_final_result("Final answer provided")
            end

            # If it's a short text response that's not a tool call, continue to see if LLM wants to do more
            @logger.info "💬 Short text response, continuing to see if LLM wants to do more..."
            next
          end

          # 5. Execute tool if LLM requested one
          if response[:type] == "tool_call" && response[:tool_name]
            # Check if we already have recommendation data - if so, prevent more tool calls
            has_recommendation = @state.memory.any? do |m|
              m.dig(:result, :success) &&
                m.dig(:result, :data, :recommendation) &&
                [:fetch_market_data, "fetch_market_data"].include?(m[:tool])
            end

            if has_recommendation && [:fetch_market_data, "fetch_market_data"].include?(response[:tool_name])
              @logger.warn "⚠️  LLM trying to call fetch_market_data again, but recommendation already exists - forcing stop"
              # Return a message telling LLM to stop
              return build_final_result("Recommendation data already available. LLM should provide final analysis instead of calling more tools.")
            end

            # Check cache first - reuse result if we've called this exact tool with same parameters
            cached_result = @state.get_cached_result(response[:tool_name], response[:arguments] || {})

            if cached_result
              @logger.info "💾 Using cached result for #{response[:tool_name]}"
              @logger.debug "   Cache key: #{@state.cache_key(response[:tool_name], response[:arguments] || {})}"

              # Check if cached result has recommendation - if so, force LLM to stop calling tools
              if cached_result[:success] &&
                 cached_result[:data] &&
                 cached_result[:data].is_a?(Hash) &&
                 cached_result[:data][:recommendation]
                @logger.warn "⚠️  Cached result already contains recommendation - LLM should provide final answer now"
                # Add a special message to force the LLM to stop
                tool_result = cached_result.dup
                # Enhance the result with a stop signal
                if tool_result[:data]
                  tool_result[:data] = tool_result[:data].dup
                  tool_result[:data][:stop_calling_tools] = true
                  tool_result[:data][:message] =
                    "You already have all the data you need including recommendation. STOP calling tools and provide your final analysis now."
                end
              else
                tool_result = cached_result
              end

              @state = @state.add_tool_result(response[:tool_name], tool_result)
              # Continue loop to get next LLM response with cached result
              next
            end

            @logger.info "🔧 Executing tool: #{response[:tool_name]}"
            @logger.info "   Parameters: #{response[:arguments].inspect}"
            if response[:arguments] && !response[:arguments].empty?
              @logger.debug "   Full arguments: #{JSON.pretty_generate(response[:arguments])}"
            end

            tool_result = execute_tool(response[:tool_name], response[:arguments])

            # Cache the result for future use
            @state.cache_result(response[:tool_name], response[:arguments] || {}, tool_result)
            @logger.debug "💾 Cached result for #{response[:tool_name]}"

            @state = @state.add_tool_result(response[:tool_name], tool_result)

            # Log tool result
            if tool_result
              if tool_result[:success]
                @logger.info "✅ Tool '#{response[:tool_name]}' executed successfully"
                if tool_result[:data]
                  data_preview = if tool_result[:data].is_a?(Hash)
                                   tool_result[:data].keys.join(", ")
                                 else
                                   tool_result[:data].inspect[0..200]
                                 end
                  @logger.debug "   Result data keys: #{data_preview}"

                  # If fetch_market_data returned recommendation, log it prominently
                  if [:fetch_market_data, "fetch_market_data"].include?(response[:tool_name]) &&
                     tool_result[:data].is_a?(Hash) &&
                     tool_result[:data][:recommendation]
                    rec = tool_result[:data][:recommendation]
                    @logger.info "📊 Recommendation available: #{rec[:trend]} trend, Action: #{rec[:action]}"
                    @logger.info "   💡 LLM should now provide final analysis - no need to call fetch_market_data again"
                  end
                end
              else
                @logger.error "❌ Tool '#{response[:tool_name]}' failed: #{tool_result[:error]}"
              end
            else
              @logger.warn "⚠️  Tool '#{response[:tool_name]}' returned nil result"
            end

            # Check if tool error should stop loop (only for critical errors)
            # Allow more errors before stopping - agent should try different approaches
            if tool_result && !tool_result[:success]
              error_count = @state.memory.count { |m| m[:result] && !m[:result][:success] }
              @logger.warn "⚠️  Total errors so far: #{error_count}/5"
              # Only stop if we have many consecutive errors
              if error_count >= 5
                @logger.error "🛑 Stopping: Too many tool errors (#{error_count})"
                return build_final_result("Too many tool errors (#{error_count}). Agent may need different tools or parameters.")
              end
              @logger.info "✅ Continuing despite error - agent can try different approaches"
              # Continue even with errors - let the agent try other tools or provide analysis based on available data
            end

            # Continue loop to get next LLM response with tool results
            # The loop will continue and call get_llm_response again, which will include
            # the tool result in the conversation history via build_messages
            next
          end

          # 6. If it's a text response (not tool call, not final), check if it's substantial enough
          if response[:type] == "text" && response[:content]
            content = response[:content]
            # If it's a substantial response (more than 50 chars), treat it as a final answer
            if content.length > 50 && !content.match?(/would recommend|I should|need to call/i)
              @logger.info "🛑 Stopping: Substantial text response provided"
              return build_final_result("Text response provided")
            end

            # Otherwise, continue to see if LLM wants to call more tools
            @logger.info "💬 Text response detected, continuing..."
            next
          end

          # 7. If we get here, it's an unexpected response type - continue anyway
          @logger.warn "⚠️  Unexpected response type: #{response[:type]}, continuing..."
          next
        end

        # If loop exits without explicit stop, build result with whatever we have
        @logger.warn "⚠️  Loop exited without explicit stop condition"
        build_final_result("Loop completed - maximum iterations or no response")
      end

      private

      def initialize_llm_client
        @logger.info "🔌 Initializing LLM client..."
        @logger.debug "   Host: #{@config.ollama_host_url}"
        @logger.debug "   Model: #{@config.ollama_model}"
        @llm_client = TaAgent::LLM::OllamaClient.new(
          host_url: @config.ollama_host_url,
          model: @config.ollama_model
        )
        @logger.info "✅ LLM client initialized successfully"
      rescue StandardError => e
        @logger.error "❌ Failed to initialize LLM client: #{e.message}"
        @logger.debug "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
        raise TaAgent::OllamaError, "Failed to initialize LLM client: #{e.message}"
      end

      def get_llm_response
        prompt = @state.build_prompt
        tools_schema = @tool_registry.to_json_schema

        @logger.debug "📤 Sending request to LLM..."
        @logger.debug "   Available tools: #{tools_schema.map { |t| t[:function][:name] }.join(", ")}"
        @logger.debug "   Message count: #{build_messages(prompt).length}"

        # Call LLM with prompt and tool schemas
        start_time = Time.now
        raw_response = @llm_client.chat(
          messages: build_messages(prompt),
          tools: tools_schema
        )
        elapsed = Time.now - start_time

        if raw_response.nil?
          @logger.error "❌ LLM returned nil response"
          return nil
        end

        @logger.debug "📥 LLM response received in #{elapsed.round(2)}s"
        @logger.debug "   Raw response keys: #{raw_response.keys.join(", ")}"

        # Debug: Log what messages we're sending to LLM (especially tool results)
        if @logger.respond_to?(:debug)
          messages = build_messages(prompt)
          @logger.debug "📤 Messages being sent to LLM (#{messages.length} total):"
          messages.each_with_index do |msg, idx|
            if msg[:role] == "tool"
              # Show full tool content, not truncated
              content_str = if msg[:content].is_a?(String)
                              msg[:content]
                            else
                              require "json"
                              begin
                                JSON.pretty_generate(msg[:content])
                              rescue StandardError
                                msg[:content].inspect
                              end
                            end
              # Only show first 500 chars in debug, but indicate if truncated
              if content_str.length > 500
                @logger.debug "   [#{idx}] Tool: #{msg[:name]} - #{content_str[0..500]}... (#{content_str.length} total chars)"
              else
                @logger.debug "   [#{idx}] Tool: #{msg[:name]} - #{content_str}"
              end
            elsif msg[:role] == "system"
              @logger.debug "   [#{idx}] System: (prompt, #{msg[:content].length} chars)"
            else
              # Show more of user/assistant content in debug
              content_preview = msg[:content].is_a?(String) ? msg[:content] : msg[:content].inspect
              if content_preview.length > 200
                @logger.debug "   [#{idx}] #{msg[:role]}: #{content_preview[0..200]}... (#{content_preview.length} total chars)"
              else
                @logger.debug "   [#{idx}] #{msg[:role]}: #{content_preview}"
              end
            end
          end
        end

        # Parse response
        parsed = @response_parser.parse(raw_response)
        @logger.debug "   Parsed type: #{parsed[:type]}"
        parsed
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

        # Add conversation history - but only recent messages to reduce token usage
        # Keep last 6 messages (3 assistant + 3 tool responses) for context
        recent_history = @state.conversation_history.last(6)
        recent_history.each do |msg|
          # Make tool results more concise
          content = msg[:content]
          if msg[:role] == "tool" && content.is_a?(String)
            begin
              tool_result = JSON.parse(content)
              # Summarize tool results to reduce tokens
              if tool_result.is_a?(Hash)
                success = tool_result["success"] || tool_result[:success]
                status = tool_result["status"] || tool_result[:status] || (success ? "SUCCESS" : "ERROR")

                if success
                  # Show key data including timeframes for market data
                  summary = if tool_result["data"] || tool_result[:data]
                              data = tool_result["data"] || tool_result[:data]

                              # Debug: Log what we're getting
                              @logger.debug "   Processing tool data: keys=#{data.is_a?(Hash) ? data.keys.inspect : "not a hash"}, has_timeframes=#{data.is_a?(Hash) && (data[:timeframes] || data["timeframes"])}, data_type=#{data.class}, data_empty=#{data.is_a?(Hash) && data.empty?}"

                              # If data is empty or not a hash, something went wrong - use original tool_result
                              if !data.is_a?(Hash) || data.empty?
                                @logger.warn "   ⚠️ Tool data is empty or invalid, using original tool_result"
                                # Return the original tool_result as-is so LLM can see what was stored
                                tool_result.to_json
                              else
                                # Normalize keys to handle both symbol and string keys from JSON
                                normalized_data = {}
                                data.each do |k, v|
                                  key = k.is_a?(Symbol) ? k : k.to_sym
                                  normalized_data[key] = v
                                end

                                # For fetch_market_data, include timeframes and recommendation
                                if normalized_data[:timeframes]
                                  # Keep full timeframes data - don't summarize too much
                                  tf_data = normalized_data[:timeframes]

                                  # Include full recommendation details so LLM can see it
                                  rec = normalized_data[:recommendation]

                                  result_hash = {
                                    success: true,
                                    status: "SUCCESS",
                                    symbol: normalized_data[:symbol],
                                    timeframes: tf_data,
                                    recommendation: rec,
                                    confidence: normalized_data[:confidence],
                                    has_data: true,
                                    stop_calling_tools: true,
                                    message: "✅ COMPLETE DATA RECEIVED! Tool executed SUCCESSFULLY. You now have: symbol, timeframes (15m, 5m, 1m), indicators (EMA, trend), and recommendation (action, strike, premium, targets). STOP calling tools immediately and provide your final analysis with the recommendation details."
                                  }.compact
                                  result_hash.to_json
                                else
                                  # For other tools, pass through normalized data
                                  {
                                    success: true,
                                    status: status,
                                    message: "Tool executed SUCCESSFULLY. Data retrieved successfully.",
                                    data: normalized_data
                                  }.to_json
                                end
                              end
                            else
                              {
                                success: true,
                                status: status,
                                message: "Tool executed SUCCESSFULLY."
                              }.to_json
                            end
                  content = summary
                else
                  # Keep error messages concise
                  error_msg = tool_result["error"] || tool_result[:error] || "Error"
                  content = {
                    success: false,
                    status: status,
                    error: error_msg,
                    message: "Tool execution FAILED."
                  }.to_json
                end
              end
            rescue JSON::ParserError
              # Keep original if not JSON
            end
          end

          messages << {
            role: msg[:role],
            content: content,
            name: msg[:name],
            tool_calls: msg[:tool_calls]
          }
        end

        messages
      end

      def build_system_prompt
        tools_list = @tool_registry.to_json_schema.map do |t|
          params = t[:function][:parameters]&.dig(:properties) || {}
          params_desc = params.map { |k, v| "#{k}: #{v[:description] || v[:type]}" }.join(", ")
          "- #{t[:function][:name]}: #{t[:function][:description]}#{params_desc.empty? ? "" : " (params: #{params_desc})"}"
        end.join("\n")

        <<~PROMPT
          You are a technical analysis assistant for Indian markets (NIFTY/options).

          Available tools:
          #{tools_list}

          🎯 DYNAMIC ITERATION CONTROL - YOU DECIDE EVERYTHING:

          You have FULL CONTROL over:
          1. **When to continue** - Call tools if you need more data
          2. **When to stop** - Provide final answer when you have enough information
          3. **Which tools to use** - Choose based on what data you need
          4. **How many iterations** - Continue until you're satisfied (soft limit: #{LoopState::MAX_STEPS} steps)

          WORKFLOW - OBSERVE → ACT → PLAN → DECIDE:

          **Step 1: OBSERVE**
          - What data do you have from the user's query?
          - What data do you need to answer the question?

          **Step 2: ACT** (if needed)
          - If analyzing a symbol (NIFTY, SENSEX, etc.), call `fetch_market_data` ONCE with the symbol
          - **CRITICAL: After `fetch_market_data` returns, check if it contains:**
            * `timeframes` (15m, 5m, 1m data)
            * `recommendation` (action, trend, strike, premium, targets)
            * If YES → You have COMPLETE data → STOP calling tools → Provide final analysis
            * If NO → Call additional tools only if truly needed
          - Call ONE tool at a time, wait for results
          - Use validation tools ONLY if you have the required data

          **Step 3: PLAN**
          - After `fetch_market_data` result, IMMEDIATELY check: Do I have recommendation?
          - If recommendation exists → You're DONE with tools → Provide final answer NOW
          - If no recommendation → Decide: call another tool OR provide analysis with available data
          - **DO NOT call `fetch_market_data` again if you already called it - the data is cached and will return the same result**

          **Step 4: DECIDE** (Self-termination)
          - **STOP IMMEDIATELY** when `fetch_market_data` returns data with `recommendation` field
          - STOP when you have: market data + indicators + recommendation
          - STOP when confidence is high (>0.7) and all required data is collected
          - STOP when you've provided a comprehensive answer
          - **NEVER call the same tool twice** - if you see a cached result, it means you already have that data

          CRITICAL RULES:
          - **Call `fetch_market_data` EXACTLY ONCE per symbol** - never call it again
          - **When tool result shows `stop_calling_tools: true` or `message` says "STOP calling tools" → IMMEDIATELY provide final answer**
          - **If you see `recommendation` in tool result → You have everything → STOP → Provide analysis**
          - Call tools ONE BY ONE - sequential execution reduces model load
          - Wait for tool results before calling the next tool
          - If a tool fails, try a different approach or explain what's needed
          - **If you call a tool and get the same result (cached), it means you already have that data - use it and provide analysis**

          TOOL SEQUENCE EXAMPLES:

          Example 1: "Analyze SENSEX for intraday trading"
          → Step 1: Call `fetch_market_data` with symbol="SENSEX" (ONCE ONLY)
          → Step 2: Tool returns: {symbol: "SENSEX", timeframes: {...}, recommendation: {action: "buy_pe", trend: "BEARISH", strike: 85400, premium: 170, ...}, stop_calling_tools: true}
          → Step 3: See `recommendation` and `stop_calling_tools: true` → IMMEDIATELY provide final answer
          → Step 4: DO NOT call any more tools - you have everything you need!

          Example 2: "Analyze SENSEX" (second call in same session)
          → Step 1: Call `fetch_market_data` with symbol="SENSEX"
          → Step 2: Get cached result (same as before) with `stop_calling_tools: true`
          → Step 3: IMMEDIATELY provide analysis - do NOT call fetch_market_data again!

          Example 2: "Check if NIFTY signals are aligned"
          → Step 1: Call `fetch_market_data` with symbol="NIFTY" (to get timeframe data)
          → Step 2: Call `validate_signal_alignment` with the timeframe data from step 1
          → Step 3: Provide final answer with alignment analysis

          STOP CONDITIONS (Auto-terminate when):
          - You have market data + indicators + analysis
          - You've provided a comprehensive answer to the user's query
          - Confidence is sufficient and all required data is collected
          - You explicitly state "final answer", "complete", "analysis done", etc.

          CONTINUE CONDITIONS:
          - Missing market data → call `fetch_market_data`
          - Need to validate signals → call `validate_signal_alignment` (with data from fetch_market_data)
          - Need to check market conditions → call `check_market_conditions` (with data from fetch_market_data)

          TOOL CALLING:
          - Use the tool_calls API parameter in your response
          - Call ONLY ONE tool per response
          - Include proper arguments for each tool
          - After tool results, analyze them and decide: continue or final answer

          RESPONSE FORMAT:
          - If calling a tool: Use tool_calls API
          - If providing final answer: Write comprehensive analysis without tool calls
          - Explicitly state when you're done: "Final answer:", "Analysis complete:", "Here's my recommendation:"

          Current mode: #{@tool_registry.mode}
          #{@tool_registry.mode == :alert ? "⚠️ Execution tools are DISABLED - analysis only" : "⚠️ Execution tools are ENABLED - use with extreme caution"}
        PROMPT
      end

      def execute_tool(tool_name, arguments)
        @logger.info "⚙️  Executing tool: #{tool_name}"
        @logger.debug "   Arguments: #{arguments.inspect}"

        start_time = Time.now
        result = @tool_registry.execute(tool_name.to_sym, arguments)
        elapsed = Time.now - start_time

        if result
          if result[:success]
            @logger.info "✅ Tool '#{tool_name}' completed in #{elapsed.round(2)}s"
          else
            @logger.error "❌ Tool '#{tool_name}' failed in #{elapsed.round(2)}s: #{result[:error]}"
          end
        else
          @logger.warn "⚠️  Tool '#{tool_name}' returned nil"
        end

        result
      end

      def build_final_result(stop_reason)
        @logger.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        @logger.info "🏁 Agent loop completed"
        @logger.info "   Stop reason: #{stop_reason}"
        @logger.info "   Total steps: #{@state.step_count}"
        @logger.info "   Tools used: #{@state.memory.map { |m| m[:tool] }.join(", ")}"
        @logger.info "   Successful tools: #{@state.memory.count { |m| m[:result] && m[:result][:success] }}"
        @logger.info "   Failed tools: #{@state.memory.count { |m| m[:result] && !m[:result][:success] }}"

        final_answer = extract_final_answer
        @logger.info "   Final answer length: #{final_answer&.length || 0} chars"

        {
          success: true,
          answer: final_answer,
          steps: @state.step_count,
          memory: @state.memory,
          stop_reason: stop_reason,
          conversation: @state.conversation_history
        }
      end

      def extract_final_answer
        # Extract final answer from conversation history
        # Look for the last assistant message that is NOT a tool call
        assistant_messages = @state.conversation_history.select { |m| m[:role] == "assistant" }

        # Find the last assistant message that is a real answer (not a tool call)
        last_answer = assistant_messages.reverse.find do |msg|
          content = msg[:content] || ""
          # Skip if it's empty
          next false if content.strip.empty?

          # Skip if it's a tool call JSON
          next false if content.match?(/^\s*\{[\s\n]*"name"\s*:/) # {"name": ...}
          next false if content.match?(/^\s*\{[\s\n]*"tool_calls"/) # {"tool_calls": ...}
          next false if content.match?(/^\s*\{[\s\n]*"function"/) # {"function": ...}
          next false if content.match?(/```json\s*\{[\s\n]*"name"/) # ```json {"name": ...}

          # Skip if it's just describing a tool
          next false if content.match?(/would recommend calling|I should call|need to call|I will call/i)

          # Skip if it's very short (likely just a tool call description)
          next false if content.length < 30 && content.match?(/call|use|execute/i)

          # This looks like a real answer
          true
        end

        if last_answer && last_answer[:content]
          content = last_answer[:content]
          # Return it if it looks substantial
          if content.length > 50 || content.match?(/analysis|conclusion|summary|recommendation|based on|according to/i)
            return content
          end
        end

        # If no real answer found, check if we have tool results that we can summarize
        if @state.memory.any?
          tool_summary = @state.memory.map do |m|
            "#{m[:tool]}: #{m.dig(:result, :success) ? "success" : "error"}"
          end.join(", ")
          return "Agent executed tools (#{tool_summary}) but didn't provide a final analysis. Tool results are available in the conversation history."
        end

        # Final fallback
        "No final answer provided. The agent made tool calls but didn't provide a complete analysis."
      end
    end
  end
end
