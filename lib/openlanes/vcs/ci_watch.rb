# frozen_string_literal: true

module OpenLanes
  module Vcs
    # CI on a plan's open pull requests, as one answer, asked of GitHub at
    # most once a minute per plan.
    #
    # The dispatcher asks on every tick while a review waits for a green
    # build, and a `gh` call per tick per plan is how a run meets GitHub's
    # rate limit. A build does not change faster than this remembers it.
    class CiWatch
      # Seconds an answer is kept.
      TTL = 60

      # @param github [OpenLanes::Vcs::GitHub]
      # @param clock [#call] monotonic seconds
      def initialize(github:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @github = github
        @clock = clock
        @seen = {}
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Symbol] {CiGate.verdict} over every open pull request's
      #   checks; `:pending` when GitHub cannot be read, so nothing is
      #   waved through on an error
      def call(subject)
        key = subject.feature.ordinal.to_s
        at, state = @seen[key]
        return state if at && @clock.call - at < TTL

        read(subject).tap { @seen[key] = [@clock.call, it] }
      end

      private

      # @return [Symbol]
      def read(subject)
        pulls = subject.pull_requests.select(&:open?)
        checks = pulls.flat_map do |pull|
          ref = pull.url || pull.number
          @github.checks(number: GitHub.number_of(ref), repo: GitHub.repo_of(ref))
        end
        CiGate.verdict(checks)
      rescue Error => e
        UI.log("could not read CI of #{subject.feature.ordinal}: #{e.message}", level: :warn, plan: subject.feature.ordinal.to_s)
        :pending
      end
    end
  end
end
