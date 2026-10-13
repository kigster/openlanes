# frozen_string_literal: true

require "digest"

module OpenLanes
  module Linear
    # One row of a plan's `linear.md`: an issue this tool has already pushed.
    #
    # @!attribute [r] unit
    #   @return [String] the {Unit#key} it was made from
    # @!attribute [r] identifier
    #   @return [String] "TAX-41" — Linear resolves this as an id
    # @!attribute [r] url
    #   @return [String, nil]
    # @!attribute [r] title
    #   @return [String] as pushed
    # @!attribute [r] state
    #   @return [String] as pushed
    # @!attribute [r] digest
    #   @return [String] fingerprint of the payload as pushed
    Issue = Data.define(:unit, :identifier, :url, :title, :state, :digest)

    # A plan's record of what it has put into Linear.
    #
    # Without it, a second `linear import` cannot tell an issue it created
    # last week from one it has never created, and the only two outcomes are
    # duplicating everything or searching Linear by title on every run. The
    # file is the memory, and it is a committed artifact rather than a dotfile
    # so the record travels with the plan and shows up in review.
    #
    # The `Synced` column is what makes an update cheap to decide: it is a
    # digest of the payload last pushed, so a run can tell — with no network
    # at all — whether anything about this issue has changed since. A digest
    # that no longer matches is the whole trigger for an update.
    class Issues
      # The file this reads and writes.
      FILENAME = "linear.md"

      # The unit key given to the issue that stands for the whole folder. Its
      # children carry their own unit keys; it carries this, so one table can
      # hold a plan and its parts without a second shape to parse.
      PARENT = "PLAN"

      # Fingerprint of a payload, short enough to read in a table.
      #
      # @param payload [Object] anything with a stable #inspect ordering
      # @return [String] eight hex characters
      def self.digest(payload) = ::Digest::SHA256.hexdigest(JSON.generate(payload))[0, 8]

      # @param team [String] the team key, e.g. "TAX"
      # @param project [Hash, nil] `{name:, url:}`
      # @param issues [Array<OpenLanes::Linear::Issue>]
      # @return [String]
      def self.render(team:, project:, issues:)
        rows = order(issues).map { |i|
          "| #{i.unit} | #{link(i.identifier, i.url)} | #{escape(i.title)} | #{i.state} | #{i.digest} |"
        }

        <<~MARKDOWN
          # Linear

          #{heading(team, project)}

          | Unit | Issue | Title | State | Synced |
          | :--- | :---- | :---- | ----: | :----- |
          #{rows.join("\n")}

          <!-- Written by `openlanes linear import`. Do not hand-edit the
               Synced column: it fingerprints what was last pushed, and a row whose
               fingerprint no longer matches the plan is what triggers an update. -->
        MARKDOWN
      end

      # The folder's own issue first, then its children. A table that opens
      # with a child reads as a list of unrelated issues.
      #
      # @param issues [Array<OpenLanes::Linear::Issue>]
      # @return [Array<OpenLanes::Linear::Issue>]
      def self.order(issues)
        parent, children = issues.partition { |i| i.unit == PARENT }
        parent + children
      end

      # @param team [String]
      # @param project [Hash, nil]
      # @return [String]
      def self.heading(team, project)
        return "Team **#{team}**." unless project

        "Team **#{team}** · project #{link(project[:name], project[:url])}"
      end

      # @param text [String]
      # @param url [String, nil]
      # @return [String]
      def self.link(text, url) = url ? "[#{escape(text)}](#{url})" : escape(text)

      # @param text [String]
      # @return [String]
      def self.escape(text) = text.to_s.gsub("|", "\\|").gsub(/\s+/, " ").strip

      # @param dir [String] absolute path to the plan folder
      def initialize(dir:)
        @dir = dir
      end

      # @return [Array<OpenLanes::Linear::Issue>] possibly empty
      def all = @all ||= parse

      # @return [Hash{String => OpenLanes::Linear::Issue}] keyed by unit
      def by_unit = @by_unit ||= all.to_h { |issue| [issue.unit, issue] }

      # The project this plan was last filed under, if any.
      #
      # @return [Hash, nil] `{name:, url:}`
      def project = (@project ||= [parse_project])[0]

      # The issue standing for the folder itself.
      #
      # @return [OpenLanes::Linear::Issue, nil]
      def parent = by_unit[PARENT]

      # @return [String] absolute path to `linear.md`
      def path = File.join(dir, FILENAME)

      # @return [Boolean]
      def exist? = File.file?(path)

      # @param team [String]
      # @param project [Hash, nil]
      # @param issues [Array<OpenLanes::Linear::Issue>]
      # @return [String] the path written
      def write(team:, project:, issues:)
        File.write(path, self.class.render(team:, project:, issues:))
        @all = @by_unit = @project = nil
        path
      end

      private

      # @return [String]
      attr_reader :dir

      # @return [String]
      def text = @text ||= exist? ? File.read(path, encoding: "UTF-8") : ""

      # @return [Array<OpenLanes::Linear::Issue>]
      def parse
        table = Markdown.tables(text).find { |t|
          t[:header].any? { |h| h.match?(/\Aissue\z/i) } && t[:header].any? { |h| h.match?(/\Aunit\z/i) }
        }
        return [] unless table

        index = table[:header].each_with_index.to_h { |h, i| [h.downcase.strip, i] }
        table[:rows].filter_map { |cells| row_to_issue(cells, index) }
      end

      # @param cells [Array<String>]
      # @param index [Hash{String => Integer}]
      # @return [OpenLanes::Linear::Issue, nil]
      def row_to_issue(cells, index)
        cell = ->(name) { cells[index[name]].to_s }
        link = cell["issue"].match(/\[([^\]]+)\]\((\S+?)\)/)
        identifier = (link ? link[1] : cell["issue"]).gsub(/[*_`]/, "").strip
        return nil if identifier.empty?

        Issue.new(unit: cell["unit"].strip,
          identifier:,
          url: link && link[2],
          title: cell["title"].gsub(/\\([|\\])/, '\1').strip,
          state: cell["state"].strip,
          digest: cell["synced"].gsub(/[`\s]/, ""))
      end

      # @return [Hash, nil]
      def parse_project
        line = text.lines.find { |l| l.match?(/project\s+\[/i) }
        return nil unless line

        link = line.match(/project\s+\[([^\]]+)\]\((\S+?)\)/i)
        return nil unless link

        { name: link[1].strip.gsub(/\\([|\\])/, '\1'), url: link[2] }
      end
    end
  end
end
