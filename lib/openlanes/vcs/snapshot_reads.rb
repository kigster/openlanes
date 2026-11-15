# frozen_string_literal: true

require "delegate"

module OpenLanes
  module Vcs
    # A {GitHub} whose per-pull-request reads (`pull_request`, `labels`, `checks`) are
    # answered from the tick's shared {PullSnapshot} when it holds that pull
    # request, and asked of GitHub only when it does not. Every write drops
    # the snapshot, so a label this process just put on is never read back
    # stale.
    class SnapshotReads < SimpleDelegator
      # The calls that change a pull request; after any of them the snapshot
      # no longer says what GitHub does.
      WRITES = %i[swap_label remove_label ensure_label comment merge update_branch retitle].freeze

      # @param github [GitHub]
      # @param snapshot [#call, #refresh!] `-> PullSnapshot`, e.g. {Engine::Steps::Snapshot}
      def initialize(github, snapshot:)
        super(github)
        @snapshot = snapshot
      end

      # @return [Array<String>]
      def labels(number:, repo: nil) = (row = held(number, repo)) ? row[:labels] : __getobj__.labels(number:, repo:)

      # A pull request that has merged or closed is not in the snapshot, which
      # holds open ones only, so it is read live: that is the read that
      # carries its merge commit.
      #
      # @param ref [String, Integer] a pull request URL or number
      # @return [Hash] in {GitHub#pull_request}'s shape
      def pull_request(ref)
        number, repo = parse_ref(ref)
        row = number && held(number, repo)
        row ? row.except(:files, :checks, :complete) : __getobj__.pull_request(ref)
      end

      # @return [Array<Hash>] `{name:, bucket:}`
      def checks(number:, repo: nil) = (row = held(number, repo)) ? row[:checks] : __getobj__.checks(number:, repo:)

      WRITES.each do |name|
        define_method(name) do |*args, **kwargs, &block|
          @snapshot.refresh!
          __getobj__.public_send(name, *args, **kwargs, &block)
        end
      end

      private

      # @return [Array(Integer, String), nil] the number and the repository
      #   (nil for a bare number); nil when +ref+ names no pull request
      def parse_ref(ref)
        [GitHub.number_of(ref), GitHub.repo_of(ref)]
      rescue Error
        nil
      end

      # @return [Hash, nil] the snapshot's row for that pull request, when it
      #   is open there, in the repository asked about, and read whole (a row
      #   with a truncated list of checks or labels is read live, so a gate
      #   fails closed)
      def held(number, repo)
        row = @snapshot.call.complete(number.to_i) or return
        row if repo.nil? || GitHub.repo_of(row[:url]) == repo
      rescue Error
        nil
      end
    end
  end
end
