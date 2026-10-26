# frozen_string_literal: true

require "time"

module OpenLanes
  module Plans
    # The dated notes an agent leaves in the document it owns.
    #
    # This is the only place in the codebase that knows the syntax. The
    # dispatcher reads it to learn whether an agent finished and who it named
    # next; the state file records it; the screen paints it. An agent writes
    # one entry when it starts and one when it stops, in a GitHub NOTE alert,
    # one entry per line:
    #
    #   > [!NOTE]
    #   >
    #   > [2026-09-04 11:29:20 AM PDT] [ agent: researcher   status: Started, round 1 ]
    #   > [2026-09-04 11:44:03 AM PDT] [ agent: researcher   status: Completed, round 1 ]
    #   > [2026-09-04 11:44:04 AM PDT] [ next: spec-writer ]
    #
    # The verbs are a closed set. A line that looks like an entry but does not
    # parse is reported as a {Problem}, never dropped, because an agent that
    # wrote "Done" has said nothing the harness can act on and silence would
    # read as a stall.
    module Ledger
      # Everything an agent may claim. `Completed` is the only verb a `next:`
      # line may follow.
      STATUSES = ["Started", "Completed", "Almost completed", "Interrupted", "Blocked"].freeze

      # Local time with the zone spelled out, so an entry written on one
      # machine reads correctly on another.
      TIME_FORMAT = "%Y-%m-%d %I:%M:%S %p %Z"

      # An entry. `**` around the status is how the harness marks the one line
      # it writes itself, the Interrupted that precedes a signature.
      ENTRY = /\A>\s*\[(?<at>[^\]]+)\]\s*\[\s*agent:\s*(?<agent>[\w-]+)\s+status:\s*(?<bold>\*\*)?
        (?<status>#{STATUSES.map { |s| Regexp.escape(s) }.join("|")}),\s*round\s*(?<round>\d+)
        (?:\s*\((?<note>[^)]*)\))?\s*(?:\*\*)?\s*\]\s*\z/x

      # The handoff line.
      NEXT = /\A>\s*\[(?<at>[^\]]+)\]\s*\[\s*next:\s*(?<next>[\w-]+)\s*\]\s*\z/

      # A line that is trying to be one of the two above. Anything matching
      # this and neither of those is a {Problem}.
      ATTEMPT = /\A>\s*\[[^\]]+\]\s*\[/

      # The whole alert block, for {.stripped}.
      BLOCK = /^[ \t]*>[ \t]*\[!NOTE\][ \t]*\n(?:[ \t]*>.*\n?)*/

      # @!attribute [r] at
      #   @return [Time]
      # @!attribute [r] agent
      #   @return [String] the definition's name, `researcher`
      # @!attribute [r] status
      #   @return [String] one of {STATUSES}
      # @!attribute [r] round
      #   @return [Integer]
      # @!attribute [r] note
      #   @return [String, nil] the parenthesised tail, `rejected 1/2`
      # @!attribute [r] file
      #   @return [String] the document it was read from
      # @!attribute [r] line
      #   @return [Integer] 1-based
      # @!attribute [r] bold
      #   @return [Boolean] written `**bold**`, which only the harness does
      Entry = Data.define(:at, :agent, :status, :round, :note, :file, :line, :bold) do
        def initialize(note: nil, bold: false, **rest) = super

        # @return [Boolean]
        def completed? = status == "Completed"

        # @return [Boolean] whether the agent gets another round
        def retry? = ["Almost completed", "Interrupted"].include?(status)

        # @return [Boolean]
        def blocked? = status == "Blocked"
      end

      # @!attribute [r] next
      #   @return [String] the agent named
      Handoff = Data.define(:at, :next, :file, :line)

      # @!attribute [r] text
      #   @return [String] the line as written
      Problem = Data.define(:file, :line, :text)

      # What one read of a plan folder yielded.
      Reading = Data.define(:entries, :handoffs, :problems) do
        # @return [OpenLanes::Plans::Ledger::Reading]
        def self.empty = new(entries: [], handoffs: [], problems: [])

        # @param other [OpenLanes::Plans::Ledger::Reading]
        # @return [OpenLanes::Plans::Ledger::Reading]
        def +(other)
          self.class.new(entries: entries + other.entries,
            handoffs: handoffs + other.handoffs,
            problems: problems + other.problems)
        end
      end

      class << self
        # @param text [String] a whole document
        # @param file [String] its name, carried on every entry
        # @return [OpenLanes::Plans::Ledger::Reading]
        def parse(text, file:)
          entries = []
          handoffs = []
          problems = []
          text.to_s.each_line.with_index(1) do |raw, line|
            stripped = raw.chomp
            if (m = ENTRY.match(stripped))
              entries << Entry.new(at: parse_time(m[:at]),
                agent: m[:agent],
                status: m[:status],
                round: m[:round].to_i,
                note: m[:note]&.strip,
                file:,
                line:,
                bold: !m[:bold].nil?)
            elsif (m = NEXT.match(stripped))
              handoffs << Handoff.new(at: parse_time(m[:at]), next: m[:next], file:, line:)
            elsif ATTEMPT.match?(stripped)
              problems << Problem.new(file:, line:, text: stripped.strip)
            end
          end
          Reading.new(entries:, handoffs:, problems:)
        end

        # Every document an agent may sign, in the order its definition lists
        # them, then the signatures in `state.json`. A missing file is not a
        # problem; an agent that has not reached `pull-requests.md` yet has not
        # written it. `state.json` comes last, so on a tie in time a signature
        # made through `openlanes state sign` outranks a line in prose.
        #
        # @param dir [String] the plan folder
        # @param files [Array<String>]
        # @return [OpenLanes::Plans::Ledger::Reading]
        def read(dir, files)
          markdown(dir, files) + signed(dir)
        end

        # A `state.json` that will not parse is reported like an unreadable
        # line, not raised: one bad file must not stop the loop for every plan.
        #
        # @param dir [String]
        # @return [OpenLanes::Plans::Ledger::Reading]
        def signed(dir)
          PlanState.for(dir).ledger
        rescue Error => e
          Reading.new(entries: [], handoffs: [], problems: [Problem.new(file: PlanState::FILENAME, line: 1, text: e.message)])
        end

        # @param dir [String]
        # @param files [Array<String>]
        # @return [OpenLanes::Plans::Ledger::Reading]
        def markdown(dir, files)
          files.each_with_index.reduce(Reading.empty) do |reading, (name, _index)|
            path = File.join(dir, name)
            next reading unless File.file?(path)

            found = parse(File.read(path, encoding: "UTF-8"), file: name)
            reading + Reading.new(entries: found.entries.map { |e| e.with(file: name) },
              handoffs: found.handoffs,
              problems: found.problems)
          end
        end

        # @param time [Time]
        # @return [String]
        def timestamp(time = Time.now) = time.strftime(TIME_FORMAT)

        # Agents write what `date` prints, and `Time.strptime` cannot read a
        # zone abbreviation back into an offset. The abbreviation is dropped
        # and the time read as local, which is right on the machine that wrote
        # it and off by a zone anywhere else, which the tick tolerates: entries
        # are compared with each other, never with the wall clock.
        #
        # @param text [String]
        # @return [Time]
        def parse_time(text)
          Time.strptime(text.to_s.strip.sub(/\s+[A-Z]{2,5}\z/, ""), "%Y-%m-%d %I:%M:%S %p")
        rescue ArgumentError
          Time.at(0)
        end

        # @param entry [OpenLanes::Plans::Ledger::Entry]
        # @return [String] one quoted line, no newline
        def render(entry)
          tail = entry.note ? " (#{entry.note})" : ""
          body = "#{entry.status}, round #{entry.round}#{tail}"
          body = "**#{body}**" if entry.bold
          "> [#{timestamp(entry.at)}] [ agent: #{entry.agent}   status: #{body} ]"
        end

        # @param handoff [OpenLanes::Plans::Ledger::Handoff]
        # @return [String]
        def render_handoff(handoff) = "> [#{timestamp(handoff.at)}] [ next: #{handoff.next} ]"

        # @param lines [Array<String>] already quoted
        # @return [String] a NOTE alert, newline-terminated
        def block(*lines) = (["> [!NOTE]", ">"] + lines.flatten).join("\n") + "\n"

        # Append one block. Separated from what is there by a blank line so the
        # alert renders as its own block rather than merging into a paragraph.
        #
        # @param path [String]
        # @param lines [Array<String>]
        # @return [void]
        def append(path, *lines)
          existing = File.file?(path) ? File.read(path, encoding: "UTF-8") : ""
          glue = if existing.empty?
                   ""
                 elsif existing.end_with?("\n\n")
                   ""
                 elsif existing.end_with?("\n")
                   "\n"
                 else
                   "\n\n"
                 end
          File.write(path, existing + glue + block(*lines))
        end

        # The entry that tells the harness where this agent stands: the latest
        # by clock, then by the order its documents are listed, then by line.
        #
        # @param reading [OpenLanes::Plans::Ledger::Reading]
        # @param agent [String]
        # @return [OpenLanes::Plans::Ledger::Entry, nil]
        def last_for(reading, agent)
          files = reading.entries.map(&:file).uniq
          reading.entries.select { |e| e.agent == agent }
                 .max_by { |e| [e.at, files.index(e.file), e.line] }
        end

        # The `next:` that belongs to an entry: same file, a later line, and no
        # other entry between the two. A handoff written under somebody else's
        # entry is not this agent's handoff.
        #
        # @param reading [OpenLanes::Plans::Ledger::Reading]
        # @param entry [OpenLanes::Plans::Ledger::Entry]
        # @return [OpenLanes::Plans::Ledger::Handoff, nil]
        def handoff_after(reading, entry)
          candidates = reading.handoffs.select { |h| h.file == entry.file && h.line > entry.line }
          handoff = candidates.min_by(&:line) or return nil
          between = reading.entries.any? { |e| e.file == entry.file && e.line > entry.line && e.line < handoff.line }
          between ? nil : handoff
        end

        # @param text [String]
        # @return [String] the document without its ledger blocks
        def stripped(text) = text.to_s.gsub(BLOCK, "")
      end
    end
  end
end
