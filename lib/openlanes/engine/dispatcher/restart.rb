# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # What carries a run across an engine's death: the agents a dead engine
      # left, the stages stranded without one, the heartbeat that says this
      # engine is alive, and prose questions converted off the tick thread.
      class Restart
        # @param desk [Desk]
        # @param options [Options]
        # @param start [Start] adopts a reattached agent
        def initialize(desk, options, start:)
          @desk = desk
          @start = start
          @conversions = Conversions.new(converter: options.converter, runner: desk.runner, find: desk.method(:fresh_by))
          @stranded = Recovery::Stranded.new(runner: desk.runner,
            state: desk.state_file,
            records: desk.records,
            clock: options.clock)
        end

        # @return [OpenLanes::Engine::Conversions]
        attr_reader :conversions

        # The agents a dead engine left, taken back before anything else is
        # started (B1 in plan 041). A verifier's preview app died with that
        # engine, so a verifier is stopped instead, and resumed as stranded (B9).
        #
        # @return [Array<Array(String, String, Integer)>] the stages taken back
        def reattach
          return [] unless state_file

          Execution::AgentProcess.reattachable!
          Recovery::Reattach.new(runner: @desk.runner, state: state_file).call.filter_map do |found|
            next @start.adopt(found) unless @desk.verifier?(found.agent)

            Execution::AgentProcess.attach(found.restart["process"]).tap(&:terminate).wait
            nil
          end
        end

        # @param reattached [Array<Array(String, String, Integer)>] stages {#reattach} took back
        # @return [void] see {Recovery::Stranded}
        def resume_stranded(reattached = []) = @stranded.call(skip: reattached)

        # Prose questions go to the model off the tick thread; what it wrote
        # comes back on a later tick (D9). A quitting or dry run applies what
        # already came back and sends nothing new.
        #
        # @return [void]
        def convert_questions
          @conversions.call(busy: @desk.untouchable, start: !(@desk.runner.dry_run? || Execution::Control.quit?))
        end

        # @return [void]
        def persist
          return unless state_file

          state_file.heartbeat!
          state_file.save
        end

        private

        def state_file = @desk.state_file
      end
    end
  end
end
