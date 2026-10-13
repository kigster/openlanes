# frozen_string_literal: true

module OpenLanes
  module Evals
    # One deterministic question about a finished folder.
    #
    # Two families, matching the two things D8 asks of every agent:
    #
    #   outcome — state, signed, files, sections, contents, changed paths:
    #             did it finish the task?
    #   depth   — words, counts, diff size, seconds, tokens, bounded per
    #             depth: did it work at the level it was asked for? Too
    #             shallow for deep fails, and so does overdone for fast.
    #
    # @!attribute [r] kind
    #   @return [Symbol] which judge answers it
    # @!attribute [r] name
    #   @return [String] how a report names it
    # @!attribute [r] args
    #   @return [Hash{Symbol => Object}] what the judge is given
    Check = Data.define(:kind, :name, :args) do
      # @param evidence [OpenLanes::Evals::Evidence]
      # @return [OpenLanes::Evals::Verdict]
      def call(evidence)
        ok, detail = Check::Judges.public_send(kind, evidence, **args)
        Verdict.new(name:, ok:, detail:)
      end
    end

    class Check
      class << self
        # @param kase [OpenLanes::Evals::Case]
        # @return [Array<OpenLanes::Evals::Check>]
        def for(kase) = outcome(kase.expect) + depth(kase.bounds, kase.depth)

        private

        # @return [Array<OpenLanes::Evals::Check>]
        def outcome(expect)
          list = []
          list << new(kind: :state, name: "state #{expect["state"]}", args: { expected: expect["state"].to_sym }) if expect["state"]
          if expect["signed"]
            note = expect["signed"] == true ? nil : expect["signed"].to_s
            list << new(kind: :signed, name: "signed Completed#{" (#{note})" if note}", args: { note: })
          end
          Array(expect["files_exist"]).each { |f| list << new(kind: :file_exists, name: "has #{f}", args: { file: f }) }
          Array(expect["files_absent"]).each { |f| list << new(kind: :file_absent, name: "no #{f}", args: { file: f }) }
          expect.fetch("sections", {}).each do |file, headings|
            list << new(kind: :sections, name: "sections in #{file}", args: { file:, headings: Array(headings) })
          end
          %w[contains excludes].each do |kind|
            expect.fetch(kind, {}).each do |file, texts|
              Array(texts).each { |text| list << new(kind: kind.to_sym, name: "#{file} #{kind} #{text}", args: { file:, text: }) }
            end
          end
          Array(expect["changed_paths"]).each { |g| list << new(kind: :changed, name: "changed #{g}", args: { glob: g }) }
          Array(expect["untouched"]).each { |g| list << new(kind: :untouched, name: "untouched #{g}", args: { glob: g }) }
          list
        end

        # @return [Array<OpenLanes::Evals::Check>]
        def depth(bounds, level)
          list = []
          %w[words count].each do |kind|
            Array(bounds[kind].is_a?(Hash) ? [bounds[kind]] : bounds[kind]).each do |b|
              where = b["section"] ? "#{b["file"]}##{b["section"]}" : b["file"]
              what = kind == "count" ? "count /#{b["pattern"]}/ in #{where}" : "words in #{where}"
              args = { file: b["file"], section: b["section"], min: b["min"], max: b["max"] }
              args[:pattern] = b["pattern"] if kind == "count"
              list << new(kind: kind.to_sym, name: "#{what} #{range(b)} @#{level}", args:)
            end
          end
          %w[changed_files changed_lines].each do |kind|
            next unless (b = bounds[kind])

            list << new(kind: kind.to_sym, name: "#{kind.tr("_", " ")} #{range(b)} @#{level}", args: { min: b["min"], max: b["max"] })
          end
          list << new(kind: :seconds, name: "seconds ≤ #{bounds["max_seconds"]} @#{level}", args: { max: bounds["max_seconds"] }) if bounds["max_seconds"]
          list << new(kind: :tokens, name: "tokens ≤ #{bounds["max_tokens"]} @#{level}", args: { max: bounds["max_tokens"] }) if bounds["max_tokens"]
          list
        end

        # @return [String] `10..40`, `≥ 10` or `≤ 40`
        def range(bound)
          min, max = bound.values_at("min", "max")
          return "#{min}..#{max}" if min && max

          min ? "≥ #{min}" : "≤ #{max}"
        end
      end

      # The answers. Each takes the evidence and its check's arguments and
      # returns `[ok, detail]`; {Check#call} names the verdict.
      module Judges
        module_function

        # Where the folder ended, and whether that state's own invariant holds
        # of what is in it. A recording that claims 🔎 without a Research
        # chapter fails here exactly as a rename would be refused.
        #
        # @return [Array(Boolean, String)]
        def state(evidence, expected:)
          actual = evidence.state or return [false, "the run recorded no final state"]
          return [false, "ended #{actual}, expected #{expected}"] unless actual == expected

          status = Plans.status(expected)
          violation = status.violation(evidence.subject_as(status))
          violation ? [false, violation] : [true, status.to_s]
        end

        # @return [Array(Boolean, String)]
        def signed(evidence, note:)
          agent = evidence.agent
          entry = Plans::Ledger.last_for(Plans::Ledger.read(evidence.folder, agent.ledger), agent.name)
          return [false, "#{agent.name} signed none of #{agent.ledger.join(", ")}"] unless entry
          return [false, "last entry says #{entry.status}"] unless entry.completed?
          if note && !entry.note.to_s.downcase.include?(note.downcase)
            return [false, "signed Completed (#{entry.note || "no note"}), expected #{note}"]
          end

          [true, "#{entry.file}:#{entry.line}"]
        end

        # @return [Array(Boolean, String)]
        def file_exists(evidence, file:)
          File.exist?(File.join(evidence.folder, file)) ? [true, "present"] : [false, "#{file} is missing"]
        end

        # @return [Array(Boolean, String)]
        def file_absent(evidence, file:)
          File.exist?(File.join(evidence.folder, file)) ? [false, "#{file} is still there"] : [true, "absent"]
        end

        # @return [Array(Boolean, String)]
        def sections(evidence, file:, headings:)
          body = evidence.text(file) or return [false, "#{file} is missing"]
          missing = headings.reject { |h| body.lines.any? { |l| l.match?(Evidence.heading(h)) } }
          missing.empty? ? [true, "all #{headings.size} present"] : [false, "missing #{missing.map { |h| "## #{h}" }.join(", ")}"]
        end

        # @return [Array(Boolean, String)]
        def contains(evidence, file:, text:)
          body = evidence.read(file) or return [false, "#{file} is missing"]
          found?(body, text) ? [true, "found"] : [false, "#{file} does not mention #{text}"]
        end

        # @return [Array(Boolean, String)]
        def excludes(evidence, file:, text:)
          body = evidence.read(file) or return [true, "#{file} is absent"]
          found?(body, text) ? [false, "#{file} still says #{text}"] : [true, "not found"]
        end

        # @return [Array(Boolean, String)]
        def changed(evidence, glob:)
          changes = evidence.changes or return [false, "no repository was recorded"]
          hits = changes.matching(glob)
          hits.empty? ? [false, "nothing matching #{glob} changed"] : [true, hits.join(", ")]
        end

        # @return [Array(Boolean, String)]
        def untouched(evidence, glob:)
          changes = evidence.changes or return [false, "no repository was recorded"]
          hits = changes.matching(glob)
          hits.empty? ? [true, "untouched"] : [false, "changed #{hits.join(", ")}"]
        end

        # @return [Array(Boolean, String)]
        def words(evidence, file:, section: nil, min: nil, max: nil)
          body = evidence.text(file, section) or return [false, missing(file, section)]
          within(body.scan(/[[:alnum:]][[:alnum:]'’_-]*/).size, min, max, "words")
        end

        # @return [Array(Boolean, String)]
        def count(evidence, file:, pattern:, section: nil, min: nil, max: nil)
          body = evidence.text(file, section) or return [false, missing(file, section)]
          within(body.scan(Regexp.new(pattern)).size, min, max, "matches")
        end

        # @return [Array(Boolean, String)]
        def changed_files(evidence, min: nil, max: nil)
          changes = evidence.changes or return [false, "no repository was recorded"]
          within(changes.paths.size, min, max, "files changed")
        end

        # @return [Array(Boolean, String)]
        def changed_lines(evidence, min: nil, max: nil)
          changes = evidence.changes or return [false, "no repository was recorded"]
          within(changes.lines, min, max, "lines changed")
        end

        # @return [Array(Boolean, String)]
        def seconds(evidence, max:)
          spent = evidence.run.seconds or return [false, "not measured"]
          within(spent.round, nil, max, "seconds")
        end

        # @return [Array(Boolean, String)]
        def tokens(evidence, max:)
          spent = evidence.run.tokens or return [false, "not measured"]
          within(spent, nil, max, "tokens")
        end

        # @return [Array(Boolean, String)]
        def within(value, min, max, unit)
          return [false, "#{value} #{unit}, fewer than #{min}"] if min && value < min
          return [false, "#{value} #{unit}, more than #{max}"] if max && value > max

          [true, "#{value} #{unit}"]
        end

        # `/.../` is a pattern; anything else is a literal.
        #
        # @return [Boolean]
        def found?(body, text)
          text = text.to_s
          text.length > 2 && text.start_with?("/") && text.end_with?("/") ? body.match?(Regexp.new(text[1..-2])) : body.include?(text)
        end

        # @return [String]
        def missing(file, section) = section ? "#{file} has no ## #{section}" : "#{file} is missing"
      end
    end
  end
end
