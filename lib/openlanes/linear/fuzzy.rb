# frozen_string_literal: true

require "fuzzystringmatch"

module OpenLanes
  module Linear
    # How alike two short strings are, on a scale rather than a yes or no.
    #
    # Counting shared words gives whole numbers, and whole numbers tie. Three
    # folders scoring 2 against the same pull request is not three good
    # answers — it is no answer — but a tie has to be *detected* to be
    # refused, and with a coarse enough score everything ties.
    #
    # Jaro-Winkler grades instead, and it is the right measure for these
    # inputs: it is built for short strings, and its prefix bonus is exactly
    # the shape of the errors here — a word and its inflection agree from the
    # front and diverge at the end.
    module Fuzzy
      module_function

      # Two words count as the same word above this.
      #
      # Calibrated rather than chosen. The prefix bonus that makes
      # `rounding`/`round` (0.938) work also lifts `plaid`/`plain` (0.920) and
      # `state`/`statement` (0.926), which are different words that would
      # wrongly file a pull request. 0.93 is the gap between those two groups.
      # It costs `corpus`/`corpora` (0.848), which is rarer than either.
      AKIN = 0.93

      # Deliberately the pure-Ruby implementation. The native one needs a C
      # extension that does not build everywhere — it fails on this machine
      # over a jemalloc header — and asking for it prints a compile warning to
      # STDERR on every single load, which would land in the middle of every
      # command's output. An import compares a few hundred short strings; that
      # is nowhere near enough work to be worth a build step.
      #
      # @return [FuzzyStringMatch::JaroWinklerPure]
      def matcher = @matcher ||= FuzzyStringMatch::JaroWinkler.create(:pure)

      # @param one [String]
      # @param other [String]
      # @return [Float] 0.0 to 1.0
      def similarity(one, other) = matcher.getDistance(one.to_s.downcase, other.to_s.downcase)

      # @param one [String]
      # @param other [String]
      # @return [Boolean] whether these are the same word, inflections aside
      def akin?(one, other) = similarity(one, other) >= AKIN

      # What fraction of `wanted` has a counterpart in `found`.
      #
      # Asymmetric on purpose. A folder is named for what it is about, in two
      # or three words; a pull request title is a sentence. Asking how much of
      # the sentence the folder covers would punish every long title, so the
      # question is the other way round: how much of this folder's name did
      # the title actually say?
      #
      # @param wanted [Array<String>] the folder's words
      # @param found [Array<String>] the title's words
      # @return [Float] 0.0 to 1.0
      def coverage(wanted, found)
        return 0.0 if wanted.empty?

        wanted.count { |word| found.any? { |other| akin?(word, other) } }.fdiv(wanted.size)
      end
    end
  end
end
