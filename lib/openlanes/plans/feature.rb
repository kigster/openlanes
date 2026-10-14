# frozen_string_literal: true

require "date"

module OpenLanes
  module Plans
    # Lowercase in the middle of a title, capitalised at the front.
    SMALL_WORDS = %w[a an and as at but by for from in into nor of on or per the to via vs with].freeze

    # Slug words that are really acronyms and should shout.
    ACRONYMS = %w[
      abac ai api aws cdn ci cd cli cms cors cpu crm css csv db dns dsl e2e ec2 etl gcp gdpr gpu gui
      html http https iam id ide jwt json k8s llm ml mcp mvp npm oauth orm otp pdf pii poc pr prs qa
      rbac rds rest rls rpc rss s3 saas sdk seo sns spa sql sqs sre ssh sso ssl ssr tls tui ts tsx ui
      ux uuid vpc vpn xml yaml
    ].freeze

    # Words with a house spelling that neither capitalize nor upcase gets right.
    SPECIAL_CASE = {
      "github" => "GitHub", "gitlab" => "GitLab", "graphql" => "GraphQL", "ios" => "iOS",
      "javascript" => "JavaScript", "macos" => "macOS", "nodejs" => "Node.js", "oauth" => "OAuth",
      "openai" => "OpenAI", "postgres" => "PostgreSQL", "postgresql" => "PostgreSQL",
      "typescript" => "TypeScript", "uuidv7" => "UUIDv7", "websocket" => "WebSocket"
    }.freeze

    # Turn a kebab slug into a proper name: `law-as-data` → "Law as Data".
    #
    # @param slug [String]
    # @return [String]
    def self.titleize(slug)
      words = slug.to_s.split(/[-_\s.]+/).reject(&:empty?)
      return "" if words.empty?

      words.each_with_index.map { |word, i|
        lower = word.downcase
        if SPECIAL_CASE.key?(lower)
          SPECIAL_CASE[lower]
        elsif ACRONYMS.include?(lower)
          lower.upcase
        elsif i.positive? && SMALL_WORDS.include?(lower)
          lower
        elsif lower.match?(/\A\d+\z/)
          lower
        else
          lower.sub(/\A./, &:upcase)
        end
      }.join(" ")
    end

    # The heavy rule between the parts of a folder name. No space anywhere, so
    # a name needs no quoting in a shell, and nothing an emoji can swallow.
    RULE = "━━"

    # What points from the state to the slug.
    POINTER = "❯"

    # The one place a plan folder's name is spelled out (decision N1):
    # `NNN.MM━━<emoji>━━❯<slug>`, or `NNN.MM━━<emoji>━━❯[YYYY-MM-DD]━━<slug>`
    # once the plan has been moved into an inactive subfolder (N3).
    #
    # The earlier `NNN.MM-<emoji> → <slug>` put a space in every name, and the
    # `--` before it let a two-cell emoji swallow the dash beside it.
    # Everything that mints or renames a folder goes through here; {Feature.parse}
    # still reads every older spelling, and `resync dirs` migrates them.
    #
    # @param ordinal [OpenLanes::Plans::Ordinal, String]
    # @param status [OpenLanes::Plans::Status]
    # @param slug [String]
    # @param archived_on [Date, nil] the date the plan was moved aside
    # @return [String]
    def self.plan_dirname(ordinal, status, slug, archived_on: nil)
      date = archived_on && "[#{archived_on.strftime("%F")}]#{RULE}"
      "#{ordinal}#{RULE}#{status.emoji}#{RULE}#{POINTER}#{date}#{slug}"
    end

    # The current spelling, with or without the archive date.
    CURRENT_FORM = /\A[\d.]+#{RULE}(?<emoji>[^━]+)#{RULE}#{POINTER}(?:\[(?<date>\d{4}-\d{2}-\d{2})\]#{RULE})?(?<slug>.+)\z/

    # One plan folder, decoded.
    #
    # @!attribute [r] ordinal
    #   @return [OpenLanes::Plans::Ordinal]
    # @!attribute [r] status
    #   @return [OpenLanes::Plans::Status]
    # @!attribute [r] slug
    #   @return [String]
    # @!attribute [r] dirname
    #   @return [String] exactly as it is on disk
    # @!attribute [r] path
    #   @return [String] absolute
    # @!attribute [r] archived_on
    #   @return [Date, nil] the date in the name of a plan moved aside, else nil
    Feature = Data.define(:ordinal, :status, :slug, :dirname, :path, :archived_on) do
      include Comparable

      # @param archived_on [Date, nil] optional, so callers that predate it still build one
      def initialize(archived_on: nil, **) = super

      # Decode a folder name, or return nil when it is not a plan folder.
      #
      # @param path [String] absolute path to a candidate directory
      # @return [OpenLanes::Plans::Feature, nil]
      def self.parse(path)
        dirname = File.basename(path)
        ordinal = Ordinal.from_dirname(dirname) or return nil

        current(dirname, ordinal, path) || legacy(dirname, ordinal, path)
      end

      # `NNN.MM━━<emoji>━━❯<slug>`, dated or not.
      #
      # @return [OpenLanes::Plans::Feature, nil]
      def self.current(dirname, ordinal, path)
        m = CURRENT_FORM.match(dirname) or return nil
        status = OpenLanes::Plans.status_for_emoji(m[:emoji]) or return nil
        archived_on = m[:date] && Date.iso8601(m[:date], exception: false)

        new(ordinal:, status:, slug: m[:slug], dirname:, path:, archived_on:)
      end

      # `NNN.MM-<emoji> → <slug>`, `NNN-<emoji>--<slug>` and `NNN-<emoji>-<slug>`.
      #
      # @return [OpenLanes::Plans::Feature]
      def self.legacy(dirname, ordinal, path)
        rest = dirname.sub(/\A[\d.]+[-_]/, "")
        head, tail = rest.split(/\s*→\s*|[-_]/, 2)

        # A leading segment with no ASCII word character is the status emoji.
        # The slug strips any further separators: the arrow spelling put a
        # spaced arrow after the emoji, and folders from before that put two
        # dashes, or one.
        status = (OpenLanes::Plans.status_for_emoji(head) if tail && !head.to_s.empty? && !head.match?(/[A-Za-z0-9]/))
        slug = status ? tail.sub(/\A[-_\s]+/, "") : rest

        new(ordinal:, status: status || STATUS_BY_KEY.fetch(:new), slug:, dirname:, path:)
      end
      private_class_method :current, :legacy

      # @return [String] proper name, e.g. "Law as Data"
      def title = OpenLanes::Plans.titleize(slug)

      # The folder name this feature would carry in a given state — the slug
      # and any archive date never move, and the number is always rendered
      # canonically, so this is also what repairs a folder written
      # `018-⚪️--foo` before the `NNN.MM` rule.
      #
      # @param status [OpenLanes::Plans::Status]
      # @param archived_on [Date, nil] defaults to the date the name carries now
      # @return [String]
      def dirname_as(status, archived_on: self.archived_on)
        OpenLanes::Plans.plan_dirname(ordinal, status, slug, archived_on:)
      end

      # The number exactly as the folder writes it, which is not always the
      # canonical rendering: `018-⚪️--foo` yields "018" where {#ordinal} renders
      # "018.00".
      #
      # @return [String]
      def dirname_ordinal = dirname.to_s[/\A[\d.]+/].to_s

      # @return [Boolean] whether the number is written in full `NNN.MM` form
      def padded? = dirname_ordinal == ordinal.to_s

      # Whether the folder is already named the way this tool would name it —
      # number padded, emoji matching the state it claims, slug unchanged.
      #
      # @return [Boolean]
      def canonical? = dirname == dirname_as(status)

      # @param other [Object]
      # @return [Integer, nil]
      def <=>(other) = other.is_a?(self.class) ? [ordinal, dirname] <=> [other.ordinal, other.dirname] : nil
    end
  end
end
