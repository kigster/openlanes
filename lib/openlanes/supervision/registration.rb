# frozen_string_literal: true

module OpenLanes
  module Supervision
    # One process's own PID file and title (S2, S5): written when it starts,
    # removed when it ends on purpose, left behind when it crashes, so a
    # file whose process is gone always means a crash.
    #
    #   registration = Supervision.registration("engine", root:)
    #   registration.claim.value_or { refuse(...) }
    #   registration.hold { run_the_engine }
    class Registration
      include Dry::Monads[:result]

      # @param draft [OpenLanes::Supervision::PidFile] what to write, short of
      #   its start time, which {#claim} asks {Probe} for
      # @param dir [OpenLanes::Supervision::PidDir]
      # @param probe [OpenLanes::Supervision::Probe]
      # @param title [OpenLanes::Supervision::Title]
      def initialize(draft:, dir: PidDir.for(draft.root), probe: Probe.new, title: Title.new(role: draft.role, root: draft.root))
        @draft = draft
        @dir = dir
        @probe = probe
        @title = title
      end

      # @return [OpenLanes::Supervision::PidFile, nil] once claimed
      attr_reader :file

      # @return [OpenLanes::Supervision::PidDir]
      attr_reader :dir

      # Takes the role's lock, names this process and writes its file. While
      # another process holds the lock, or a file naming another process that
      # passes {Probe#verified?}, this one is refused. A file that fails the
      # check is a crash's leftover, and is written over.
      #
      # @return [Dry::Monads::Result] Success(self), or Failure({Refusal}):
      #   75 naming the holder, 70 when `ps` cannot give this process's start time
      def claim
        @lock = @dir.lock(@draft.role, pid: @draft.pid)
        held = holder
        return refuse(taken(held), 75) if held || !@lock

        started = @probe.started(@draft.pid) or return refuse(unstarted, 70)
        @title.set
        @file = @draft.with(started:)
        @dir.write(@file)
        Success(self)
      end

      # @return [OpenLanes::Supervision::PidFile, nil] another live process
      #   that already holds this role's file
      def holder
        held = @dir.read(@draft.role, pid: @draft.pid)
        held if held && held.pid != @draft.pid && @probe.verified?(held)
      end

      # Runs the block and removes the file when it ends on purpose: by
      # returning, or by `exit`, which is how every refusal ends. Any other
      # exception is a crash, and the file stays to say so, so a graceful
      # stop must end in one of those two and never in another exception.
      #
      # @yieldreturn [Object]
      # @return [Object] what the block returned
      def hold
        result = yield
        release
        result
      rescue SystemExit
        release
        raise
      end

      # @param status [String, nil]
      # @return [void]
      def title(status = nil) = @title.set(status)

      # Rewrites the file with what changed: a URL, a child given up on.
      #
      # @param changes [Hash]
      # @return [void]
      def update(**changes)
        return unless @file

        @file = @file.with(**changes)
        @dir.write(@file)
      end

      # @return [void]
      def release
        @dir.remove(@file) if @file
        @file = nil
        @lock&.close
        @lock = nil
      end

      private

      # @param message [String]
      # @param status [Integer]
      # @return [Dry::Monads::Result::Failure]
      def refuse(message, status)
        release
        Failure(Refusal.new(message:, status:))
      end

      # A file whose start time is unknown could never be verified, so `stop`
      # would take it for a crash's and leave its process running.
      #
      # @return [String]
      def unstarted
        "#{Title.prefix(@draft.role, @draft.root)} could not read its own start time from `ps`, " \
          "which `openlanes stop` needs to tell it from a reused pid."
      end

      # @param held [OpenLanes::Supervision::PidFile, nil] nil while the
      #   holder of the lock has not yet written its file
      # @return [String]
      def taken(held)
        who = held ? "is already running (pid #{held.pid})#{" at #{held.url}" if held.url}" : "is already starting"
        "#{Title.prefix(@draft.role, @draft.root)} #{who}. `openlanes stop` stops it; `openlanes status` shows it."
      end
    end
  end
end
