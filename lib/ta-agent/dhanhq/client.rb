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
        "MIDCPNIFTY" => "IDX_I",
        "SENSEX" => "IDX_I"
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

        # Fetch intraday data using instrument.intraday method
        data = instrument.intraday(
          from_date: from,
          to_date: to,
          interval: interval
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
      # @param expiry [Date, String, nil] Expiry date (optional, defaults to nearest expiry)
      # @return [Hash] Option chain data with :strikes, :expiry_dates, :symbol
      def fetch_option_chain(symbol:, expiry: nil)
        instrument = find_instrument(symbol)
        raise DhanHQError, "Instrument not found for symbol: #{symbol}" unless instrument

        # Get available expiries
        expiries = instrument.expiry_list

        # If no expiry specified, use the nearest one (first in list)
        expiry_date = if expiry
                        normalize_date(expiry)
                      elsif expiries&.any?
                        expiries.first
                      else
                        nil
                      end

        # Fetch option chain for the specified expiry
        chain_data = if expiry_date
                       instrument.option_chain(expiry: expiry_date)
                     else
                       { strikes: [], expiries: [] }
                     end

        # Transform to expected format
        {
          symbol: symbol,
          strikes: chain_data[:strikes] || chain_data[:strike] || [],
          expiry_dates: expiries || [],
          selected_expiry: expiry_date
        }
      rescue ::DhanHQ::Error => e
        raise DhanHQError, "DhanHQ API error for #{symbol}: #{e.message}"
      rescue StandardError => e
        raise DhanHQError, "Failed to fetch option chain for #{symbol}: #{e.message}"
      end

      # Fetch current market data
      # @param symbol [String] Symbol name
      # @return [Hash] Current market data with :last_price, :open, :high, :low, :close, :volume, :change, :change_percent
      def fetch_quote(symbol:)
        instrument = find_instrument(symbol)
        raise DhanHQError, "Instrument not found for symbol: #{symbol}" unless instrument

        # Fetch LTP (Last Traded Price)
        ltp_data = instrument.ltp

        # Fetch OHLC data
        ohlc_data = instrument.ohlc

        # Fetch full quote (if needed for depth)
        quote_data = instrument.quote

        # Extract relevant data
        last_price = ltp_data[:ltp] || ltp_data[:last_price] || quote_data[:ltp] || quote_data[:last_price]
        open_price = ohlc_data[:open] || quote_data[:open]
        high_price = ohlc_data[:high] || quote_data[:high]
        low_price = ohlc_data[:low] || quote_data[:low]
        close_price = ohlc_data[:close] || quote_data[:close] || quote_data[:previous_close]
        volume = ohlc_data[:volume] || quote_data[:volume]

        # Calculate change
        change = last_price && close_price ? last_price - close_price : nil
        change_percent = change && close_price && close_price != 0 ? (change / close_price * 100).round(2) : nil

        {
          symbol: symbol,
          last_price: last_price,
          open: open_price,
          high: high_price,
          low: low_price,
          close: close_price,
          volume: volume,
          change: change,
          change_percent: change_percent
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
        symbol_up = symbol.upcase

        # Try common segments first for known indices
        if SYMBOL_SEGMENTS.key?(symbol_up)
          segment = SYMBOL_SEGMENTS[symbol_up]
          ::DhanHQ::Models::Instrument.find(segment, symbol_up)
        else
          # Try common segments for unknown symbols
          # First try IDX_I (indices), then NSE_EQ (equity)
          %w[IDX_I NSE_EQ].each do |segment|
            instrument = ::DhanHQ::Models::Instrument.find(segment, symbol_up)
            return instrument if instrument
          rescue StandardError
            # Continue to next segment
            next
          end

          # If not found, try find_anywhere if available
          if ::DhanHQ::Models::Instrument.respond_to?(:find_anywhere)
            ::DhanHQ::Models::Instrument.find_anywhere(symbol_up)
          else
            nil
          end
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
        return [] if data.nil?

        # Handle array of hashes format (if API returns directly)
        if data.is_a?(Array) && data.first.is_a?(Hash)
          return data.map do |item|
            {
              timestamp: normalize_timestamp(item[:timestamp] || item[:time] || item[:date]),
              open: item[:open].to_f,
              high: item[:high].to_f,
              low: item[:low].to_f,
              close: item[:close].to_f,
              volume: (item[:volume] || 0).to_i
            }
          end
        end

        # Handle hash with arrays format: {open: [...], high: [...], close: [...], ...}
        return [] unless data.is_a?(Hash)

        timestamps = data[:timestamp] || data[:time] || []
        opens = data[:open] || []
        highs = data[:high] || []
        lows = data[:low] || []
        closes = data[:close] || []
        volumes = data[:volume] || []

        result = []
        length = [timestamps.length, opens.length, highs.length, lows.length, closes.length].min

        (0...length).each do |i|
          result << {
            timestamp: normalize_timestamp(timestamps[i]),
            open: opens[i].to_f,
            high: highs[i].to_f,
            low: lows[i].to_f,
            close: closes[i].to_f,
            volume: (volumes[i] || 0).to_i
          }
        end

        result
      end

      def normalize_timestamp(timestamp)
        return Time.now.to_i if timestamp.nil?

        case timestamp
        when Integer
          # If it's already a Unix timestamp, return as is
          timestamp
        when String
          # Try parsing as ISO8601 or date string
          Time.parse(timestamp).to_i
        when Time
          timestamp.to_i
        when Date
          timestamp.to_time.to_i
        else
          Time.now.to_i
        end
      end
    end
  end
end
