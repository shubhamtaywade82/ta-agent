# frozen_string_literal: true

require_relative "market_data_tools"
require_relative "indicator_tools"
require_relative "structure_tools"
require_relative "../agent/context_contracts"

# TaAgent::Tools::TimeframeContextBuilders
#
# Category 4: Timeframe Context Builders (CRITICAL)
#
# Responsibilities:
# - Aggregate outputs from tools 1-3
# - Apply hard rules
# - Produce final JSON blocks for LLM
#
# Design:
# - Each builder pulls from market data + indicators + structure tools
# - Applies permission gates
# - Output: Structured context ready for LLM
module TaAgent
  module Tools
    module TimeframeContextBuilders
      # Build 15m context
      # @param client [TaAgent::DhanHQ::Client] DhanHQ client
      # @param symbol [String] Symbol name
      # @return [Hash] Complete 15m context block
      def self.build_tf_context_15m(client, symbol:)
        # Step 1: Fetch raw data
        ohlcv = MarketDataTools.fetch_ohlc(client, symbol: symbol, timeframe: "15", days: 30)
        return { error: "Failed to fetch 15m data" } if ohlcv[:error]

        # Step 2: Calculate indicators
        ema_9 = IndicatorTools.calculate_ema(ohlcv[:close], 9)
        ema_21 = IndicatorTools.calculate_ema(ohlcv[:close], 21)
        adx = IndicatorTools.calculate_adx(ohlcv[:high], ohlcv[:low], ohlcv[:close])
        atr = IndicatorTools.calculate_atr(ohlcv[:high], ohlcv[:low], ohlcv[:close])
        vwap = IndicatorTools.calculate_vwap(ohlcv)

        # Step 3: Detect structure and behavior
        trend = StructureTools.detect_trend(
          adx: adx[:adx],
          ema_9: ema_9[:latest],
          ema_21: ema_21[:latest]
        )
        structure = StructureTools.detect_structure(ohlcv[:high], ohlcv[:low])
        volatility = StructureTools.detect_volatility_state([atr[:atr]].compact)
        vwap_relation = StructureTools.detect_vwap_relation(
          ohlcv[:close].last,
          vwap[:vwap]
        )

        # Step 4: Build structured context using contract
        raw_context = {
          trend: trend[:direction],
          ema_9: ema_9[:latest],
          ema_21: ema_21[:latest],
          status: "complete"
        }

        indicators = {
          adx: adx[:adx],
          di_diff: nil, # TODO: Calculate DI difference
          last_bos: structure[:last_bos],
          structure_age: structure[:structure_age_candles],
          atr_trend: volatility[:atr_trend],
          range_state: volatility[:range_state],
          vwap_position: vwap_relation[:state],
          vwap_distance_pct: vwap_relation[:distance_pct]
        }

        ContextContracts::TF15MContext.build(raw_context, indicators: indicators)
      end

      # Build 5m context
      # @param client [TaAgent::DhanHQ::Client] DhanHQ client
      # @param symbol [String] Symbol name
      # @return [Hash] Complete 5m context block
      def self.build_tf_context_5m(client, symbol:)
        # Step 1: Fetch raw data
        ohlcv = MarketDataTools.fetch_ohlc(client, symbol: symbol, timeframe: "5", days: 7)
        return { error: "Failed to fetch 5m data" } if ohlcv[:error]

        # Step 2: Calculate indicators
        ema_9 = IndicatorTools.calculate_ema(ohlcv[:close], 9)
        vwap = IndicatorTools.calculate_vwap(ohlcv)

        # Step 3: Detect structure
        vwap_relation = StructureTools.detect_vwap_relation(
          ohlcv[:close].last,
          vwap[:vwap]
        )

        # Step 4: Build structured context
        raw_context = {
          setup_type: "trend_continuation", # TODO: Detect actual setup type
          ema_9: ema_9[:latest],
          latest_close: ohlcv[:close].last,
          status: "complete"
        }

        indicators = {
          setup_type: "trend_continuation",
          rsi: nil, # TODO: Calculate RSI
          rsi_trend: "flat",
          macd_state: "neutral",
          upper_wick_pct: 0.0, # TODO: Calculate from candles
          body_pct: 0.0, # TODO: Calculate from candles
          vwap_state: vwap_relation[:state],
          vwap_retests: 0, # TODO: Count retests
          weak_close: false, # TODO: Detect weak close
          failed_retest: false, # TODO: Detect failed retest
          momentum_alignment: true # TODO: Compare with 15m
        }

        ContextContracts::TF5MContext.build(raw_context, indicators: indicators)
      end

      # Build 1m context
      # @param client [TaAgent::DhanHQ::Client] DhanHQ client
      # @param symbol [String] Symbol name
      # @return [Hash] Complete 1m context block
      def self.build_tf_context_1m(client, symbol:)
        # Step 1: Fetch raw data
        ohlcv = MarketDataTools.fetch_ohlc(client, symbol: symbol, timeframe: "1", days: 1)
        return { error: "Failed to fetch 1m data" } if ohlcv[:error]

        # Step 2: Calculate indicators
        atr = IndicatorTools.calculate_atr(ohlcv[:high], ohlcv[:low], ohlcv[:close])

        # Step 3: Detect structure
        # TODO: Detect momentum ignition, micro structure

        # Step 4: Build structured context
        raw_context = {
          entry_signal: "confirmed", # TODO: Detect actual trigger
          trigger_reason: "momentum_burst", # TODO: Detect actual type
          latest_close: ohlcv[:close].last,
          entry_zone: {
            from: (ohlcv[:close].last * 0.98).round(2),
            to: (ohlcv[:close].last * 1.02).round(2)
          },
          status: "complete"
        }

        indicators = {
          trigger_type: "momentum_burst",
          range_expansion_pct: 0.0, # TODO: Calculate
          atr_spike: false, # TODO: Detect
          consecutive_strong_closes: 0, # TODO: Count
          higher_low: false, # TODO: Detect
          lower_wick_dominance: false, # TODO: Detect
          rr_estimate: 0.0, # TODO: Calculate
          forming: false
        }

        ContextContracts::TF1MContext.build(raw_context, indicators: indicators)
      end
    end
  end
end

