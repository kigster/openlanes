# frozen_string_literal: true

module OpenLanes
  module CLI
    # Parsed options typed out again as flags, for the process `start`
    # spawns to do the work: the engine under the supervisor, or the
    # supervisor itself under `--background`.
    #
    # Only what differs from the command's defaults is typed. The defaults
    # already hold `.openlanes.yml`, which the child reads for itself, and a
    # value typed into argv is one anyone can read through `ps`.
    module Argv
      module_function

      # @param declared [Array<Dry::CLI::Option>] the options the child takes
      # @param values [Hash{Symbol => Object}] as the parent parsed them
      # @param defaults [Hash{Symbol => Object}] what the parent would have had untyped
      # @param except [Array<Symbol>] options the child is not given
      # @return [Array<String>]
      def for(declared, values, defaults:, except: [])
        declared.reject { except.include?(it.name) }.filter_map do |option|
          next unless values.key?(option.name)

          value = values[option.name]
          flag(option, value) unless value.nil? || value == defaults[option.name]
        end
      end

      # @param option [Dry::CLI::Option]
      # @param value [Object]
      # @return [String] `--name=value`, which no value starting with a dash can confuse
      def flag(option, value)
        dashed = option.name.to_s.tr("_", "-")
        return value ? "--#{dashed}" : "--no-#{dashed}" if option.boolean?

        "--#{dashed}=#{option.array? ? Array(value).join(",") : value}"
      end
    end
  end
end
