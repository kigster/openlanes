# frozen_string_literal: true

require "json"

module OpenLanes
  module Live
    # One instruction from the page to the engine, as `web/src/api/types.ts`
    # defines `Command`. The id is minted by the page and is also the
    # idempotency key (W13): the engine applies a command once however many
    # times it is delivered.
    #
    # {.parse} checks only the shape, so the API server can refuse a
    # malformed command with 422 before it is queued. Whether the plan,
    # agent or question it names exists is the engine's to say, when it
    # applies it.
    #
    # @!attribute [r] id
    #   @return [String]
    # @!attribute [r] kind
    #   @return [String] one of {KINDS}
    # @!attribute [r] plan
    #   @return [String, nil] an ordinal
    # @!attribute [r] agent
    #   @return [String, nil]
    # @!attribute [r] payload
    #   @return [Hash{String => Object}]
    Command = Data.define(:id, :kind, :plan, :agent, :payload) do
      # @return [String] `"<ordinal>/<agent>"`, the car it addresses
      def car = "#{plan}/#{agent}"

      # @param name [String]
      # @return [String] the payload field, stripped; empty when absent
      def [](name) = payload[name.to_s].to_s.strip

      # @return [Hash] as the wire carries it
      def wire = { id:, kind:, plan:, agent:, payload: }
    end

    class Command
      # A command that cannot be applied as written.
      class Invalid < Error; end

      # Every kind the page may send.
      KINDS = %w[answer hold_blocked release_hold resume discard message hold wrap_up compact stop stop_all
                 set_model switch_model add_plan create_plans respond pause_discuss resume_anyway
                 stop_plan restart_plan set_concurrency].freeze

      # Kinds that act on one plan, and so must name it.
      PLAN_KINDS = %w[answer hold_blocked release_hold resume discard message hold wrap_up compact stop
                      set_model switch_model respond pause_discuss resume_anyway stop_plan restart_plan].freeze

      # Kinds that act on one agent of that plan, and so must name it too.
      AGENT_KINDS = %w[hold wrap_up compact stop set_model switch_model].freeze

      # Payload fields each kind cannot do without.
      PAYLOAD = {
        "answer"          => %w[question text],
        "hold_blocked"    => %w[question],
        "release_hold"    => %w[question],
        "message"         => %w[text],
        "set_model"       => %w[model],
        "switch_model"    => %w[model],
        "add_plan"        => %w[ordinal],
        "create_plans"    => %w[idea],
        "respond"         => %w[text],
        "set_concurrency" => %w[limit]
      }.freeze

      # Ids are ULIDs; this only keeps an absurd one out of a hash field.
      ID = /\A[0-9A-Za-z_-]{1,64}\z/

      # @param input [String, Hash] JSON, or the parsed hash
      # @return [OpenLanes::Live::Command]
      # @raise [OpenLanes::Live::Command::Invalid] naming what is wrong
      def self.parse(input)
        data = input.is_a?(String) ? JSON.parse(input) : input
        raise Invalid, "a command is a JSON object" unless data.is_a?(Hash)

        data = data.transform_keys(&:to_s)
        plan = data["plan"]&.to_s
        command = new(id: data["id"].to_s,
          kind: data["kind"].to_s,
          plan: (Plans::Ordinal.parse(plan)&.to_s if plan) || plan,
          agent: data["agent"]&.to_s,
          payload: (data["payload"] || {}).to_h.transform_keys(&:to_s))
        command.tap { check(it) }
      rescue JSON::ParserError, TypeError, NoMethodError => e
        raise Invalid, "not a command: #{e.message.lines.first.to_s.strip}"
      end

      # @param command [OpenLanes::Live::Command]
      # @return [void]
      # @raise [OpenLanes::Live::Command::Invalid]
      def self.check(command)
        raise Invalid, "id must be 1 to 64 letters, digits, - or _" unless command.id.match?(ID)
        raise Invalid, "unknown kind #{command.kind.inspect}; known: #{KINDS.join(", ")}" unless KINDS.include?(command.kind)
        raise Invalid, "#{command.kind} needs a plan" if PLAN_KINDS.include?(command.kind) && command.plan.to_s.empty?
        raise Invalid, "#{command.kind} needs an agent" if AGENT_KINDS.include?(command.kind) && command.agent.to_s.empty?

        missing = PAYLOAD.fetch(command.kind, []).select { |field| command[field].empty? }
        raise Invalid, "#{command.kind} needs payload #{missing.join(" and ")}" unless missing.empty?
      end
    end

    # The engine's answer to one {Command}: `Reply` in `types.ts`.
    #
    # @!attribute [r] id
    #   @return [String] the command's id
    # @!attribute [r] status
    #   @return [String] "accepted", "refused" or "done"
    # @!attribute [r] reason
    #   @return [String, nil]
    # @!attribute [r] at
    #   @return [Time]
    Reply = Data.define(:id, :status, :reason, :at) do
      def initialize(reason: nil, at: Time.now, **rest) = super

      # @return [Hash]
      def wire = { id:, status:, reason:, at: at.utc.iso8601 }

      # @return [String]
      def to_json(*) = JSON.generate(wire)
    end
  end
end
