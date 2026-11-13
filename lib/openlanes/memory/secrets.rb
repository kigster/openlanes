# frozen_string_literal: true

module OpenLanes
  module Memory
    # What must never be committed under `.openlanes/`: keys, tokens,
    # passwords, private keys, URLs that carry credentials, and people's
    # email addresses.
    #
    # Memory is text an agent proposed, distilled from review findings and
    # answers a person typed, and it is committed and shown to every later
    # agent. An agent told "never write a secret" is a request; this scan is
    # the check, run before a candidate is written, again before it is
    # promoted, and over the whole folder in the suite.
    #
    # It errs toward refusing. A lesson that trips it is dropped and
    # reported, and a person can reword it; a key that slipped through is in
    # the history for good. A {Finding} names the kind and the line and never
    # the text that matched, so reporting one does not repeat the leak.
    module Secrets
      # One match.
      #
      # @!attribute [r] kind
      #   @return [String] what it looks like, e.g. "a private key"
      # @!attribute [r] line
      #   @return [Integer] 1-based
      Finding = Data.define(:kind, :line) do
        # @return [String]
        def to_s = "line #{line}: #{kind}"
      end

      # A long run of letters and digits that is not a commit id: 40 or more
      # characters with a lower-case letter, an upper-case letter and a digit.
      BLOB = %r{(?<![A-Za-z0-9+/_-])(?=[A-Za-z0-9+/_-]*[a-z])(?=[A-Za-z0-9+/_-]*[A-Z])(?=[A-Za-z0-9+/_-]*\d)[A-Za-z0-9+/_-]{40,}={0,2}}

      # Each shape, by what to call it. Vendor prefixes first, since they are
      # exact; the general shapes after.
      PATTERNS = {
        "a private key"                => /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
        "an Anthropic or OpenAI key"   => /\bsk-[A-Za-z0-9_-]{16,}/,
        "a GitHub token"               => /\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})/,
        "a GitLab token"               => /\bglpat-[A-Za-z0-9_-]{16,}/,
        "an AWS access key"            => /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/,
        "a Slack token"                => /\bxox[abprs]-[A-Za-z0-9-]{10,}/,
        "a Google API key"             => /\bAIza[0-9A-Za-z_-]{30,}/,
        "a Stripe key"                 => /\b[rs]k_(?:live|test)_[A-Za-z0-9]{16,}/,
        "a JSON web token"             => /\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\./,
        "a URL carrying credentials"   => %r{\b[a-z][a-z0-9+.-]*://[^/\s:@]+:[^/\s@]+@},
        "a key, token or password set to a value" =>
          /\b[\w-]*(?:api[_-]?key|secret|token|passw(?:or)?d|credential)s?["']?[ \t]*[:=][ \t]*["']?[^\s"'<>{}$]{8,}/i,
        "an email address"             => /(?<![\w.+-])(?!git@)[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b/,
        "a long random-looking string" => BLOB
      }.freeze

      module_function

      # @param text [String]
      # @return [Array<OpenLanes::Memory::Secrets::Finding>] in line order, one per kind per line
      def scan(text)
        text.to_s.scrub("?").each_line.with_index(1).flat_map do |line, number|
          PATTERNS.filter_map { |kind, pattern| Finding.new(kind:, line: number) if line.match?(pattern) }
        end
      end

      # @param text [String]
      # @return [Boolean]
      def clean?(text) = scan(text).empty?

      # Every file under +dir+ that holds something, by path.
      #
      # @param dir [String]
      # @return [Hash{String => Array<OpenLanes::Memory::Secrets::Finding>}] empty when the folder is clean or absent
      def scan_tree(dir)
        return {} unless File.directory?(dir)

        files = Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).map { File.join(dir, it) }.select { File.file?(it) && !File.symlink?(it) }
        files.sort.to_h { [it, scan(File.binread(it))] }.reject { |_, found| found.empty? }
      end
    end
  end
end
