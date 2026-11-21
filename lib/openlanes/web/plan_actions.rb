# frozen_string_literal: true

module OpenLanes
  module Web
    # The "Plan Management" menu's actions: which of them one plan offers,
    # and doing one. Each is an operation the CLI already has
    # ({Lifecycle::Removal} for discard, the 💤 edge for defer,
    # {Plans::Spec.with_depends_on} for clearing dependencies), so a plan
    # moved from the page lands exactly where `openlanes plans discard`
    # would have put it.
    #
    # None of them runs under an agent: a rename or a spec edit beneath a
    # running agent is either overwritten by it or breaks it. The page stops
    # the plan's agents first (the engine's `stop_plan`), then asks again.
    class PlanActions
      # No plan by that number.
      class NotFound < OpenLanes::Error; end

      # The action is unknown, not open to this plan, or lacks its reason.
      class Refused < OpenLanes::Error; end

      # An agent is working the plan.
      class Busy < OpenLanes::Error; end

      # Action keys, in the order the menu lists them.
      KEYS = %w[clear_dependencies discard defer].freeze

      # The words 💤 asks `delayed.md` to carry, so a trigger typed without
      # one of them still justifies the state.
      TRIGGER = /trigger|revisit|when\b|until\b|once\b/i

      # What the menu shows for one plan.
      #
      # @!attribute [r] ordinal
      #   @return [String]
      # @!attribute [r] status
      #   @return [String] the status key
      # @!attribute [r] started
      #   @return [Boolean] whether its build has begun, or an agent is on it
      # @!attribute [r] running
      #   @return [Boolean] whether an agent is working it now
      # @!attribute [r] depends_on
      #   @return [Array<String>]
      # @!attribute [r] actions
      #   @return [Array<String>] the keys of {KEYS} open to it
      Offer = Data.define(:ordinal, :status, :started, :running, :depends_on, :actions)

      # @param plans_dir [String]
      # @param working [#call] ordinal => whether an agent works it now
      def initialize(plans_dir:, working:)
        @plans_dir = plans_dir
        @working = working
      end

      # @param ordinal [String]
      # @return [Offer]
      def offer(ordinal)
        subject = find!(ordinal)
        number = subject.feature.ordinal.to_s
        key = subject.status.key
        running = @working.call(number) ? true : false
        Offer.new(ordinal: number,
          status: key.to_s,
          started: running || started?(key),
          running:,
          depends_on: depends_on(subject),
          actions: open_to(subject, key))
      end

      # @param ordinal [String]
      # @param action [String] one of {KEYS}
      # @param reason [String] why (discard) or what ends the wait (defer)
      # @return [Offer] the plan as it stands afterwards
      # @raise [Refused, Busy, NotFound]
      def call(ordinal, action, reason: "")
        subject = find!(ordinal)
        number = subject.feature.ordinal.to_s
        permit!(subject, number, action)
        send(action, subject, reason.to_s.strip)
        action == "discard" ? gone(number) : offer(number)
      end

      private

      # @return [void]
      # @raise [Refused, Busy]
      def permit!(subject, number, action)
        raise Refused, "#{action.inspect} is not one of #{KEYS.join(", ")}" unless KEYS.include?(action)
        raise Busy, "an agent is working on #{number}; stop it first" if @working.call(number)
        return if open_to(subject, subject.status.key).include?(action)

        raise Refused, "#{number} cannot #{action.tr("_", " ")} from #{subject.status}"
      end

      # @return [void]
      def clear_dependencies(subject, _reason)
        path = File.join(subject.feature.path, "spec.md")
        File.write(path, Plans::Spec.with_depends_on(File.read(path), []))
      end

      # @return [void]
      def discard(subject, reason)
        raise Refused, "say why it is discarded" if reason.empty?

        number = subject.feature.ordinal.to_s
        result = Lifecycle.removal(tree: Plans.tree(@plans_dir), to: :discarded).call({ number => reason })
        refusal = result.refused[number] and raise Refused, refusal
      end

      # `delayed.md` goes in first, since 💤 refuses a folder without one; a
      # move that fails, refused or not, takes back a file this call created.
      #
      # @return [void]
      def defer(subject, reason)
        raise Refused, "say what should bring it back" if reason.empty?

        path = File.join(subject.feature.path, "delayed.md")
        created = !File.exist?(path)
        File.open(path, "a") { it.write(delayed(reason, fresh: created)) }
        taking_back(created ? path : nil) { subject.machine.promote!(:deferred) }
      rescue Plans::StateMachine::Refused => e
        raise Refused, e.message
      end

      # Runs the block, removing `path` if the block raises, and raising on.
      #
      # @param path [String, nil] the file to take back; nil keeps whatever is there
      # @return [void]
      def taking_back(path)
        yield
      rescue StandardError
        File.delete(path) if path && File.exist?(path)
        raise
      end

      # @return [String]
      def delayed(reason, fresh:)
        trigger = reason.match?(TRIGGER) ? reason : "Revisit when #{reason}"
        "#{"# Deferred\n\n" if fresh}#{"\n" unless fresh}#{trigger}\n\n- Date: #{Date.today.strftime("%F")}\n- Deferred from the control room\n"
      end

      # @return [Array<String>]
      def open_to(subject, key)
        KEYS.select do |action|
          case action
          when "clear_dependencies" then !depends_on(subject).empty?
          when "discard" then Plans::StateMachine.edge?(key, :discarded)
          when "defer" then Plans::StateMachine.edge?(key, :deferred)
          end
        end
      end

      # @return [Boolean]
      def started?(key) = key == :rejected || Plans::StateMachine.reached?(key, :building)

      # @return [Array<String>]
      def depends_on(subject) = Array(Plans::Spec.for(subject).depends_on).map(&:to_s)

      # A discarded plan leaves the open tree, so it is read back from all of it.
      #
      # @return [Offer]
      def gone(number)
        subject = Plans.tree(@plans_dir).everything.find(number)
        Offer.new(ordinal: number, status: subject&.status&.key.to_s, started: false, running: false, depends_on: [], actions: [])
      end

      # @return [OpenLanes::Plans::Subject]
      def find!(ordinal)
        number = Plans::Ordinal.parse(ordinal.to_s) or raise NotFound, "#{ordinal} is not a plan number"
        Plans.tree(@plans_dir).find(number) or raise NotFound, "there is no plan #{number}"
      end
    end
  end
end
