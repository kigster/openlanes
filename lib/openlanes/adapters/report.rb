# frozen_string_literal: true

module OpenLanes
  module Adapters
    # The Adapters table `openlanes agents list` prints under the roster
    # (plan 040, D8): which coding CLIs can take an agent on this machine,
    # what each can do, and how many models it offers.
    #
    # {#render} returns a string and prints nothing, the bargain
    # {Agents::Roster} makes, so the table stays pipeable.
    class Report
      # Columns, so the header and the rows cannot drift apart.
      HEADINGS = ["Adapter", "Available", "Can", "Models"].freeze

      # {Capabilities} members, in the words the table uses for them.
      CAN = { compacts: "compacts", resumes: "resumes", enforces_tool_denial: "refuses denied tools" }.freeze

      # @param availabilities [Array<OpenLanes::Adapters::Availability>]
      def initialize(availabilities)
        @availabilities = availabilities
      end

      # @return [String] newline-terminated
      def render = UI.table(availabilities.map { row(it) }, header: HEADINGS)

      private

      # @return [Array<OpenLanes::Adapters::Availability>]
      attr_reader :availabilities

      # @param availability [OpenLanes::Adapters::Availability]
      # @return [Array<String>] one cell per entry in {HEADINGS}
      def row(availability)
        [UI.paint(availability.name, :bright_cyan),
         status(availability),
         UI.paint(can(Adapters.for(availability.name).capabilities), :bright_black),
         availability.models.size.to_s]
      end

      # @param availability [OpenLanes::Adapters::Availability]
      # @return [String] "yes", or the reason it is not
      def status(availability)
        return UI.paint("yes", :green) if availability.available?

        UI.paint(availability.reason || "not checked yet", :yellow)
      end

      # @param capabilities [OpenLanes::Adapters::Capabilities]
      # @return [String] e.g. "compacts, resumes", or "—" for none
      def can(capabilities)
        words = CAN.filter_map { |member, word| word if capabilities.public_send(member) }
        words.empty? ? "—" : words.join(", ")
      end
    end
  end
end
