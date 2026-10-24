# frozen_string_literal: true

module OpenLanes
  # The durable record of runs (plan 020.01): an opt-in, append-only JSONL
  # log of run, agent, block/answer and PR events, kept outside the repo and
  # outside Redis, and the aggregates read back from it.
  #
  # Redis stays the live view. This is what is left after a run ends or
  # Redis is flushed. It holds ids, timestamps, adapter, model and usage,
  # and no prompt, transcript, answer or code (see {Event::PAYLOAD_KEYS}).
  module Events
    module_function

    # @param root [String] the project root
    # @param config [OpenLanes::Config]
    # @param node [OpenLanes::Live::Node, nil] nil reads this machine's
    # @param env [Hash]
    # @return [OpenLanes::Events::Sink, OpenLanes::Events::NullSink] the null
    #   sink unless `.openlanes.yml` says `events: { enabled: true }`
    def emitter(root:, config: Config.current, node: nil, env: ENV)
      return NullSink.new unless config.events_enabled

      node ||= Live::Node.current(root:)
      Sink.new(dir: Location.dir(root:, config:, env:),
        node: node.id,
        checkout: node.checkout_id,
        project: config.project || File.basename(root))
    end

    # @param root [String]
    # @param config [OpenLanes::Config]
    # @param env [Hash]
    # @return [String] where the log is, or would be
    def dir(root:, config: Config.current, env: ENV) = Location.dir(root:, config:, env:)

    # @param dir [String]
    # @return [OpenLanes::Events::Log]
    def log(dir) = Log.new(dir:)

    # @param events [Array<OpenLanes::Events::Event>]
    # @param skipped_lines [Integer]
    # @return [OpenLanes::Events::Report::Result]
    def report(events, skipped_lines: 0) = Report.new(events, skipped_lines:).call
  end
end
