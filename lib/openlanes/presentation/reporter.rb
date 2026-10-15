# frozen_string_literal: true

module OpenLanes
  module Presentation
    # `/spec-status` — every plan, its state in icon and words, and its pull
    # requests as clickable links.
    #
    # {#render} returns a string and prints nothing. Whoever calls it decides
    # where it goes, which keeps the table pipeable.
    class Reporter
      # Columns, so the header and the rows cannot drift apart.
      HEADINGS = ["Plan", "⬇", "Status", "Feature", "Pull Requests"].freeze

      # Cells given to the plan number: "018.01" with room to grow.
      ORDINAL_WIDTH = 7

      # Cells given to a status icon. Emoji vary in both character count and
      # display width, so the cell is padded to this by {UI.fit} rather than
      # trusted to be any particular size — see the note there.
      EMOJI_WIDTH = 2

      # Cells given to a pull request's state, so the URLs line up beneath each
      # other whichever states the tree happens to contain.
      STATE_WIDTH = Plans::PullRequests::STATES.map { |_, label| UI.display_width(label) }.max

      # @param tree [OpenLanes::Plans::Tree]
      def initialize(tree:)
        @tree = tree
      end

      # @return [OpenLanes::Plans::Tree]
      attr_reader :tree

      # @return [String] the whole table, newline-terminated
      def render
        return "No plans found in #{tree.dir}\n" if tree.subjects.empty?

        [header, *tree.subjects.flat_map { |s| rows_for(s) }, "", footer].join("\n") + "\n"
      end

      # @return [Hash{Symbol => Integer}] how many plans sit in each state
      def totals
        tree.subjects.each_with_object(Hash.new(0)) { |s, h| h[s.status.key] += 1 }
      end

      # Plans whose folder name their contents do not justify.
      #
      # @return [Array<OpenLanes::Plans::Subject>]
      def inconsistent = tree.subjects.reject(&:consistent?)

      private

      # @return [Integer] widest status label, so the column lines up
      def label_width = @label_width ||= tree.subjects.map { |s| UI.display_width(s.status.label) }.max.to_i + 4

      # @return [Integer] widest feature name
      def title_width = @title_width ||= tree.subjects.map { |s| UI.display_width(s.feature.title) }.max.to_i + 2

      # The one place the table's shape is written down. The heading, the plan
      # rows, the continuation lines and the violations all come through here, so
      # a column cannot widen in one of them and stay put in the others.
      #
      # Cells arrive already fitted and already painted, in that order, because
      # the order matters: escape codes count toward a string's length, so
      # padding a coloured string pads it to a width of which several characters
      # are invisible, and the column collapses by exactly that much.
      #
      # @return [String]
      def row(flag, ordinal, emoji, label, title, tail)
        format("%s %s  %s  %s  %s %s", flag, ordinal, emoji, label, title, tail)
      end

      # Cell at which the pull requests start, so a plan's second and third pull
      # requests sit under its first. Measured by running blanks through {#row}
      # rather than counted by hand, so the indent cannot drift when the layout
      # changes.
      #
      # @return [Integer]
      def pr_column
        @pr_column ||= row(" ",
          " " * ORDINAL_WIDTH,
          " " * EMOJI_WIDTH,
          " " * label_width,
          " " * title_width,
          "").length
      end

      # @return [Integer] cell at which the feature name starts
      def title_column = pr_column - title_width - 1

      # @return [String]
      def header
        text = row(" ",
          UI.fit(HEADINGS[0], ORDINAL_WIDTH),
          UI.fit(HEADINGS[1], EMOJI_WIDTH),
          UI.fit(HEADINGS[2], label_width),
          UI.fit(HEADINGS[3], title_width),
          HEADINGS[4])

        rule = "  " + ("─" * (UI.display_width(text) - 2))

        [UI.paint(text, :bold), UI.paint(rule, :bright_yellow)].join("\n")
      end

      # One line per plan, plus a continuation line for each extra pull request
      # so that every URL is visible and clickable rather than truncated.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<String>]
      def rows_for(subject)
        feature = subject.feature
        prs = subject.pull_requests

        first = row(
          subject.consistent? ? " " : UI.paint("!", :red),
          UI.paint(UI.fit(feature.ordinal.to_s, ORDINAL_WIDTH), :bold),
          UI.fit(feature.status.emoji, EMOJI_WIDTH),
          UI.paint(UI.fit(feature.status.label, label_width), :yellow),
          UI.paint(UI.fit(feature.title, title_width), :blue, :bold),
          [prs.empty? ? UI.paint("[none yet]", :bright_red) : link(prs.first), *blocks_note(feature.ordinal)].join("  ")
        )

        rest = prs.drop(1).map { |pr| (" " * pr_column) + link(pr) }

        [first, *rest, *violation_line(subject), *dependency_lines(subject)]
      end

      # What this plan holds up, said in the row's tail so the one line that
      # answers "why is 050 not moving" is on the plan that causes it.
      #
      # @param ordinal [OpenLanes::Plans::Ordinal]
      # @return [Array<String>]
      def blocks_note(ordinal)
        blocked = tree.dependencies.blocks_of(ordinal)
        blocked.empty? ? [] : [UI.paint("blocks #{blocked.join(", ")}", :cyan)]
      end

      # Dependency trouble under the plan's row. Every answer comes from
      # {Plans::Dependencies}; nothing about the graph is computed here.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<String>]
      def dependency_lines(subject)
        ordinal = subject.feature.ordinal
        deps = tree.dependencies
        notes = Plans::Spec.for(subject).problems.grep(/\Adepends_on/).map { |p| [p, :red] }
        deps.unknown(ordinal).each { |o| notes << ["depends_on: #{o} is not a plan in this tree", :red] }
        deps.closed(ordinal).each { |o| notes << ["depends_on: #{o} is already done, so the entry is ignored", :yellow] }
        cycle = deps.cycle_of(ordinal)
        notes << ["cycle: #{cycle.join(" → ")}", :red] if cycle

        notes.map { |text, colour| (" " * title_column) + UI.paint("↳ #{text}", colour) }
      end

      # The URL is left bare rather than wrapped in an OSC 8 hyperlink: the table
      # is as likely to be piped into a file as read in a terminal, and every
      # terminal worth the name linkifies a bare URL anyway.
      #
      # @param pr [OpenLanes::Plans::PullRequest]
      # @return [String]
      def link(pr)
        colour = state_colour(pr)

        format("#%4s %s %s",
          pr.number,
          UI.paint(UI.fit(pr.state, STATE_WIDTH), colour),
          UI.paint(pr.url.to_s, colour))
      end

      # @param pr [OpenLanes::Plans::PullRequest]
      # @return [Symbol] a pastel style name
      def state_colour(pr)
        if pr.merged?
          :magenta
        elsif pr.open?
          :yellow
        else
          :blue
        end
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<String>]
      def violation_line(subject)
        return [] if subject.consistent?

        [(" " * title_column) + UI.paint("↳ #{subject.violation}", :red)]
      end

      # @return [String]
      def footer
        counts = totals.map { |key, n| "#{Plans::STATUS_BY_KEY.fetch(key).emoji}  #{n}" }.join("   ")
        lines = ["  #{tree.subjects.size} #{tree.subjects.size == 1 ? "plan" : "plans"}   #{counts}"]

        unless inconsistent.empty?
          lines << "  #{UI.paint("#{inconsistent.size} with a status their contents do not justify", :red)}"
        end

        tree.duplicates.each do |ordinal, dirnames|
          lines << "  #{UI.paint("#{ordinal} is claimed by #{dirnames.size} folders — a number is an identity:", :red)}"
          dirnames.each { |d| lines << "    #{UI.paint(d, :bright_black)}" }
        end

        lines.join("\n")
      end
    end
  end
end
