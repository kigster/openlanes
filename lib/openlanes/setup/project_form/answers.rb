# frozen_string_literal: true

module OpenLanes
  module Setup
    module ProjectForm
      # Turns what a run of the form said into the decisions to record. With no
      # answers at all (`-y`) it records what the scan found and what the file
      # already said, and never a recommendation.
      class Answers
        # @param input [Object] a comma- or space-separated list of folders
        # @return [Array<String>]
        def self.paths(input) = input.to_s.split(/[,\s]+/).reject(&:empty?)

        # @param answers [Hash{Symbol => Object}]
        # @param scan [OpenLanes::Setup::Architecture]
        # @param file [OpenLanes::Setup::ArchitectureDecisions]
        # @param wanted_ci [Symbol, nil] `--ci`, which wins over any answer
        def initialize(answers:, scan:, file:, wanted_ci: nil)
          @answers = answers
          @scan = scan
          @file = file
          @wanted_ci = wanted_ci
        end

        # @return [OpenLanes::Setup::ArchitectureDecisions]
        def decisions
          ArchitectureDecisions.new(detail: @answers[:detail]&.to_sym || @file.detail,
            current:,
            target:,
            migration: migration)
        end

        private

        # @return [Symbol, nil]
        def migration = changed? ? (@answers[:migration]&.to_sym || @file.migration) : nil

        # @return [Boolean]
        def changed? = !current.blank? && current != target

        # @return [OpenLanes::Setup::Architecture]
        def current
          @current ||= filled(filled(@file.current, @scan), section(:current))
        end

        # @return [OpenLanes::Setup::Architecture]
        def target
          @target ||= begin
            wanted = @answers[:keep_current] ? current : filled(filled(current, @file.target), understood, section(:target))
            @wanted_ci ? wanted.new(ci: [@wanted_ci]) : wanted
          end
        end

        # @return [Hash{Symbol => Object}] what the description settled, even for a
        #   question this detail does not ask
        def understood = picked(@answers[:understanding], :target)

        # @return [Hash{Symbol => Object}] the answers given to one snapshot's questions
        def section(name) = picked(@answers, name)

        # @return [Hash{Symbol => Object}]
        def picked(source, name)
          Architecture::ATTRIBUTES.each_with_object({}) do |attribute, held|
            value = source&.[](:"#{name}_#{attribute.name}")
            held[attribute.name] = attribute.kind == :paths ? self.class.paths(value) : value unless value.nil?
          end
        end

        # @return [OpenLanes::Setup::Architecture] the first, with what each later one holds
        def filled(base, *others)
          others.reduce(base) do |merged, other|
            merged.new(other.to_h.reject { |_, value| value.nil? || value == [] || value == "" })
          end
        end
      end
    end
  end
end
