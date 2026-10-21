# frozen_string_literal: true

module OpenLanes
  module Live
    module EventBus
      # The production bus, over {Store}: Redis pub/sub and streams.
      class RedisBus < Base; end
    end
  end
end
