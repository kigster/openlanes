# frozen_string_literal: true

require "date"
require "json"
require "json_schemer"

module OpenLanes
  class Config
    # `schemas/openlanes-config.schema.json`, the one place every key of
    # `.openlanes.yml` is described (S4): its type, allowed values, default
    # and one line of help. The parser, the full-file writer and the
    # settings page all read it, so none of them keeps a list of its own.
    #
    # The checked-in file holds the whole document, `commands` included, so
    # an editor can validate against it; `commands` itself is rebuilt from
    # the CLI registry on every load (S5), and a spec fails when the file
    # is stale. `just update-config-schema` rewrites it.
    module Schema
      # The checked-in document.
      PATH = File.expand_path("../../../../schemas/openlanes-config.schema.json", __dir__)

      module_function

      # @return [Hash{String => Object}] the schema, `commands` from the registry
      def document
        @document ||= begin
          static = JSON.parse(File.read(PATH, encoding: "UTF-8"))
          static["properties"]["commands"] = CommandsSchema.build
          static.freeze
        end
      end

      # @return [Array<String>] every key the top level may hold, in documented order
      def keys = document.fetch("properties").keys

      # @param section [String, Symbol] e.g. "merge"
      # @return [Array<String>] every key the section may hold; empty for an
      #   open section whose own parser checks it (app, coverage, …)
      def keys_for(section) = document.dig("properties", section.to_s, "properties")&.keys || []

      # @return [Hash{String => Object}] every key with its default, nested
      #   sections as Hashes of their own keys' defaults
      def defaults
        document.fetch("properties").to_h do |key, schema|
          nested = schema["properties"]
          [key, key == "commands" || nested.nil? ? schema["default"] : nested.transform_values { it["default"] }]
        end
      end

      # @param settings [Hash] the parsed file, string keys
      # @return [Array<Hash>] json_schemer's errors, empty when the file is valid
      def errors(settings) = schemer.validate(jsonable(settings)).to_a

      # @param path [String]
      # @return [void]
      def write(path = PATH) = File.write(path, "#{JSON.pretty_generate(document)}\n")

      # @return [JSONSchemer::Schema]
      def schemer = @schemer ||= JSONSchemer.schema(document)

      # YAML hands over Dates and Symbols, which JSON has no word for; the
      # schema describes the file as typed, so each is read as its text.
      #
      # @param value [Object]
      # @return [Object]
      def jsonable(value)
        case value
        when Hash then value.to_h { |k, v| [k.to_s, jsonable(v)] }
        when Array then value.map { jsonable(it) }
        when Date, Symbol then value.to_s
        else value
        end
      end
    end
  end
end
