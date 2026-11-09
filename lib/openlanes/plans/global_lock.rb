# frozen_string_literal: true

module OpenLanes
  module Plans
    # The gate for a plan marked `execution: global-lock-required` (R6).
    #
    # Once such a plan is ready for backend-coder (⭐ Planned), nothing new starts: the
    # refactor waits until no other plan holds a branch or a pull request,
    # and plans that never started stay queued behind it. Plans that already
    # hold one carry on, so the wait ends when they are merged or closed. Once
    # the refactor's build is under way, nothing else starts until it is
    # merged, blocked or not.
    #
    # Whether a plan holds a branch is read from the tree alone, never from
    # git or GitHub, so asking costs nothing per tick: a plan past the
    # documents and not yet done holds one, and so does a parked plan whose
    # folder shows a build began (`contract.md`, written before any code) or
    # a pull request was opened (`pull-requests.md`).
    class GlobalLock
      # The states in which a plan is finished: its branch merged or closed.
      # Rolled back still shipped first; discarded and trashed close theirs.
      # Abandoned and rewrite are parked instead, since either may resume.
      FINISHED = (Dependencies::DONE + %i[rolled_back discarded trashed]).freeze

      # Parked states, which say nothing about how far the plan got.
      PARKED = (StateMachine::SETTLED - FINISHED).freeze

      # What a parked plan's folder holds once it has a branch.
      BRANCH_MARKERS = %w[contract.md pull-requests.md].freeze

      # @param tree [OpenLanes::Plans::Tree]
      # @param status_of [#call, nil] the state to judge a plan by, as in
      #   {Dependencies#initialize}
      def initialize(tree, status_of: nil)
        @tree = tree
        @status_of = status_of || :status.to_proc
      end

      # The refactor that holds the lock, or nil when none does: the lowest
      # unfinished `global-lock-required` plan that is ready for backend-coder or past it.
      #
      # @return [String, nil] its ordinal
      def holder
        return @holder if defined?(@holder)

        @holder = subjects.find { |s| Execution.global_lock?(s) && active?(s) }&.then { ordinal(it) }
      end

      # @return [Boolean] whether the holder's build has not begun yet
      def waiting? = !holder.nil? && state(holder) == :planned

      # Plans other than the holder that hold a branch or a pull request.
      # While any remains, the holder is not handed to backend-coder.
      #
      # @return [Array<String>] ordinals, sorted
      def waits_on
        return [] unless waiting?

        subjects.reject { ordinal(it) == holder }.select { branch?(it) }.map { ordinal(it) }.sort
      end

      # Why the engine must not start this plan, or nil when it may.
      #
      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [String, nil] e.g. "refactor 031.00 waits on 018.00 ⭕" or
      #   "queued behind refactor 031.00"
      def reason(ordinal)
        return nil if holder.nil?

        wanted = ordinal.to_s
        return own_reason if wanted == holder
        return nil if waiting? && branch?(find(wanted))

        "queued behind refactor #{holder}"
      end

      private

      # @return [String, nil]
      def own_reason
        open = waits_on
        return nil if open.empty?

        "refactor #{holder} waits on #{open.map { "#{it} #{@status_of.call(find(it)).emoji}" }.join(", ")}"
      end

      # A refactor still in the documents does not lock anything yet, and
      # one parked before its build began does not either.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean]
      def active?(subject)
        key = @status_of.call(subject).key
        key == :planned || branch?(subject)
      end

      # @param subject [OpenLanes::Plans::Subject, nil]
      # @return [Boolean]
      def branch?(subject)
        return false if subject.nil?

        key = @status_of.call(subject).key
        return false if FINISHED.include?(key)
        return BRANCH_MARKERS.any? { subject.file?(it) } if PARKED.include?(key) || key == :retroactive

        !Dependencies::BEFORE_BUILD.include?(key)
      end

      # @return [Symbol]
      def state(wanted) = @status_of.call(find(wanted)).key

      # @return [OpenLanes::Plans::Subject, nil]
      def find(wanted) = index[wanted]

      # @return [String]
      def ordinal(subject) = subject.feature.ordinal.to_s

      # @return [Hash{String => OpenLanes::Plans::Subject}]
      def index = @index ||= subjects.to_h { [ordinal(it), it] }

      # @return [Array<OpenLanes::Plans::Subject>] sorted by ordinal
      def subjects = @subjects ||= @tree.subjects.sort_by { ordinal(it) }
    end
  end
end
