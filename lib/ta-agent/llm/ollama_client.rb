# frozen_string_literal: true

# TaAgent::LLM::OllamaClient
#
# Ollama API client using Faraday.
#
# Responsibilities:
# - Connect to Ollama /api/chat endpoint
# - Handle timeouts gracefully
# - Return nil/error if unreachable (non-fatal)
#
# Design:
# - Uses Faraday for HTTP
# - Timeout-safe (5-10s default)
# - Optional - gem works without it
# - Raises TaAgent::OllamaError (non-fatal, can continue)
module TaAgent
  module LLM
    class OllamaClient
      # TODO: Implement Ollama client
      # - Faraday connection to OLLAMA_HOST_URL
      # - POST /api/chat with model and messages
      # - Handle timeouts and errors gracefully
      # - Return parsed response or nil
    end
  end
end

