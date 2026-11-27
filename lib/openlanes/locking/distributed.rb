# frozen_string_literal: true

require "agent/lock"

module OpenLanes
  module Locking
    # {Adapter} over agent-lock's Ruby API, in this process: no fork and exec
    # of `alock` per call. Every lock lives in Redis (`REDIS_URL`) through
    # `Agent::Lock.distributed`, so it reaches across machines.
    #
    # Redis only, never the file store: a lock on one machine's disk is
    # invisible to an engine on another, which is the collision the register
    # exists to prevent. A Redis that does not answer is a passing fault, a
    # `:failed` {Outcome} or {Unreadable}, and the engine leaves plans alone
    # until it answers. agent-lock keeps no facade whose build failed, so
    # each call asks Redis again.
    #
    # Thread safety: a facade is frozen and builds a fresh manager per call,
    # and `Agent::Lock.distributed` is memoized thread-safely, so calls run
    # side by side with no mutex here.
    #
    # Lifetime: a facade ties a lock to the Ruby process that took it
    # (agent-lock's `holder: :process`, its default), read on every call, so
    # every lock ends with openlanes, and a fork holds its own.
    class Distributed
      include Adapter

      # The Redis facade; raises RedisUnavailableError when Redis does not answer.
      REDIS = -> { Agent::Lock.distributed }

      # What can go wrong in one call that may go right in the next: Redis
      # not answering or dropping, a checkout whose locks live in the file
      # store, a scope outside the checkout, `git` or `ps` failing underneath.
      PASSING = [Agent::Lock::Error, Agent::Lock::RedisUnavailableError, ::Redis::BaseError, SystemCallError].freeze

      # @param redis [#call] see {REDIS}; the spec passes one on its test database
      def initialize(redis: REDIS)
        @redis = redis
      end

      # @param root [String]
      # @return [Array<Lock>]
      # @raise [Unreadable]
      def list(root)
        facade.list(dir: root).records.filter_map do |record|
          next unless record.status == Agent::Lock::Record::ACTIVE

          Lock.new(agent: record.agent_id.to_s, scope: record.scope.to_s, tree: record.tree.to_s, intent: presence(record.intent))
        end
      rescue *PASSING => e
        raise Unreadable, first_line(e)
      end

      # @return [Outcome] `:done` for `:acquired` and `:already_mine`
      def acquire(scope, intent, dir:, as:) = change { facade.acquire(scope, intent, dir:, agent_id: as) }

      # @return [Outcome] `:done` for `:released`, `:refused` for `:not_found`
      def release(scope, dir:, as:)
        change do
          result = facade.release(scope, dir:, agent_id: as)
          next Outcome.new(status: :refused, message: "NOT LOCKED #{scope}") if result.status == :not_found

          result
        end
      end

      private

      # @yieldreturn [Agent::Lock::Manager::Result, Outcome]
      # @return [Outcome]
      def change
        answer = yield
        answer.is_a?(Outcome) ? answer : Outcome.new(status: :done, message: answer.message.to_s)
      rescue Agent::Lock::Refused => e
        Outcome.new(status: :refused, message: first_line(e))
      rescue *PASSING => e
        Outcome.new(status: :failed, message: first_line(e))
      end

      # @return [Agent::Lock::Facade]
      # @raise [Agent::Lock::RedisUnavailableError]
      def facade = @redis.call

      # @param error [Exception]
      # @return [String]
      def first_line(error) = error.message.lines.first.to_s.strip

      # @param text [String, nil]
      # @return [String, nil]
      def presence(text) = text.to_s.strip.empty? ? nil : text.strip
    end
  end
end
