# frozen_string_literal: true

module OpenLanes
  module Plans
    # A folder's state: what it means, which files it cannot be honest without,
    # and the rule that decides whether the folder may legitimately claim it.
    #
    # `invariant` is asked in both directions. {StateMachine} asks it of a
    # destination before moving there; `resync` and `check` ask it of the current
    # state, to catch folders whose name has drifted from their contents. One
    # definition, so the two can never disagree about what a state means.
    #
    # @!attribute [r] key
    #   @return [Symbol] machine-facing name, e.g. `:product_blocked`
    # @!attribute [r] emoji
    #   @return [String] as it appears in the folder name
    # @!attribute [r] label
    #   @return [String] the human words
    # @!attribute [r] requires
    #   @return [Array<String>] files this state cannot be honest without
    # @!attribute [r] note
    #   @return [String] one-line meaning, for tables and generated docs
    # @!attribute [r] invariant
    #   @return [Proc, nil] `(subject) -> String | nil` — the reason it does not hold
    Status = Data.define(:key, :emoji, :label, :requires, :note, :invariant) do
      # @param subject [#file?, #read, #pull_requests]
      # @return [Boolean]
      def satisfied_by?(subject) = violation(subject).nil?

      # @param subject [#file?, #read, #pull_requests]
      # @return [String, nil] why this state is not justified, nil when it is
      def violation(subject)
        missing = requires.reject { |f| subject.file?(f) }
        return "#{label} requires #{missing.map { |f| "`#{f}`" }.join(" and ")}" unless missing.empty?

        invariant&.call(subject)
      end

      # @return [Boolean] whether nothing may follow this state
      def terminal? = StateMachine.outbound(key).empty?

      # @return [String] emoji and words, as the tables print it
      def to_s = "#{emoji} #{label}"
    end

    # "1 pull request", "3 pull requests".
    #
    # @param count [Integer]
    # @return [String]
    def self.pull_request_count(count) = "#{count} pull request#{"s" unless count == 1}"

    # What proves a specification has been researched rather than merely
    # written: the chapter `leah-researcher` contributes. It is a section of
    # `spec.md` rather than a file of its own because research is not a separate
    # document — it is the first half of the specification, and splitting it
    # would leave `yoda-writer` reading two files to write one.
    RESEARCH_CHAPTER = /^[ \t]{0,3}\#{2,3}[ \t]+Research\b/i

    # What proves `plan.md` holds a plan rather than the blank file
    # `yoda-writer` leaves for `luthen-rael-planner`: any section heading. The
    # ledger notes are stripped first, so an agent's `Started` line does not
    # count as a plan.
    PLAN_HEADING = /^[ \t]{0,3}\#{1,3}[ \t]+\S/

    # Variation selectors make ⚪️ and ⚪ different strings that mean the same
    # thing to a human. Compare with them removed.
    #
    # @param str [String, nil]
    # @return [String]
    def self.fold_emoji(str) = str.to_s.gsub(/[\u{FE0E}\u{FE0F}\u{200D}]/, "")

    # 🟢 Ready for Review, 👀 In Review and 🔴 Changes Requested are the same
    # thing on disk — the work exists and at least one pull request is still
    # open. Which of the three it is lives in the folder name and nowhere else,
    # so they share one invariant rather than three that could drift apart.
    #
    # @param label [String]
    # @return [Proc]
    def self.open_pull_request(label)
      lambda { |subject|
        return "#{label} requires an open pull request; none are recorded" if subject.pull_requests.empty?

        "#{label}, but every pull request is already merged" if subject.pull_requests.none?(&:open?)
      }
    end

    # 🔗 Ready for Linking and 📋 Ready for Planning share one invariant:
    # `plan.md` exists and nobody has planned in it yet.
    #
    # @param label [String]
    # @return [Proc]
    def self.blank_plan(label)
      lambda { |subject|
        body = Ledger.stripped(subject.read("plan.md"))
        "#{label}, but `plan.md` already holds a plan" if body.match?(PLAN_HEADING)
      }
    end

    # A question that is still somebody's to answer, written as its own heading:
    # `## B1`, `## B2`. The number is what `blocked.md` gets referenced by in
    # conversation and in pull requests, so it is also the only part of the file
    # a program can count.
    #
    # Whoever writes `blocked.md` MUST use this notation. A question written any
    # other way is invisible to every part of this tool: the folder never becomes
    # ⭕️, and `unblock` reports a file with nothing in it to drain. {ANSWER_BLOCK}
    # is the other half of the pair.
    OPEN_BLOCK = /^[ \t]{0,3}\#{0,4}[ \t]*\**B(\d+)\b/

    # The answer to the question of the same number: `## A1` settles `## B1`.
    #
    # Answers are an inbox, not a record. `lando-broker` folds each one into the
    # document its question was stopping and deletes both, so a `blocked.md`
    # holding nothing but history must not go on stopping the folder. An `A`
    # never matches {OPEN_BLOCK}, which is what lets the two live in one file.
    ANSWER_BLOCK = /^[ \t]{0,3}\#{0,4}[ \t]*\**A(\d+)\b/

    # The numbers named by every heading in +text+ matching +pattern+.
    #
    # @param text [String, nil]
    # @param pattern [Regexp] {OPEN_BLOCK} or {ANSWER_BLOCK}
    # @return [Array<Integer>] in the order they appear, without duplicates
    def self.block_numbers(text, pattern)
      text.to_s.lines.filter_map { |line| line[pattern, 1]&.to_i }.uniq
    end

    # ⭕️ Technical Block and 🅱️ Product Block are the same thing on disk: a
    # `blocked.md` still naming at least one question nobody has answered. Which
    # human is owed the answer lives in the folder name and nowhere else, so the
    # two share one invariant rather than two that could drift apart.
    #
    # This is what lets a block drain in pieces. Answers land in `blocked.md`
    # one at a time, `lando-broker` moves each into `spec.md` or `plan.md` and
    # deletes it here, and the folder leaves ⭕️ on the pass that empties the
    # file, by content rather than by anyone remembering to delete it.
    #
    # @param label [String]
    # @return [Proc]
    def self.open_block(label)
      lambda { |subject|
        "#{label}, but `blocked.md` names no open question" unless subject.read("blocked.md").to_s.match?(OPEN_BLOCK)
      }
    end

    # Every state a plan folder may be in, in lifecycle order. That order drives
    # the legend, the generated documentation and the `--to` help text.
    #
    # 🟣 Merged is deliberately absent: it is a pull request's status, not a
    # folder's, and giving it a folder state invites folders that claim a pull
    # request's condition as their own.
    #
    # Adding a state here, or changing an emoji, makes the hand-drawn
    # `docs/img/plan-spec-build.png` stale — `just docs` will show you, because
    # the mermaid source in the generated document moves with this list.
    STATUSES = [
      Status.new(
        key:       :new,
        emoji:     "⚪",
        label:     "New",
        requires:  %w[spec.md],
        note:      "a specification exists; it has not been planned yet",
        invariant: nil
      ),
      Status.new(
        key:       :researched,
        emoji:     "🔎",
        label:     "Researched",
        requires:  %w[spec.md],
        note:      "the topic has been researched; `spec.md` carries a `## Research` chapter",
        invariant: lambda { |s|
          body = s.read("spec.md").to_s
          "Researched, but `spec.md` has no `## Research` chapter" unless body.match?(RESEARCH_CHAPTER)
        }
      ),
      # 🔗 and 📋 hold the same files: a finished `spec.md` and the blank
      # `plan.md` yoda-writer leaves. What tells them apart is whether
      # `ewoki-linker` has answered `depends_on:`, which the folder name
      # records and the invariant deliberately does not: a 📋 plan written
      # before the linker existed would otherwise be renamed backwards by
      # `resync`. The two are a {StateMachine::FAMILIES family} for that reason.
      Status.new(
        key:       :ready_for_linking,
        emoji:     "🔗",
        label:     "Ready for Linking",
        requires:  %w[spec.md plan.md],
        note:      "the specification is finished; ewoki-linker writes its `depends_on:` before the planner starts",
        # Whether `depends_on:` is answered is what tells 🔗 from 📋 on disk,
        # so a 📋 plan coming back from ⭕ is not sent to be linked again.
        invariant: lambda { |subject|
          blank_plan("Ready for Linking").call(subject) ||
            ("Ready for Linking, but `spec.md` already answers `depends_on:`" if Spec.for(subject).linked?)
        }
      ),
      Status.new(
        key:       :ready_for_planning,
        emoji:     "📋",
        label:     "Ready for Planning",
        requires:  %w[spec.md plan.md],
        note:      "the specification is finished; `plan.md` exists and is still blank, waiting for the planner",
        invariant: blank_plan("Ready for Planning")
      ),
      Status.new(
        key:       :planned,
        emoji:     "⭐",
        label:     "Planned",
        requires:  %w[spec.md plan.md],
        note:      "specified and planned; nobody has started building",
        invariant: lambda { |s|
          body = Ledger.stripped(s.read("plan.md"))
          next "Planned, but `plan.md` has no work units yet" unless body.match?(PLAN_HEADING)

          # An open pull request means somebody did start. Without this
          # clause a ✅ folder found with a new pull request would fall back
          # to ⭐️, the family's floor, and claim nobody had touched it.
          open = s.pull_requests.count(&:open?)
          "Planned, but #{OpenLanes::Plans.pull_request_count(open)} already open" if open.positive?
        }
      ),
      # `pull-requests.md` is deliberately absent from `requires` on both of the
      # building states, though it names the file they are about. That file is
      # written by opening a pull request, which happens once, when the last
      # implementer advances the plan to Ready for Review. Requiring the file to
      # *enter* Building would mean nothing could ever justify entering it, and
      # `luthen-rael-planner` finishing `plan.md` would loop forever between itself
      # and a state it can never actually reach. Ready for Review is where the
      # file becomes a real requirement, once something has had the chance to
      # write it.
      Status.new(
        key:       :building,
        emoji:     "🟡",
        label:     "Building",
        requires:  %w[spec.md plan.md],
        note:      "the back end is under way: data, domain and the API the interface will call",
        invariant: lambda { |s|
          body = Ledger.stripped(s.read("plan.md"))
          "Building, but `plan.md` has no work units to build" unless body.match?(PLAN_HEADING)
        }
      ),
      # Two building states rather than one, because the order is not a
      # preference: an interface is written against an API that already answers.
      # Splitting them lets each half be built by someone who only has to be good
      # at that half, and gives the second a working system to build on rather
      # than a description of one.
      Status.new(
        key:       :building_ui,
        emoji:     "🎨",
        label:     "Building UI",
        requires:  %w[spec.md plan.md],
        note:      "the back end holds; the interface is being built against it",
        invariant: lambda { |s|
          body = Ledger.stripped(s.read("plan.md"))
          "Building UI, but `plan.md` has no work units to build" unless body.match?(PLAN_HEADING)
        }
      ),
      Status.new(
        key:       :ready_for_review,
        emoji:     "🟢",
        label:     "Ready for Review",
        requires:  %w[spec.md plan.md pull-requests.md],
        note:      "every pull request is green on CI and waiting for a reviewer",
        invariant: open_pull_request("Ready for Review")
      ),
      Status.new(
        key:       :in_review,
        emoji:     "👀",
        label:     "In Review",
        requires:  %w[spec.md plan.md pull-requests.md],
        note:      "a reviewer has picked it up and has not ruled yet",
        invariant: open_pull_request("In Review")
      ),
      Status.new(
        key:       :verifying,
        emoji:     "🧪",
        label:     "Verifying",
        requires:  %w[spec.md plan.md pull-requests.md],
        note:      "the review approved it; chewie runs the app through How to test before anything merges",
        invariant: open_pull_request("Verifying")
      ),
      # Completed is not done. `ready-to-merge` is a pull request's state
      # (P2), and once every pull request of the plan carries it the plan is
      # 🏁: palpatine rules on each, the engine merges the `auto` ones one at
      # a time and rebases the rest onto `main`, and `merge-manually` ones
      # wait for a person. At least one is still open, or the plan would be
      # ✅ (P3).
      Status.new(
        key:       :completed,
        emoji:     "🏁",
        label:     "Completed",
        requires:  %w[spec.md plan.md pull-requests.md],
        note:      "every pull request is `ready-to-merge`; palpatine weighs each, and they merge one at a time",
        invariant: open_pull_request("Completed")
      ),
      Status.new(
        key:       :rejected,
        emoji:     "🔴",
        label:     "Changes Requested",
        requires:  %w[spec.md plan.md pull-requests.md],
        note:      "the review asked for fixes; resubmit once they are made",
        invariant: open_pull_request("Changes Requested")
      ),
      Status.new(
        key:       :approved,
        emoji:     "✅",
        label:     "Approved & Merged",
        requires:  %w[pull-requests.md],
        note:      "reviewed, approved, and every pull request merged",
        invariant: lambda { |s|
          return "Approved & Merged, but no pull requests are recorded" if s.pull_requests.empty?

          open = s.pull_requests.count(&:open?)
          "Approved & Merged, but #{OpenLanes::Plans.pull_request_count(open)} still open" if open.positive?
        }
      ),
      Status.new(
        key:       :deployed,
        emoji:     "😎",
        label:     "Deployed",
        requires:  %w[deployed.md],
        note:      "live in production; `deployed.md` names the release, date and SHA",
        invariant: nil
      ),
      Status.new(
        key:       :rolled_back,
        emoji:     "😱",
        label:     "Rolled Back",
        requires:  %w[rollback.md],
        note:      "it shipped and was pulled; `rollback.md` names what broke",
        invariant: nil
      ),
      Status.new(
        key:       :shit,
        emoji:     "💩",
        label:     "Scrapped by Review",
        requires:  %w[rewrite.md],
        note:      "the review scrapped the work; the plan survives, the pull requests do not",
        invariant: nil
      ),
      Status.new(
        key:       :blocked,
        emoji:     "⭕",
        label:     "Technical Block",
        requires:  %w[blocked.md],
        note:      "cannot proceed; `blocked.md` names what an engineer or the CTO must decide",
        invariant: open_block("Technical Block")
      ),
      Status.new(
        key:       :product_blocked,
        emoji:     "🛑",
        label:     "Product Block",
        requires:  %w[blocked.md],
        note:      "cannot proceed; `blocked.md` names what a product manager must decide",
        invariant: open_block("Product Block")
      ),
      # 💣 is entered only by the aging sweep's `bomb` event, never by what a
      # folder holds: its contents are a ⭕'s, and a check that read the clock
      # would rename folders as days pass with nobody firing anything. Its
      # check is a block's, open question and all: a weaker one would let
      # `resync` carry a drained ⭕ sideways into 💣 instead of out.
      Status.new(
        key:       :bomb,
        emoji:     "💣",
        label:     "Bomb",
        requires:  %w[blocked.md],
        note:      "blocked too long while other plans depend on it; the run halts until a human answers",
        invariant: open_block("Bomb")
      ),
      Status.new(
        key:       :deferred,
        emoji:     "💤",
        label:     "Deferred",
        requires:  %w[delayed.md],
        note:      "could proceed and chose not to yet; `delayed.md` must name the trigger",
        invariant: lambda { |s|
          body = s.read("delayed.md").to_s
          "Deferred, but `delayed.md` names no trigger" unless body.match?(/trigger|revisit|when\b|until\b|once\b/i)
        }
      ),
      Status.new(
        key:       :retroactive,
        emoji:     "⏪",
        label:     "Retroactive",
        requires:  [],
        note:      "the feature is live, but has neither a specification nor a plan",
        invariant: lambda { |s|
          next "Retroactive, but a `spec.md` already exists — it has been documented" if s.file?("spec.md")

          "Retroactive, but no pull requests are recorded" if s.pull_requests.empty?
        }
      ),
      Status.new(
        key:       :discarded,
        emoji:     "❌",
        label:     "Discarded",
        requires:  %w[discarded.md],
        note:      "dropped for good; `discarded.md` says why. A terminal state",
        invariant: nil
      )
    ].freeze

    # Symbol => status.
    STATUS_BY_KEY = STATUSES.to_h { |s| [s.key, s] }.freeze

    # The emoji each state wore before every one became a single code point
    # (decision N2). Folders, ledgers and snapshots written before then still
    # carry them, and a plan named with one must keep its state until
    # `resync dirs` renames it. Read only, never written. `⚪️ ⭐️ ⭕️` fold onto
    # their successors anyway; the rest are different characters altogether,
    # and `🅱` appears both with and without its variation selector.
    LEGACY_EMOJI = {
      "⚪️" => :new, "⭐️" => :planned, "⭕️" => :blocked, "🅱️" => :product_blocked, "🅱" => :product_blocked,
      "☢️" => :deferred, "🕰️" => :retroactive
    }.freeze

    # Emoji => status, folded so ⚪ and ⚪️ both resolve, and so does every
    # {LEGACY_EMOJI} spelling.
    STATUS_BY_EMOJI = STATUSES.each_with_object({}) { |s, h| h[fold_emoji(s.emoji)] ||= s }
                              .merge(LEGACY_EMOJI.to_h { |e, key| [fold_emoji(e), STATUS_BY_KEY.fetch(key)] }) { |_, now, _| now }
                              .freeze

    # @param emoji [String, nil]
    # @return [OpenLanes::Plans::Status, nil]
    def self.status_for_emoji(emoji) = STATUS_BY_EMOJI[fold_emoji(emoji)]

    # Resolve a state from the only two names it has: its key, and its emoji.
    #
    # There is deliberately no synonym table. A state that also answers to
    # "star", "green" and "completed" has four names to keep in step with the
    # folder, the generated docs and the agent frontmatter — and the synonym
    # table that used to live here went stale pointing six words at a state that
    # no longer existed.
    #
    # @param text [String, Symbol, OpenLanes::Plans::Status, nil]
    # @return [OpenLanes::Plans::Status, nil]
    def self.status(text)
      return nil if text.nil?
      return text if text.is_a?(Status)

      key = text.to_s.strip
      STATUS_BY_KEY[key.to_sym] || status_for_emoji(key)
    end
  end
end
