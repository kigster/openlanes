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
      FIELDS = %w[number title url headRefName files state isDraft mergedAt labels].freeze

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
            open:   pr["mergedAt"].nil? && pr["state"].to_s.upcase == "OPEN",
            labels: Array(pr["labels"]).map { |l| l["name"] }
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
      VIEW_FIELDS = %w[number title url headRefName state isDraft mergedAt body labels].freeze

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
      # @return [Hash] `{number:, title:, url:, branch:, state:, open:, labels:, body:}`,
      #   the keys {#pulls} gives a row plus the body
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
          open:   pr["mergedAt"].nil? && pr["state"].to_s.upcase == "OPEN",
          labels: Array(pr["labels"]).map { |l| l["name"] },
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

      # Create a review label when the repository lacks it. Never `--force`:
      # this runs before every label swap, and recolouring is {LabelSync}'s
      # job, done once per run where the change is announced, not as a side
      # effect of labelling one pull request.
      #
      # @param label [Plans::ReviewLabel]
      # @param repo [String, nil] "owner/repo"; nil means the current checkout's
      # @return [void]
      # @raise [OpenLanes::Error]
      def ensure_label(label, repo: nil)
        @command.run("gh",
          "label",
          "create",
          label.name,
          "--color",
          label.colour,
          "--description",
          label.meaning,
          *repo_flag(repo))
      rescue TTY::Command::ExitError => e
        return if e.message.match?(/already exists/i)

        raise Error, "could not create label #{label.name}: #{first_line(e)}"
      end

      # Every label the repository has, and its colour.
      #
      # @param repo [String, nil]
      # @return [Hash{String => String}] name to colour, lower-case hex without `#`
      # @raise [OpenLanes::Error]
      def label_colours(repo: nil)
        out = @command.run("gh", "label", "list", "--limit", "1000", "--json", "name,color", *repo_flag(repo)).out
        JSON.parse(out).to_h { [it["name"].to_s, it["color"].to_s.downcase] }
      # A machine without `gh` (a CI image, say) is a reason to skip the sync,
      # not to stop the run: {LabelSync}'s caller warns on Error.
      rescue TTY::Command::ExitError, JSON::ParserError, SystemCallError => e
        raise Error, "could not list labels: #{first_line(e)}"
      end

      # Give an existing label its colour and description back (R3). Only
      # {LabelSync} calls this, and only for the labels openlanes owns.
      #
      # @param label [Plans::ReviewLabel]
      # @param repo [String, nil]
      # @return [void]
      # @raise [OpenLanes::Error]
      def recolour_label(label, repo: nil)
        @command.run("gh",
          "label",
          "edit",
          label.name,
          "--color",
          label.colour,
          "--description",
          label.meaning,
          *repo_flag(repo))
      rescue TTY::Command::ExitError => e
        raise Error, "could not recolour label #{label.name}: #{first_line(e)}"
      end

      # Put one label on a pull request and take others off, in one edit.
      #
      # @param number [Integer]
      # @param repo [String, nil]
      # @param add [Plans::ReviewLabel]
      # @param remove [Array<String>] label names to take off
      # @return [Array<String>] the labels the pull request is left with
      # @raise [OpenLanes::Error]
      def swap_label(number:, add:, repo: nil, remove: [])
        ensure_label(add, repo:)
        removing = remove.map(&:to_s) - [add.name]
        begin
          edit_labels(number, add, removing, repo)
        rescue Error
          raise if removing.empty?

          # Removing a label the pull request does not carry fails the whole
          # edit (open question 6). Adding alone would leave any of `removing`
          # it does carry beside the new one, two verdicts at once, so ask what
          # is still there and take exactly that off. A second failure is real.
          edit_labels(number, add, labels(number:, repo:) & removing, repo)
        end
        labels(number:, repo:)
      end

      # @param number [Integer]
      # @param repo [String, nil]
      # @return [Array<String>] label names on the pull request
      def labels(number:, repo: nil)
        out = @command.run("gh", "pr", "view", number.to_s, "--json", "labels", *repo_flag(repo)).out
        Array(JSON.parse(out)["labels"]).map { |l| l["name"] }
      rescue TTY::Command::ExitError, JSON::ParserError => e
        raise Error, "could not read labels of ##{number}: #{first_line(e)}"
      end

      # @param number [Integer]
      # @param repo [String, nil]
      # @return [Array<Hash>] `{name:, bucket:}`, bucket as `gh` reports it
      def checks(number:, repo: nil)
        # `gh pr checks` exits non-zero when a check failed or is pending, and
        # the JSON it printed is still the answer, so its status is no verdict.
        result = @command.run!("gh", "pr", "checks", number.to_s, "--json", "name,state,bucket", *repo_flag(repo))
        out = result.out.to_s
        if out.strip.empty?
          return [] if result.success? || result.err.to_s.match?(/no checks reported/i)

          raise Error, "could not read checks of ##{number}: #{result.err.to_s.lines.first.to_s.strip}"
        end

        JSON.parse(out).map { |c| { name: c["name"].to_s, bucket: c["bucket"].to_s } }
      rescue JSON::ParserError => e
        raise Error, "could not read checks of ##{number}: #{e.message.lines.first.to_s.strip}"
      end

      # @param number [Integer]
      # @param repo [String, nil]
      # @return [Array<Hash>] `{author:, body:, url:}`, conversation comments then reviews
      def review_comments(number:, repo: nil)
        out = @command.run("gh", "pr", "view", number.to_s, "--json", "comments,reviews", *repo_flag(repo)).out
        data = JSON.parse(out)
        (Array(data["comments"]) + Array(data["reviews"])).filter_map do |c|
          next if c["body"].to_s.strip.empty?

          { author: c.dig("author", "login").to_s, body: c["body"].to_s, url: c["url"].to_s }
        end
      rescue TTY::Command::ExitError, JSON::ParserError => e
        raise Error, "could not read comments of ##{number}: #{first_line(e)}"
      end

      # @param url [String] a pull request URL
      # @return [String, nil] "owner/repo", or nil when the URL is not GitHub's
      def self.repo_of(url) = url.to_s[%r{github\.com/([^/]+/[^/]+)/pull/}, 1]

      # The number a pull request reference names: the `/pull/N` segment of a
      # URL, or a bare or `#`-prefixed number. Never "the trailing digits",
      # which read `…/pull/7#issuecomment-1234` as #1234 and relabel a
      # different pull request.
      #
      # @param ref [String, Integer] "12", "#12" or a pull request URL
      # @return [Integer]
      # @raise [OpenLanes::Error] when `ref` names no pull request
      def self.number_of(ref)
        text = ref.to_s.strip
        found = text[%r{\Ahttps?://\S+?/(?:pull|merge_requests)/(\d+)(?:[/?#]\S*)?\z}, 1] || text[/\A#?(\d+)\z/, 1]
        raise Error, "not a pull request number or URL: #{ref}" unless found

        found.to_i
      end

      # @return [Boolean] whether `gh` is installed and authenticated
      def available?
        @command.run!("gh", "auth", "status").success?
      end

      private

      def repo_flag(repo) = repo ? ["-R", repo] : []

      # The first line `gh` wrote to stderr, which is the one naming the problem.
      def first_line(error)
        stderr = error.message[/stderr: (.*)/, 1].to_s.strip
        stderr.empty? ? error.message.lines.first.to_s.strip : stderr
      end

      def edit_labels(number, add, removing, repo)
        @command.run("gh",
          "pr",
          "edit",
          number.to_s,
          "--add-label",
          add.name,
          *removing.flat_map { |r| ["--remove-label", r] },
          *repo_flag(repo))
      rescue TTY::Command::ExitError => e
        raise Error, "could not label ##{number}: #{first_line(e)}"
      end
    end
  end
end
