# frozen_string_literal: true

require "json"
require "tty/command"

module OpenLanes
  module Vcs
    # The `gh` CLI, wrapped thinly.
    #
    # It is a seam rather than a convenience: every example in the suite injects
    # a double here, so nothing in the tests reaches the network or a real
    # repository.
    class GitHub
      # Fields asked of `gh pr list`.
      FIELDS = %w[number title url headRefName files state isDraft mergedAt].freeze

      # @param command [TTY::Command] runner, injectable for tests
      # @param limit [Integer] how many pull requests to fetch
      def initialize(command: TTY::Command.new(printer: :null), limit: 200)
        @command = command
        @limit = limit
      end

      # Every pull request, normalised into plain hashes.
      #
      # @param state [String] "open", "closed", "merged" or "all"
      # @return [Array<Hash>] `{number:, title:, url:, branch:, files:}`
      def pulls(state: "all")
        out = UI.spinning("Fetching pull requests from GitHub") {
          @command.run("gh",
            "pr",
            "list",
            "--state",
            state,
            "--limit",
            @limit.to_s,
            "--json",
            FIELDS.join(",")).out
        }

        # `gh` can exit 0 having printed NOTHING — most often when it cannot reach
        # the credential store, as in a non-interactive shell that has no keyring
        # access, or when GH_TOKEN is set to something invalid and shadows a
        # working login. Left alone this parses as a JSON error and reports as
        # "bad output", sending you to look at the wrong thing entirely.
        raise Error, no_output_message if out.to_s.strip.empty?

        JSON.parse(out).map do |pr|
          {
            number: pr["number"],
            title:  pr["title"].to_s,
            url:    pr["url"],
            branch: pr["headRefName"].to_s,
            files:  Array(pr["files"]).map { |f| f["path"] }.compact,
            state:  self.class.state_label(pr),
            open:   pr["mergedAt"].nil? && pr["state"].to_s.upcase == "OPEN"
          }
        end
      rescue TTY::Command::ExitError, JSON::ParserError => e
        raise Error, "could not list pull requests via `gh`: #{e.message.lines.first.to_s.strip}"
      end

      # @return [String] the diagnosis for a silent `gh`
      def no_output_message
        <<~MESSAGE.strip
          `gh` produced no output and did not report an error.

          That is almost always authentication rather than an empty repository:

            - Check `gh auth status`. An invalid GH_TOKEN in the environment
              shadows a working keyring login and fails without saying so.

            - A non-interactive shell may have no access to the system keyring
              even when an interactive one does.

          Verify with: gh pr list --state all --limit 1
        MESSAGE
      end

      # Fields asked of `gh pr view`, which unlike `pr list` can be told about
      # one pull request in another repository.
      VIEW_FIELDS = %w[number title url headRefName state isDraft mergedAt body].freeze

      # A reference to one pull request: a bare number, a `#`-prefixed number,
      # or a full URL to a GitHub pull request or a GitLab merge request.
      REF = %r{\A(?:\#?\d+|https?://\S+?/(?:pull|merge_requests)/\d+/?)\z}

      # Split and validate a `--prs` value before any of it reaches the network,
      # so a typo fails in a hundredth of a second with the offending token named
      # rather than after four round trips with a `gh` diagnostic.
      #
      # @param text [String] e.g. "12,15,18" or "https://…/pull/12, #15"
      # @return [Array<String>] references, in the order given, de-duplicated
      # @raise [OpenLanes::Error] on anything that is not a reference
      def self.parse_refs(text)
        refs = text.to_s.split(",").map(&:strip).reject(&:empty?)
        raise Error, "no pull requests given" if refs.empty?

        bad = refs.reject { |r| r.match?(REF) }
        unless bad.empty?
          raise Error, "not a pull request number or URL: #{bad.join(", ")}"
        end

        refs.uniq
      end

      # One pull request, by number or URL.
      #
      # @param ref [String] "12", "#12" or "https://github.com/o/r/pull/12"
      # @return [Hash] `{number:, title:, url:, branch:, state:, body:}`
      # @raise [OpenLanes::Error]
      def pull_request(ref)
        out = @command.run("gh", "pr", "view", ref.to_s, "--json", VIEW_FIELDS.join(",")).out
        raise Error, no_output_message if out.to_s.strip.empty?

        pr = JSON.parse(out)
        {
          number: pr["number"],
          title:  pr["title"].to_s,
          url:    pr["url"].to_s,
          branch: pr["headRefName"].to_s,
          state:  self.class.state_label(pr),
          body:   pr["body"].to_s
        }
      rescue TTY::Command::ExitError, JSON::ParserError => e
        raise Error, "could not read pull request #{ref}: #{e.message.lines.first.to_s.strip}"
      end

      # Several pull requests, in the order asked for.
      #
      # @param refs [Array<String>]
      # @return [Array<Hash>]
      def pull_requests(refs)
        UI.stepping(refs, "Fetching pull requests") { |ref| ref }
        refs.map { |ref| pull_request(ref) }
      end

      # `gh` speaks in enums; `pull-requests.md` speaks in the words the state
      # machine parses. Translate once, here, rather than at each call site.
      #
      # @param pr [Hash] a decoded `gh pr view` payload
      # @return [String] one of the labels in {PullRequests::STATES}
      def self.state_label(pr)
        return "Merged 🟣" if pr["mergedAt"]
        return "WIP 🟡" if pr["isDraft"]

        case pr["state"].to_s.upcase
        when "OPEN" then "Open 🟡"
        when "CLOSED" then "Closed 🔴"
        else "Unknown"
        end
      end

      # Change a pull request's title.
      #
      # @param number [Integer]
      # @param title [String]
      # @return [void]
      def retitle(number:, title:)
        @command.run("gh", "pr", "edit", number.to_s, "--title", title)
      rescue TTY::Command::ExitError => e
        raise Error, "could not retitle ##{number}: #{e.message.lines.first.to_s.strip}"
      end

      # @return [Boolean] whether `gh` is installed and authenticated
      def available?
        @command.run!("gh", "auth", "status").success?
      end
    end
  end
end
