# frozen_string_literal: true

module OpenLanes
  module Live
    module EventBus
      # One {Base#transaction} block's writes: {#append} for the streams, and
      # the store's other writes ({Store::WRITES}) beside them, so a site that
      # sets a key and appends an entry together keeps doing both atomically.
      class Transaction
        # @param raw [OpenLanes::Live::Store::Transaction]
        def initialize(raw)
          @raw = raw
        end

        # @param stream [String]
        # @param fields [Hash]
        # @param maxlen [Integer, nil]
        # @return [nil]
        def append(stream, fields, maxlen: nil) = @raw.xadd(stream, fields, maxlen:)

        (Store::WRITES - %i[xadd]).each do |name|
          define_method(name) { |*args, **kwargs| @raw.public_send(name, *args, **kwargs) }
        end
      end
    end
  end
end
