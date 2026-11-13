# frozen_string_literal: true

module OpenLanes
  module Engine
    # The dispatcher's question of the dollar cap: may another round start on
    # this plan? A plan that has spent `budget.plan_usd` or more gets no new
    # agent; a round already running finishes.
    #
    # The log is reread at most once per {TTL}, because {Dispatcher} asks for
    # every plan on every tick and a log is many files. With no cap nothing
    # is read at all.
    class Budget
      # Seconds a read of the event log is reused.
      TTL = 5

      # @param cap [#call] the cap in dollars, or nil for none
      # @param events [#call] the event log's events
      # @param clock [#now]
      def initialize(cap: -> { Events::PlanSpend.cap_for(Config.current) }, events: -> { [] }, clock: Time)
        @cap = cap
        @events = events
        @clock = clock
        @read_at = nil
      end

      # The budget a runner's own event sink reads back: nothing to read for
      # a run whose log is off.
      #
      # @param runner [OpenLanes::Engine::Runner]
      # @return [OpenLanes::Engine::Budget]
      def self.for(runner)
        sink = runner.events
        dir = sink.enabled? ? sink.dir : nil
        new(events: -> { read(dir) })
      end

      # The budget of the project the process is in, read from its event log
      # wherever `.openlanes.yml` puts it, enabled or not: a log written by an
      # earlier run still says what was spent.
      #
      # @param root [String, nil] nil takes {Project.root}
      # @return [OpenLanes::Engine::Budget]
      def self.local(root: nil)
        new(events: -> { read(Events.dir(root: root || Project.root || Dir.pwd)) })
      end

      # The one reader of an event log for a budget, so the board and the cap
      # cannot read the same directory two ways (F203 on PR 211).
      #
      # @param dir [String, nil] the log's directory; nil for a run whose log is off
      # @return [Array<OpenLanes::Events::Event>]
      def self.read(dir) = dir && Dir.exist?(dir) ? Events.log(dir).events : []

      # @param ordinal [String, #to_s]
      # @return [OpenLanes::Events::PlanSpend]
      def spend(ordinal) = Events::PlanSpend.for(ordinal, events, cap: @cap.call)

      # @param ordinal [String, #to_s]
      # @return [String, nil] `over budget: $X of $Y`, or nil when it may run
      def refusal(ordinal)
        return nil if @cap.call.nil?

        spend(ordinal).reason
      end

      private

      # @return [Array<OpenLanes::Events::Event>]
      def events
        now = @clock.now
        if @read_at.nil? || now - @read_at >= TTL
          @cached = @events.call
          @read_at = now
        end
        @cached
      end
    end
  end
end
