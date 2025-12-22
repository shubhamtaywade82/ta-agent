# frozen_string_literal: true

require "dhan_hq"
require "date"

# TaAgent::DhanHQ::Client
#
# Thin wrapper around dhanhq-client gem.
#
# Responsibilities:
# - Initialize dhanhq-client with credentials
# - Provide convenience methods for data fetching
# - Handle DhanHQ-specific errors
#
# Design:
# - Wraps dhanhq-client gem
# - Raises TaAgent::DhanHQError on API failures
# - Provides clean interface for TA agent
module TaAgent
  module DhanHQ
    class Client
      # Map common symbols to their exchange segments
      # NIFTY, BANKNIFTY are indices (IDX_I)
      # Most others are equity (NSE_EQ)
      SYMBOL_SEGMENTS = {
        "NIFTY" => "IDX_I",
        "BANKNIFTY" => "IDX_I",
        "FINNIFTY" => "IDX_I",
        "MIDCPNIFTY" => "IDX_I"
      }.freeze

      def initialize(client_id:, access_token:)
        @client_id = client_id
        @access_token = access_token
        initialize_dhanhq
      end

      # Fetch OHLCV data for a symbol and timeframe
      # @param symbol [String] Symbol name (e.g., "NIFTY", "BANKNIFTY")
      # @param timeframe [String] Timeframe in minutes (e.g., "15", "5", "1")
      # @param from_date [Date, String] Start date (YYYY-MM-DD)
      # @param to_date [Date, String] End date (YYYY-MM-DD)
      # @return [Array<Hash>] Array of OHLCV data points with keys: :timestamp, :open, :high, :low, :close, :volume
      def fetch_ohlcv(symbol:, timeframe:, from_date:, to_date:)
        instrument = find_instrument(symbol)
        raise DhanHQError, "Instrument not found for symbol: #{symbol}" unless instrument

        # Convert timeframe to DhanHQ format (e.g., "15" for 15 minutes)
        interval = timeframe.to_s

        # Normalize dates
        from = normalize_date(from_date)
        to = normalize_date(to_date)

        # Fetch intraday data
        data = ::DhanHQ::Models::HistoricalData.intraday(
          security_id: instrument.security_id,
          exchange_segment: instrument.exchange_segment,
          instrument: instrument.instrument,
          interval: interval,
          from_date: from,
          to_date: to
        )

        # Transform to array of hashes
        transform_ohlcv_data(data)
      rescue ::DhanHQ::Error => e
        raise DhanHQError, "DhanHQ API error for #{symbol}: #{e.message}"
      rescue StandardError => e
        raise DhanHQError, "Failed to fetch OHLCV data for #{symbol}: #{e.message}"
      end

      # Fetch option chain for a symbol
      # @param symbol [String] Symbol name
      # @return [Hash] Option chain data
      def fetch_option_chain(symbol:)
        instrument = find_instrument(symbol)
        raise DhanHQError, "Instrument not found for symbol: #{symbol}" unless instrument

        # TODO: Implement option chain fetch when DhanHQ API is available
        # For now, return empty structure
        {
          symbol: symbol,
          strikes: [],
          expiry_dates: []
        }
      rescue ::DhanHQ::Error => e
        raise DhanHQError, "DhanHQ API error for #{symbol}: #{e.message}"
      rescue StandardError => e
        raise DhanHQError, "Failed to fetch option chain for #{symbol}: #{e.message}"
      end

      # Fetch current market data
      # @param symbol [String] Symbol name
      # @return [Hash] Current market data
      def fetch_quote(symbol:)
        instrument = find_instrument(symbol)
        raise DhanHQError, "Instrument not found for symbol: #{symbol}" unless instrument

        # TODO: Implement quote fetch when DhanHQ API is available
        {
          symbol: symbol,
          last_price: nil,
          change: nil,
          change_percent: nil
        }
      rescue ::DhanHQ::Error => e
        raise DhanHQError, "DhanHQ API error for #{symbol}: #{e.message}"
      rescue StandardError => e
        raise DhanHQError, "Failed to fetch quote for #{symbol}: #{e.message}"
      end

      # Find instrument by symbol
      # @param symbol [String] Symbol name
      # @return [DhanHQ::Models::Instrument, nil] Instrument or nil if not found
      def find_instrument(symbol)
        # Try common segments first for known indices
        if SYMBOL_SEGMENTS.key?(symbol.upcase)
          segment = SYMBOL_SEGMENTS[symbol.upcase]
          ::DhanHQ::Models::Instrument.find(segment, symbol.upcase, exact_match: true)
        else
          # Search across all segments
          ::DhanHQ::Models::Instrument.find_anywhere(symbol.upcase, exact_match: true)
        end
      end

      private

      def initialize_dhanhq
        # Configure DhanHQ with credentials
        ::DhanHQ.configure do |config|
          config.client_id = @client_id
          config.access_token = @access_token
        end
      rescue StandardError => e
        raise DhanHQError, "Failed to initialize DhanHQ client: #{e.message}"
      end

      def normalize_date(date)
        case date
        when Date
          date.strftime("%Y-%m-%d")
        when String
          Date.parse(date).strftime("%Y-%m-%d")
        when Time
          date.to_date.strftime("%Y-%m-%d")
        else
          raise ArgumentError, "Invalid date format: #{date.class}"
        end
      end

      def transform_ohlcv_data(data)
        return [] unless data.is_a?(Hash)

        # DhanHQ returns data as arrays: {open: [...], high: [...], close: [...], ...}
        # Transform to array of hashes
        timestamps = data[:timestamp] || []
        opens = data[:open] || []
        highs = data[:high] || []
        lows = data[:low] || []
        closes = data[:close] || []
        volumes = data[:volume] || []

        result = []
        length = [timestamps.length, opens.length, highs.length, lows.length, closes.length].min

        (0...length).each do |i|
          result << {
            timestamp: Time.at(timestamps[i]).to_i,
            open: opens[i].to_f,
            high: highs[i].to_f,
            low: lows[i].to_f,
            close: closes[i].to_f,
            volume: volumes[i].to_i
          }
        end

        result
      end
    end
  end
end
