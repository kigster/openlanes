# frozen_string_literal: true

module OpenLanes
  module Setup
    module ProjectForm
      # What each question shows already chosen, and where that came from.
      # NOW shows the scan, else what the file said. WANTED shows the description,
      # else the file, else what NOW was answered, else a recommendation.
      class Preselection
        # A question about one attribute of one snapshot.
        ATTRIBUTE_STEP = /\A(current|target)_(.+)\z/

        # @param scan [OpenLanes::Setup::Architecture]
        # @param file [OpenLanes::Setup::ArchitectureDecisions]
        # @param config [Hash{Symbol => Object}] the other answers the file holds
        def initialize(scan:, file:, config: {})
          @scan = scan
          @file = file
          @config = config
          @understood = {}
        end

        # @param understood [Hash{Symbol => Object}] what the description settled
        # @return [void]
        def understand(understood) = @understood = understood

        # @param id [Symbol]
        # @param answers [Hash{Symbol => Object}] the answers so far
        # @return [Object, nil]
        def for(id, answers)
          section, name = id.to_s.match(ATTRIBUTE_STEP)&.captures
          return @understood.fetch(id) { @config[id] } unless section

          attribute = Architecture::ATTRIBUTES.find { it.name == name.to_sym } or return @config[id]
          section == "current" ? now(attribute) : wanted(attribute, answers)
        end

        private

        # @return [Object, nil]
        def now(attribute) = first_held(attribute, @scan.public_send(attribute.name), @file.current.public_send(attribute.name))

        # @return [Object, nil]
        def wanted(attribute, answers)
          name = attribute.name
          return @understood[:"target_#{name}"] if @understood.key?(:"target_#{name}")

          first_held(attribute,
            @file.target.public_send(name),
            answers[:"current_#{name}"],
            now(attribute),
            Architecture.recommended(frameworks(answers)).fetch(name, nil))
        end

        # @return [Array<Symbol>]
        def frameworks(answers) = Array(answers[:current_frameworks]).map(&:to_sym) | @scan.frameworks

        # @return [Object, nil] the first value that says something, as the step reads it
        def first_held(attribute, *values)
          held = values.find { !it.nil? && it != [] && it != "" } or return nil
          case attribute.kind
          when :one then held.to_s
          when :paths then held.is_a?(String) ? held : held.join(", ")
          else Array(held).map(&:to_s)
          end
        end
      end
    end
  end
end
