# frozen_string_literal: true

module OpenLanes
  module Plans
    # A plan's number, and therefore its identity. Set once when the folder is
    # created and never changed: branch names, pull request titles and every
    # `pull-requests.md` join on it, and renumbering breaks all of them silently.
    #
    # Always rendered `NNN.MM`. `002.00` is an ordinary plan, specified before it
    # was built. `002.01` is retroactive — work that shipped between 002 and 003
    # and was documented afterwards. The decimal marks a **sibling**, not
    # containment: 002.01 is not part of 002.
    #
    # `000` is where the sequence starts, so the first plan of a project is
    # `000.00`. It also absorbs the older meaning — work that predates the plan
    # discipline — since either way it sorts first, which is where it belongs.
    #
    # @!attribute [r] major
    #   @return [Integer] 0..999
    # @!attribute [r] minor
    #   @return [Integer] 0..99; zero for an ordinary plan
    class Ordinal < Data.define(:major, :minor)
      include Comparable

      # The canonical form, plus the bare `NNN` that trees written before this
      # rule still use and must remain readable.
      PATTERN = /\A(\d{1,3})(?:\.(\d{1,2}))?\z/

      # The most retroactive slots a single gap can hold.
      MAX_MINOR = 99

      # @param text [String, nil] e.g. "3", "003", "003.00", "018.01"
      # @return [OpenLanes::Plans::Ordinal, nil] nil when it is not a plan number
      def self.parse(text)
        m = PATTERN.match(text.to_s.strip)
        m && new(major: m[1].to_i, minor: m[2].to_i)
      end

      # Pull the number off the front of a folder name.
      #
      # @param dirname [String] e.g. "018.01-✅--verify-against-filed-returns"
      # @return [OpenLanes::Plans::Ordinal, nil]
      def self.from_dirname(dirname) = parse(dirname.to_s[/\A[\d.]+/])

      # The next ordinary plan after everything in +existing+.
      #
      # The first plan in an empty tree is `000.00`, not `001.00`: the sequence
      # counts from zero so that the very first specification — usually the
      # project's own — sorts above everything and needs no gap reserved for it.
      #
      # @param existing [Array<OpenLanes::Plans::Ordinal>]
      # @return [OpenLanes::Plans::Ordinal]
      def self.next_major(existing)
        return new(major: 0, minor: 0) if existing.empty?

        new(major: existing.map(&:major).max + 1, minor: 0)
      end

      # The next retroactive slot in the gap after +major+.
      #
      # @param existing [Array<OpenLanes::Plans::Ordinal>]
      # @param major [Integer] the plan the work landed after
      # @return [OpenLanes::Plans::Ordinal]
      # @raise [OpenLanes::Error] when the gap is full
      def self.next_minor(existing, major:)
        taken = existing.select { |o| o.major == major }.map(&:minor).max || 0
        if taken >= MAX_MINOR
          raise Error, "all #{MAX_MINOR} retroactive slots after #{format("%03d", major)} are taken"
        end

        new(major:, minor: taken + 1)
      end

      # @return [Boolean] whether this plan was documented after the fact
      def retroactive? = minor.positive?

      # @return [String] the canonical `NNN.MM`
      def to_s = format("%03d.%02d", major, minor)

      # @return [String] what a pull request title carries
      def to_prefix = "[#{self}]"

      # @param other [Object]
      # @return [Integer, nil]
      def <=>(other)
        return nil unless other.is_a?(self.class)

        [major, minor] <=> [other.major, other.minor]
      end
    end
  end
end
