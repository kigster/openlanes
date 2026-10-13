# frozen_string_literal: true

module OpenLanes
  module Linear
    # One unit of work inside a plan — the thing that becomes a Linear issue.
    #
    # @!attribute [r] key
    #   @return [String] "PR-1" from a plan.md heading, or "#38" from a pull request
    # @!attribute [r] title
    #   @return [String] the heading's words, without the "PR-1 —" part
    # @!attribute [r] body
    #   @return [String] everything under the heading, as written
    # @!attribute [r] pull_requests
    #   @return [Array<OpenLanes::Plans::PullRequest>] the ones this unit claims
    Unit = Data.define(:key, :title, :body, :pull_requests)

    # Reads the work units out of a plan folder.
    #
    # `plan.md` is written by an agent for humans, not as a data file, so this
    # reads the one structure the format has always had: a heading per unit,
    # naming the pull request it will become. Everything else is prose about
    # those units.
    #
    # Two things about real plans make that harder than it sounds, and both
    # were found by running this over thirty-eight of them:
    #
    #   * The unit headings are all at one level, but *which* level varies by
    #     document — `## PR-1 — …` in one plan, `### PR 020.01 — …` in the
    #     next. Deeper headings underneath them (`### PR-1 tests`) name the
    #     same unit again. Matching every heading that mentions a pull request
    #     turned one plan's three units into nine.
    #   * A plan numbers its units either from one (`PR-1`) or from its own
    #     spec number (`PR 020.01`). The second form is the first form with
    #     the plan's number glued on, so it is normalised back.
    #
    # A plan with no such headings is not an error. Retroactive plans have no
    # `plan.md` at all, and a small plan is often one pull request with no
    # internal divisions — both import as a single issue standing for the
    # whole plan, which is the honest reading of a plan that never divided
    # itself.
    class Units
      # `## 2. PR-1 — …`, `### PR 020.01 — …`, and the several other ways the
      # same heading gets typed. The hashes are escaped because an unescaped
      # `#{` in a regexp literal is interpolation.
      HEADING = /\A(\#{2,4})[ \t]+(?:\d+[.)][ \t]*)?PR[\s_-]?(\d+(?:\.\d+)?)\b[ \t]*(.*)\z/i

      # A fenced block can hold anything, including lines that read as
      # headings — `plan.md` files are full of shell and SQL whose comments
      # start with `#`. Scanning without stripping fences invents units.
      FENCE = /^[ \t]{0,3}(?:```|~~~)/

      # `(✔ #38)`, `(▶︎ in-flight)`, `(⬜ blocked)` — a status glyph in a
      # trailing parenthetical. It is the state of the unit, which Linear
      # tracks itself, and leaving it in the title means every title churns
      # the moment the work moves.
      GLYPH_NOTE = /\s*\((?:[^\w\s(][^)]*)\)\s*\z/

      # The same thing without the brackets: `… over the law plane ☢️ deferred`.
      TRAILING_GLYPH = /\s*[\u{2190}-\u{2BFF}\u{1F000}-\u{1FAFF}][^\n]*\z/

      # A plan number the author typed into the heading as well. The issue for
      # the plan already carries it.
      OWN_NUMBER = /\A\[\d{1,3}(?:\.\d{2})?\]\s*/

      # Pull request numbers named in the heading: "(✔ #38)".
      NUMBERED = /#(\d+)\b/

      # @param subject [OpenLanes::Plans::Subject]
      def initialize(subject:)
        @subject = subject
      end

      # The units of work inside a plan, which become its sub-issues.
      #
      # A plan that declares its units in `plan.md` gets those. A plan that
      # does not — a retroactive one, or one written before the convention —
      # gets one per pull request instead, because a pull request that shipped
      # is a unit of work whether or not anybody wrote it down first.
      #
      # A plan with neither is legitimately empty: it has been specified and
      # nothing has been divided or built yet. Its issue stands alone until
      # somebody plans it.
      #
      # @return [Array<OpenLanes::Linear::Unit>] possibly empty
      def all = @all ||= divided.empty? ? from_pull_requests : attach(divided)

      # A pull request title carries the plan number this tool put there, and
      # often the unit it implements. Neither belongs in an issue title: the
      # issue for the plan already says which plan, and the attachment already
      # says which pull request.
      #
      # @param title [String]
      # @return [String]
      def self.clean_title(title)
        title.to_s
             .sub(/\A\[[^\]]*\]\s*/, "")
             .sub(/\A(?:spec\s*)?\d{1,3}(?:\.\d{2})?\s*[—–:.-]?\s*/i, "")
             .sub(/\APR[\s_-]?\d+(?:\.\d+)?\s*[—–:.-]?\s*/i, "")
             .strip
      end

      private

      # @return [OpenLanes::Plans::Subject]
      attr_reader :subject

      # @return [Array<OpenLanes::Linear::Unit>] possibly empty
      def divided = @divided ||= merge(sections).map { |key, title, body| Unit.new(key:, title:, body:, pull_requests: []) }

      # One unit per pull request, for a plan that declared none itself.
      #
      # Keyed by pull request number rather than by position, so the key means
      # something on its own and cannot collide with the `PR-1` keys a
      # `plan.md` would introduce later.
      #
      # @return [Array<OpenLanes::Linear::Unit>]
      def from_pull_requests
        subject.pull_requests.map do |pr|
          Unit.new(key: "##{pr.number}", title: clean_pr(pr.title), body: "", pull_requests: [pr])
        end
      end

      # @param title [String]
      # @return [String]
      def clean_pr(title) = self.class.clean_title(title)

      # @return [Array<Array(String, String, String)>] key, title, body
      def sections
        lines = readable
        level = headings(lines).map(&:first).min
        return [] unless level

        found = []
        lines.each do |line|
          match = HEADING.match(line)
          if match && match[1].length == level
            found << [key_for(match[2]), clean(match[3]), +""]
          elsif found.any?
            found.last[2] << line << "\n"
          end
        end
        found.reject { |_, title, _| title.empty? }
      end

      # A heading at the shallowest level that names a pull request starts a
      # unit; a deeper one is that unit's contents.
      #
      # @param lines [Array<String>]
      # @return [Array<Array(Integer, String)>] level and key
      def headings(lines)
        lines.filter_map { |line|
          match = HEADING.match(line)
          [match[1].length, key_for(match[2])] if match
        }
      end

      # `PR 020.01` inside plan 020.00 is this plan's first unit, written the
      # long way. Reduced, so its key does not depend on which convention the
      # author reached for.
      #
      # @param number [String] "1" or "020.01"
      # @return [String]
      def key_for(number)
        major, minor = number.split(".")
        return "PR-#{number}" unless minor
        return "PR-#{number}" unless major.to_i == subject.feature.ordinal.major

        "PR-#{minor.to_i}"
      end

      # One unit, headed twice. Bodies join; the first title wins, because a
      # later heading for the same unit is a continuation and titles itself
      # like one — "PR-1 tests", "PR-1 parameters".
      #
      # @param sections [Array<Array(String, String, String)>]
      # @return [Array<Array(String, String, String)>]
      def merge(sections)
        sections.each_with_object({}) { |(key, title, body), by_key|
          if by_key.key?(key)
            by_key[key][2] = "#{by_key[key][2]}\n\n#{body}"
          else
            by_key[key] = [key, title, body]
          end
        }.values.map { |key, title, body| [key, title, body.strip] }
      end

      # Which pull requests each unit claims, by the three joins that exist
      # between `plan.md` and `pull-requests.md`, most explicit first.
      #
      # @param units [Array<OpenLanes::Linear::Unit>]
      # @return [Array<OpenLanes::Linear::Unit>]
      def attach(units)
        claimed = []
        found = units.map { |unit|
          prs = (numbered(unit) + named(unit)).uniq - claimed
          claimed.concat(prs)
          unit.with(pull_requests: prs)
        }

        return found unless found.one?

        # With one unit there is nowhere else for a pull request to go. That
        # is arithmetic rather than a guess, so it is done rather than warned
        # about — and it is the common case for the small plans.
        [found.first.with(pull_requests: subject.pull_requests)]
      end

      # The heading said so: `### PR 020.03 — Clerk webhooks (✔ #44)`.
      #
      # @param unit [OpenLanes::Linear::Unit]
      # @return [Array<OpenLanes::Plans::PullRequest>]
      def numbered(unit)
        wanted = heading_for(unit.key).to_s.scan(NUMBERED).flatten
        subject.pull_requests.select { |pr| wanted.include?(pr.number.to_s) }
      end

      # The pull request title said so: "Spec 010 PR-2: MAGI registry".
      #
      # @param unit [OpenLanes::Linear::Unit]
      # @return [Array<OpenLanes::Plans::PullRequest>]
      def named(unit)
        pattern = /\bPR[\s_-]?#{unit.key[/\d+\z/]}\b/i
        subject.pull_requests.select { |pr| pr.title.match?(pattern) }
      end

      # Every heading line that names a unit, grouped by its key — the deeper
      # continuation headings included, since any of them may be the one
      # carrying the pull request number.
      #
      # @return [Hash{String => Array<String>}]
      def headlines
        @headlines ||= readable.each_with_object(Hash.new { |h, k| h[k] = [] }) do |line, found|
          match = HEADING.match(line)
          found[key_for(match[2])] << line if match
        end
      end

      # @param key [String]
      # @return [String] every heading this unit was written under
      def heading_for(key) = headlines[key].join("\n")

      # Every line of `plan.md` that is not inside a fence, fence lines
      # themselves included in what gets dropped.
      #
      # @return [Array<String>]
      def readable
        @readable ||= begin
          fenced = false
          subject.read("plan.md").to_s.each_line(chomp: true).each_with_object([]) do |line, kept|
            if line.match?(FENCE)
              fenced = !fenced
            elsif !fenced
              kept << line
            end
          end
        end
      end

      # @param title [String]
      # @return [String]
      def clean(title)
        title.to_s
             .sub(/\A\([^)]*\)\s*/, "") # "(010a) — Per-person taxes" — a nickname, not a title
             .sub(/\A[—–:.-]+\s*/, "")
             .sub(GLYPH_NOTE, "")
             .sub(TRAILING_GLYPH, "")
             .gsub(/[*`]/, "") # before OWN_NUMBER: the number is often inside backticks
             .sub(/\A_+/, "").sub(/_+\z/, "") # emphasis, but never `signed_off`
             .sub(OWN_NUMBER, "")
             .strip
      end
    end
  end
end
