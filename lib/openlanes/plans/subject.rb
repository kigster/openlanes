# frozen_string_literal: true

module OpenLanes
  module Plans
    # A plan folder as the state machine sees it: which files exist, what they
    # say, and which pull requests they record.
    #
    # It exists because the invariants ask the same questions repeatedly and
    # {Feature} is a frozen `Data` with nowhere to memoize the answers.
    class Subject
      # @param feature [OpenLanes::Plans::Feature]
      def initialize(feature)
        @feature = feature
        @reads = {}
      end

      # @return [OpenLanes::Plans::Feature]
      attr_reader :feature

      # @return [OpenLanes::Plans::Status] the status the folder name claims
      def status = feature.status

      # @param name [String] a bare filename
      # @return [Boolean]
      def file?(name) = File.file?(File.join(feature.path, name))

      # @param name [String]
      # @return [String, nil] contents, or nil when absent
      def read(name)
        @reads.fetch(name) do
          @reads[name] = file?(name) ? File.read(File.join(feature.path, name), encoding: "UTF-8") : nil
        end
      end

      # Forget the memoized reads, after the caller wrote a file itself: the
      # guards would otherwise judge the contents from before the write.
      #
      # @return [self]
      def reread! = tap { @reads = {} }

      # @return [Array<OpenLanes::Plans::PullRequest>]
      def pull_requests = @pull_requests ||= PullRequests.new(dir: feature.path).all

      # The specification's own Goal section, verbatim and at most two
      # paragraphs. Anything that paraphrases the spec is a second copy that
      # drifts; quoting it is not — which is why the pull request body and the
      # index both read it from here rather than each writing their own.
      #
      # @return [Array<String>] paragraphs, empty when there is no Goal to read
      def goal
        body = read("spec.md").to_s
        section = body[/^\#{"#"}{2,3}\s*Goals?\b[^\n]*\n+(.*?)(?=\n\#{"#"}{1,3}\s|\z)/mi, 1]

        paragraphs(section) || paragraphs(body.sub(/\A\s*\#{"#"}[^\n]*\n/, "")) || []
      end

      # Specifications written before the template existed have no Goal section,
      # and they are exactly the ones an index most needs to describe. So the
      # opening prose stands in — skipping headings, quotes, lists and tables,
      # which describe the document rather than the work.
      #
      # @param text [String, nil]
      # @return [Array<String>, nil] nil when there is no prose to be had
      def paragraphs(text)
        found = text.to_s.strip.split(/\n{2,}/)
                    .map(&:strip)
                    .reject { |p| p.empty? || p.match?(/\A[\#>|\-*\d`_=]/) }
                    .first(2)

        found.empty? ? nil : found
      end

      # The questions `blocked.md` still names, by number.
      #
      # Empty means one of two very different things, and a caller that treats
      # them alike is how a folder with thirty kilobytes of open questions gets
      # reported as "nothing left open": either there is no `blocked.md` at all,
      # or there is one whose questions are not written as `## B<n>` and are
      # therefore invisible to every part of this tool. Ask {#file?} which.
      #
      # @return [Array<Integer>]
      def open_blocks = OpenLanes::Plans.block_numbers(read("blocked.md"), OPEN_BLOCK)

      # The answers waiting in `blocked.md`, by number. `## A1` settles `## B1`.
      #
      # Waiting, not folded. An `## A<n>` heading is not the same as a settled
      # question: one may say in its own body that it is a draft pending a
      # conversation. `lando-broker` makes that call; this only counts headings.
      #
      # @return [Array<Integer>]
      def block_answers = OpenLanes::Plans.block_numbers(read("blocked.md"), ANSWER_BLOCK)

      # A `blocked.md` this tool cannot read: the file is there, and not one
      # question in it is written as `## B<n>`. Nothing can drain it and nothing
      # currently says so, which is the whole reason this exists.
      #
      # @return [Boolean]
      def unreadable_block? = file?("blocked.md") && open_blocks.empty?

      # @return [String, nil] why the folder's name is not justified
      def violation = status.violation(self)

      # @return [Boolean] whether the name matches the contents
      def consistent? = violation.nil?

      # @return [OpenLanes::Plans::StateMachine] positioned at the current state
      def machine = StateMachine.new(self)

      # @return [Array<Symbol>] states reachable right now, guards applied
      def allowed = machine.allowed

      # @return [OpenLanes::Plans::Status, nil] the state these contents justify
      def best_fit = machine.best_fit

      # Move the folder into +status+ — the side effect a transition *is*.
      #
      # The {Feature} is a frozen `Data` holding the old name, so it is replaced
      # rather than mutated, and the memoized reads go with it.
      #
      # @param status [OpenLanes::Plans::Status]
      # @return [OpenLanes::Plans::Feature] the feature under its new name
      # @raise [OpenLanes::Error] when the target name is already taken
      def rename_to(status)
        return @feature if status.key == @feature.status.key

        target = File.join(File.dirname(@feature.path), @feature.dirname_as(status))
        unless OpenLanes.move_directory(@feature.path, target)
          raise Error, "cannot rename #{@feature.dirname} — #{File.basename(target)} already exists"
        end

        from = @feature.status
        @reads = {}
        @pull_requests = nil
        @feature = Feature.parse(target) or raise Error, "#{File.basename(target)} is not a plan folder"
        PlanState.for(target).state!(status.key)
        # Every transition passes through here, whoever fires it, so this is
        # the one line in the log that says a plan changed state.
        UI.log("moved: #{from} → #{status}", plan: @feature.ordinal.to_s)
        @feature
      end
    end
  end
end
