# frozen_string_literal: true

require "json"
require "time"

module OpenLanes
  module Supervision
    # What one factory process says about itself in `tmp/pids/` (S2): who it
    # is, when it started, and where. A PID alone is not proof, since the
    # operating system reuses numbers, so {Probe#verified?} matches the
    # start time and the title as well before anything trusts or signals it.
    #
    # @!attribute [r] role
    #   @return [String] supervisor, engine, web, run or agent
    # @!attribute [r] pid
    #   @return [Integer]
    # @!attribute [r] started
    #   @return [String, nil] `ps -o lstart=` for the process, as written by itself
    # @!attribute [r] root
    #   @return [String] the project root
    # @!attribute [r] url
    #   @return [String, nil] the control room, for a supervisor or a web
    # @!attribute [r] plans
    #   @return [Array<String>] what a run works, or the plan an agent works
    # @!attribute [r] agent
    #   @return [String, nil] which agent an agent supervisor runs
    # @!attribute [r] failed
    #   @return [Hash{String => String}] children a supervisor stopped restarting, and why
    PidFile = Data.define(:role, :pid, :started, :root, :url, :plans, :failed, :agent) do
      # Defaults for the optional members, +url+, +plans+, +failed+ and
      # +agent+; +role+, +pid+, +started+ and +root+ pass through.
      #
      # @param fields [Hash]
      def initialize(**fields) = super(url: nil, plans: [], failed: {}, agent: nil, **fields)

      # @param text [String] what {#to_json} wrote
      # @return [OpenLanes::Supervision::PidFile, nil] nil for anything unreadable,
      #   which every reader treats as a crash
      def self.parse(text)
        data = JSON.parse(text, symbolize_names: true)
        new(**data.slice(:url, :agent),
          role:    data.fetch(:role),
          pid:     Integer(data.fetch(:pid)),
          started: data[:started],
          root:    data.fetch(:root),
          plans:   Array(data[:plans]),
          failed:  (data[:failed] || {}).transform_keys(&:to_s))
      rescue JSON::ParserError, KeyError, ArgumentError, TypeError
        nil
      end

      # A run is one of many, so its file carries its pid; every other role
      # has one file per project.
      #
      # @return [String]
      def name = self.class.name_for(role, pid)

      # @param role [String]
      # @param pid [Integer]
      # @return [String] the file name, without the directory
      def self.name_for(role, pid) = role == RUN ? "#{RUN}-#{pid}.pid" : "#{role}.pid"

      # @return [String] what the process's title starts with (S5)
      def title = Title.prefix(role, root)

      # @param now [Time]
      # @return [Integer, nil] seconds since the process started
      def uptime(now: Time.now)
        started && (now - Time.strptime(started, "%a %b %e %H:%M:%S %Y")).to_i
      rescue ArgumentError
        nil
      end

      # @return [String]
      def to_json(*) = JSON.pretty_generate(to_h.compact)
    end
  end
end
