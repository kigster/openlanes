# frozen_string_literal: true

require "cgi"
require "erb"

module OpenLanes
  module Plans
    # `openlanes index` — the project's plans as one browsable page.
    #
    # {Reporter} answers "what is the state of things" in a terminal, in columns,
    # for someone standing at a prompt. This answers "what is this project, and
    # where is everything" for someone arriving at the repository on the web: the
    # goal of each plan in its own words, every pull request as a link, and every
    # document in the folder one click away.
    #
    # It is generated for the same reason the conventions document is. A
    # hand-written index of twenty plans cannot survive a rename, and renaming is
    # exactly what `resync dirs` exists to do — the first hand-made INDEX.md this
    # replaced had all 82 of its links pointing at folder names that had been
    # padded to `NNN.MM` underneath it.
    class Index
      # The file this writes, relative to the `.plans` directory.
      FILENAME = "INDEX.md"

      # Documents that get a proper name rather than their filename.
      ARTIFACT_NAMES = {
        "spec.md"          => "Spec",
        "plan.md"          => "Plan",
        "pull-requests.md" => "Pull Requests",
        "linear.md"        => "Linear",
        "blocked.md"       => "Blocked",
        "delayed.md"       => "Deferred",
        "rewrite.md"       => "Rewrite",
        "deployed.md"      => "Deployed",
        "rollback.md"      => "Rollback",
        "discarded.md"     => "Discarded"
      }.freeze

      # @param tree [OpenLanes::Plans::Tree]
      # @param project [String, nil] the heading; defaults to the repository name
      def initialize(tree:, project: nil)
        @tree = tree
        @project = project
      end

      # @return [OpenLanes::Plans::Tree]
      attr_reader :tree

      # @return [String] the project's name, titleized from its directory
      def project = @project ||= OpenLanes::Plans.titleize(File.basename(File.dirname(tree.dir)))

      # @return [String] the whole document
      def render
        [heading, *tree.subjects.map { |subject| section(subject) }].join("\n") + footer
      end

      # Write it next to the plans it describes.
      #
      # @param path [String, nil] override the destination
      # @return [String] where it was written
      def write(path = nil)
        path ||= File.join(tree.dir, FILENAME)
        File.write(path, render)
        path
      end

      private

      # @return [String]
      def heading
        <<~MARKDOWN
          # Project #{project}

          > [!IMPORTANT]
          > **This file is auto generated.** To regenerate it, run `openlanes index`.
          > Editing it by hand lasts until the next `resync dirs` renames a folder.

          ## Current specifications and their status

        MARKDOWN
      end

      # One plan: a heading that carries its number and state, then a table.
      #
      # Raw HTML rather than a markdown table because the cells are not one-liners
      # — a goal is a paragraph or two and a plan may have a dozen pull requests,
      # neither of which a pipe-delimited row can hold.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [String]
      def section(subject)
        feature = subject.feature

        <<~MARKDOWN
          ## #{feature.ordinal} — #{feature.status.emoji} #{escape(feature.title)}

          <table>
            <thead>
              <tr>
                <th align="left">Status</th>
                <th align="left">Pull Requests</th>
                <th align="left">What it is</th>
                <th align="left">Artifacts</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td valign="top">#{status_cell(subject)}</td>
                <td valign="top">#{pulls_cell(subject)}</td>
                <td valign="top">#{goal_cell(subject)}</td>
                <td valign="top">#{artifacts_cell(feature)}</td>
              </tr>
            </tbody>
          </table>

        MARKDOWN
      end

      # The emoji and the words, kept on one line — a status that wraps mid-label
      # makes the column look like two states rather than one.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [String]
      def status_cell(subject)
        cell = "#{subject.status.emoji}&nbsp;#{escape(subject.status.label)}"
        return cell if subject.consistent?

        "#{cell}<br><sub>⚠️ #{escape(subject.violation)}</sub>"
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [String]
      def pulls_cell(subject)
        prs = subject.pull_requests
        return "<em>—</em>" if prs.empty?

        items = prs.map { |pr|
          "<li>#{link(pr.url, pr.label)} #{escape(pr.state)}</li>"
        }
        "<ul>#{items.join}</ul>"
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [String]
      def goal_cell(subject)
        paragraphs = subject.goal
        return "<em>No specification yet.</em>" if paragraphs.empty?

        paragraphs.map { |p| "<p>#{inline(p)}</p>" }.join
      end

      # Markdown inside a raw HTML block is not parsed — GitHub stops parsing
      # markdown the moment it sees a block-level tag — so a goal quoted verbatim
      # would show its own `**` and backticks. Only the three that carry meaning
      # are translated; single-underscore emphasis is deliberately left alone,
      # because `deleted_at` is more common in these documents than italics.
      #
      # @param text [String] markdown, unescaped
      # @return [String] HTML
      def inline(text)
        escape(text)
          .gsub(/\[([^\]]+)\]\((https?:[^)\s]+)\)/) { %(<a href="#{$2}">#{$1}</a>) }
          .gsub(/\*\*([^*]+)\*\*/) { "<strong>#{$1}</strong>" }
          .gsub(/`([^`]+)`/) { "<code>#{$1}</code>" }
          .tr("\n", " ")
      end

      # Every document in the folder, linked. The folder name is percent-encoded
      # because it contains an emoji, and a raw one in an href is a broken link
      # on GitHub.
      #
      # @param feature [OpenLanes::Plans::Feature]
      # @return [String]
      def artifacts_cell(feature)
        files = Dir.children(feature.path).select { |f| File.file?(File.join(feature.path, f)) }
        return "<em>empty</em>" if files.empty?

        # The documents that carry the lifecycle come first, in lifecycle order;
        # whatever else the folder holds follows alphabetically.
        known = ARTIFACT_NAMES.keys
        files = files.sort_by { |f| [known.index(f) || known.size, f] }

        items = files.map { |file|
          href = "#{ERB::Util.url_encode(feature.dirname)}/#{ERB::Util.url_encode(file)}"
          "<li>#{link(href, ARTIFACT_NAMES.fetch(file, file))}</li>"
        }
        "<ul>#{items.join}</ul>"
      end

      # @return [String]
      def footer
        counts = tree.subjects.each_with_object(Hash.new(0)) { |s, h| h[s.status] += 1 }
                     .map { |status, n| "#{status.emoji} #{n}" }.join(" &nbsp; ")

        "\n---\n\n#{tree.subjects.size} #{tree.subjects.size == 1 ? "plan" : "plans"} &nbsp; #{counts}\n"
      end

      # @param href [String]
      # @param text [String]
      # @return [String]
      def link(href, text) = %(<a href="#{escape(href)}">#{escape(text)}</a>)

      # @param text [String]
      # @return [String]
      def escape(text) = CGI.escapeHTML(text.to_s)
    end
  end
end
