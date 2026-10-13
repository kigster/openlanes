# frozen_string_literal: true

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

    # The one place a plan folder's name is spelled out: `NNN.MM-<emoji> → <slug>`.
    #
    # The spaced arrow after the emoji is deliberate: an emoji renders two cells
    # wide and visually swallows a bare dash beside it, so `🔎-refactor` reads
    # as if the emoji and the slug were touching. Everything that mints or
    # renames a folder goes through here; {Feature.parse} accepts the older
    # `--` and single-dash spellings too, and `resync dirs` migrates them on
    # contact.
    #
    # @param ordinal [OpenLanes::Plans::Ordinal, String]
    # @param status [OpenLanes::Plans::Status]
    # @param slug [String]
    # @return [String]
    def self.plan_dirname(ordinal, status, slug) = "#{ordinal}-#{status.emoji} → #{slug}"

    # One `NNN.MM-<emoji> → <slug>` folder, decoded.
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
    Feature = Data.define(:ordinal, :status, :slug, :dirname, :path) do
      include Comparable

      # Decode a folder name, or return nil when it is not a plan folder.
      #
      # @param path [String] absolute path to a candidate directory
      # @return [OpenLanes::Plans::Feature, nil]
      def self.parse(path)
        dirname = File.basename(path)
        ordinal = Ordinal.from_dirname(dirname) or return nil

        rest = dirname.sub(/\A[\d.]+[-_]/, "")
        head, tail = rest.split(/\s*→\s*|[-_]/, 2)

        # A leading segment with no ASCII word character is the status emoji.
        # The slug strips any further separators: the canonical spelling puts
        # a spaced arrow after the emoji, and folders from before that rule put
        # two dashes, or one.
        status = (OpenLanes::Plans.status_for_emoji(head) if tail && !head.to_s.empty? && !head.match?(/[A-Za-z0-9]/))
        slug = status ? tail.sub(/\A[-_\s]+/, "") : rest

        new(ordinal:, status: status || STATUS_BY_KEY.fetch(:new), slug:, dirname:, path:)
      end

      # @return [String] proper name, e.g. "Law as Data"
      def title = OpenLanes::Plans.titleize(slug)

      # The folder name this feature would carry in a given state — the slug
      # never moves, and the number is always rendered canonically, so this is
      # also what repairs a folder written `018-⚪️--foo` before the `NNN.MM` rule.
      #
      # @param status [OpenLanes::Plans::Status]
      # @return [String]
      def dirname_as(status) = OpenLanes::Plans.plan_dirname(ordinal, status, slug)

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
