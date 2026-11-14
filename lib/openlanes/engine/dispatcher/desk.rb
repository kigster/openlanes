# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # What the tick's steps share: the jobs running now ({Registers}), what
      # each agent has already done on each plan ({Rounds}), the plans nothing
      # may touch ({Fences}, {Budgeting}), and the collaborators every step
      # reads or writes through. One desk per run, built by the {Dispatcher}
      # and handed to each {Step}; its public methods are the steps' contract.
      class Desk
        extend Forwardable
        include Deps["clock"]

        # The keywords {Dispatcher} and the suite have always passed still
        # build a desk: they are gathered into a {Setup} here.
        def self.new(setup = nil, clock: nil, **)
          clocked = clock ? { clock: } : {}
          super(setup || Setup.new(**), **clocked)
        end

        # @param setup [Setup] the run this desk serves
        # @param deps [Hash] `clock:` [#now, #sleep], from the container unless given
        def initialize(setup, **deps)
          super(**deps)
          @setup = setup
          @idle = @wake = false
          @registers = Registers.fresh
          @extensions = setup.extensions || Extensions.new(stay: setup.stay)
          @feed = EventJournal::Feed.new(setup.journal)
          @guards = Guards.for(setup.runner, clock)
          build_collaborators
        end

        attr_reader :clock, :feed, :extensions

        # Mail over Redis, the drain of answered blocks (set once the
        # dispatcher has built it, since it needs {#untouchable}), whether the
        # last dispatch found nothing to start, and whether a rescan was asked for.
        attr_accessor :mail, :unblocking, :idle, :wake

        def_delegators :@setup, :runner
        def_delegators :@guards, *Guards.members
        def_delegators :@registers, *Registers.members
        def_delegators :@profiles, :adapter_of, :rounds_for, :rounds_allowed, :model_for, :profile_fields, :models
        def_delegators :@budgeting, :budget_refusal, :announce_budget, :budget_holds
        def_delegators :@fences, :untouchable, :verifying_now, :arbitrating_now, :waiting
        def_delegators :@fences, :locked_elsewhere?, :held_outside?
        def_delegators :@rounds, :resume, :remember, :forget_round
        def_delegators :@round_records, :harness_resume, :last_line, :write_interrupted, :stage!
        def_delegators :@lookups, :in_run?, :read_ledger, :verifier?, :assessor?, :fresh, :fresh_by
        def_delegators :@events, :adapter_for, :event_fields, :adapter_name

        # The setup's own fields: the state file (nil under a dry run),
        # `--rounds`, and whether this run idles past its fixed points.
        def state_file = @setup.state
        def rounds_cap = @setup.rounds
        def stay? = @setup.stay

        # @return [OpenLanes::Engine::Rebase] stopped rebases and their failures
        def rebases = @rebases ||= Rebase.new(agents: runner.agents, executor: runner.executor)

        # Rescan on the next tick: a command was applied, and what it changed
        # should be acted on now.
        def wake! = @wake = true

        # The job's plan's ordinal; whether nothing is running, draining or
        # being thrown back; a finish ({Finishes#finish}); a job by its
        # `"<ordinal>/<agent>"` key.
        def plan_of(job) = job.task.subject.feature.ordinal.to_s
        def quiet? = running.empty? && unblocking.empty? && discarding.empty?
        def finish(subject, kind) = finishes.finish(subject, kind)
        def job(key) = running.find { |j| j.key == key }

        # One control word into one running agent's control file.
        #
        # @return [Boolean] whether there was a running agent to tell
        def signal(key, word)
          control = job(key)&.handle&.control or return false
          Execution::Control.write(control, word)
          true
        end

        private

        def build_collaborators
          @profiles = Profiles.new(runner:, rounds_cap:, extensions:)
          @budgeting = Budgeting.new(runner:, budget: @setup.budget || Engine.budget_for(runner))
          @fences = Fences.new(self)
          @rounds = Rounds.new(@registers)
          @round_records = RoundRecords.new(records)
          @lookups = Lookups.new(runner)
          @events = Events.new(self)
        end
      end
    end
  end
end
