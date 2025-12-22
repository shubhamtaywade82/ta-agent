# frozen_string_literal: true

require_relative "../dhanhq/client"
require_relative "../ta/indicators/ema"

# TaAgent::Agent::Runner
#
# Core agent execution logic.
#
# Pseudocode flow:
#   build_15m_context
#   abort_if_blocked
#
#   build_5m_context
#   abort_if_blocked
#
#   build_option_chain_context
#   abort_if_empty
#
#   build_1m_context
#
#   if llm_enabled?
#     llm_decision
#   else
#     deterministic_decision
#   end
#
#   format_output
#
# Design:
# - Orchestrates all TA pipelines
# - Applies gates (kill switches)
# - Optionally calls LLM
# - Returns structured result
module TaAgent
  module Agent
    class Runner
      attr_reader :symbol, :config, :dhanhq_client, :result

      def initialize(symbol:, config: nil)
        @symbol = symbol.upcase
        @config = config || TaAgent::Config.instance
        @dhanhq_client = DhanHQ::Client.new(
          client_id: @config.dhanhq_client_id,
          access_token: @config.dhanhq_access_token
        )
        @result = {
          symbol: @symbol,
          timestamp: Time.now,
          timeframes: {},
          options: nil,
          recommendation: nil,
          confidence: 0.0,
          errors: []
        }
      end

      def run
        build_15m_context
        build_5m_context
        build_1m_context
        build_option_chain_context

        make_decision

        @result
      rescue TaAgent::DhanHQError => e
        @result[:errors] << e.message
        @result
      rescue StandardError => e
        @result[:errors] << "Unexpected error: #{e.message}"
        @result
      end

      private

      def build_15m_context
        begin
          # Fetch last 30 days of 15m data
          to_date = Date.today
          from_date = to_date - 30

          ohlcv_data = @dhanhq_client.fetch_ohlcv(
            symbol: @symbol,
            timeframe: "15",
            from_date: from_date,
            to_date: to_date
          )

          if ohlcv_data.empty?
            @result[:timeframes][:tf_15m] = {
              trend: "unknown",
              status: "no_data",
              error: "No data available"
            }
            return
          end

          # Extract closing prices
          closes = ohlcv_data.map { |d| d[:close] }

          # Calculate EMAs
          ema_9 = TA::Indicators::EMA.latest(closes, 9)
          ema_21 = TA::Indicators::EMA.latest(closes, 21)

          # Determine trend
          trend = if ema_9 && ema_21
                    if ema_9 > ema_21
                      "bullish"
                    elsif ema_9 < ema_21
                      "bearish"
                    else
                      "neutral"
                    end
                  else
                    "neutral"
                  end

          @result[:timeframes][:tf_15m] = {
            trend: trend,
            ema_9: ema_9,
            ema_21: ema_21,
            data_points: ohlcv_data.length,
            latest_close: closes.last,
            status: "complete"
          }
        rescue TaAgent::DhanHQError => e
          @result[:timeframes][:tf_15m] = {
            trend: "unknown",
            status: "error",
            error: e.message
          }
          @result[:errors] << "15m context: #{e.message}"
        end
      end

      def build_5m_context
        begin
          # Fetch last 7 days of 5m data
          to_date = Date.today
          from_date = to_date - 7

          ohlcv_data = @dhanhq_client.fetch_ohlcv(
            symbol: @symbol,
            timeframe: "5",
            from_date: from_date,
            to_date: to_date
          )

          if ohlcv_data.empty?
            @result[:timeframes][:tf_5m] = {
              setup: "unknown",
              status: "no_data"
            }
            return
          end

          closes = ohlcv_data.map { |d| d[:close] }
          ema_9 = TA::Indicators::EMA.latest(closes, 9)

          @result[:timeframes][:tf_5m] = {
            setup: "analyzed",
            ema_9: ema_9,
            data_points: ohlcv_data.length,
            latest_close: closes.last,
            status: "complete"
          }
        rescue TaAgent::DhanHQError => e
          @result[:timeframes][:tf_5m] = {
            setup: "unknown",
            status: "error",
            error: e.message
          }
          @result[:errors] << "5m context: #{e.message}"
        end
      end

      def build_1m_context
        begin
          # Fetch last 1 day of 1m data
          to_date = Date.today
          from_date = to_date - 1

          ohlcv_data = @dhanhq_client.fetch_ohlcv(
            symbol: @symbol,
            timeframe: "1",
            from_date: from_date,
            to_date: to_date
          )

          if ohlcv_data.empty?
            @result[:timeframes][:tf_1m] = {
              trigger: "unknown",
              status: "no_data"
            }
            return
          end

          closes = ohlcv_data.map { |d| d[:close] }

          @result[:timeframes][:tf_1m] = {
            trigger: "analyzed",
            data_points: ohlcv_data.length,
            latest_close: closes.last,
            status: "complete"
          }
        rescue TaAgent::DhanHQError => e
          @result[:timeframes][:tf_1m] = {
            trigger: "unknown",
            status: "error",
            error: e.message
          }
          @result[:errors] << "1m context: #{e.message}"
        end
      end

      def build_option_chain_context
        # TODO: Fetch option chain and score strikes
        @result[:options] = {
          strikes: [],
          best_strike: nil,
          status: "pending"
        }
      end

      def make_decision
        tf_15m = @result[:timeframes][:tf_15m]
        tf_5m = @result[:timeframes][:tf_5m]
        tf_1m = @result[:timeframes][:tf_1m]

        # Basic decision logic based on 15m trend
        if tf_15m[:status] == "complete" && tf_15m[:trend] == "bullish"
          confidence = 0.6
          if tf_5m[:status] == "complete" && tf_5m[:ema_9] && tf_15m[:ema_9]
            # 5m EMA above 15m EMA = stronger bullish
            if tf_5m[:ema_9] > tf_15m[:ema_9]
              confidence = 0.75
            end
          end

          @result[:recommendation] = {
            action: "buy",
            reason: "15m trend is bullish#{tf_15m[:ema_9] && tf_15m[:ema_21] ? " (EMA 9: #{tf_15m[:ema_9].round(2)} > EMA 21: #{tf_15m[:ema_21].round(2)})" : ""}",
            strike: nil,
            entry: tf_1m[:latest_close],
            stop_loss: nil,
            target: nil
          }
          @result[:confidence] = confidence
        elsif tf_15m[:status] == "complete" && tf_15m[:trend] == "bearish"
          @result[:recommendation] = {
            action: "sell",
            reason: "15m trend is bearish#{tf_15m[:ema_9] && tf_15m[:ema_21] ? " (EMA 9: #{tf_15m[:ema_9].round(2)} < EMA 21: #{tf_15m[:ema_21].round(2)})" : ""}",
            strike: nil,
            entry: tf_1m[:latest_close],
            stop_loss: nil,
            target: nil
          }
          @result[:confidence] = 0.6
        else
          @result[:recommendation] = {
            action: "wait",
            reason: tf_15m[:status] == "error" ? "Data fetch error" : "Trend unclear or neutral",
            strike: nil,
            entry: nil,
            stop_loss: nil,
            target: nil
          }
          @result[:confidence] = 0.0
        end
      end
    end
  end
end
