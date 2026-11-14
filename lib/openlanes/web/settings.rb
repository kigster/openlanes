# frozen_string_literal: true

require "digest"
require "open3"
require "yaml"

module OpenLanes
  module Web
    # The settings page's model (plan 058, B1): `.openlanes.yml` as the page
    # reads it, and the check a save must pass before anything is written.
    # The schema is {Config::Schema}'s and the judge is {Config.parse}, so the
    # page never accepts a value the engine would refuse on its next load.
    module Settings
      # What GET /api/settings answers.
      #
      # @!attribute [r] schema
      #   @return [Hash] the JSON Schema document, `commands` included
      # @!attribute [r] keys
      #   @return [Array<String>] the top-level keys, in {Config::KEYS} order
      # @!attribute [r] values
      #   @return [Hash] what the file holds, string keys
      # @!attribute [r] defaults
      #   @return [Hash] {Config::Schema.defaults}
      # @!attribute [r] etag
      #   @return [String] sha256 of the file's bytes
      # @!attribute [r] branch
      #   @return [String, nil] the checkout's branch, nil when detached
      View = Data.define(:schema, :keys, :values, :defaults, :etag, :branch) do
        # @return [Hash{Symbol => Object}]
        def to_json_hash = to_h
      end

      # One refused value: the key path it sits at, and why.
      Problem = Data.define(:path, :message) do
        # @return [Hash{Symbol => Object}]
        def to_json_hash = { path:, message: }
      end

      module_function

      # @param root [String] the project root, the main checkout
      # @return [View]
      def read(root)
        View.new(schema: Config::Schema.document,
          keys: Config::KEYS,
          values: file_values(root),
          defaults: Config::Schema.defaults,
          etag: etag(root),
          branch: branch(root))
      end

      # @param values [Hash] the whole file as the page would have it
      # @return [Array<Problem>] empty when {Config.parse} accepts it
      def validate(values)
        parse(values)
        []
      rescue Error => e
        problems(compact(values), e.message)
      end

      # @param values [Hash] the whole file, already {.validate}d
      # @return [Config]
      # @raise [OpenLanes::Error] when it does not parse
      def parse(values) = Config.parse(text(values), path: Config::FILE)

      # @param values [Hash]
      # @return [String] the YAML {Config.parse} is given
      def text(values) = YAML.dump(compact(values))

      # @param root [String]
      # @return [String] sha256 of the file, of nothing when there is none
      def etag(root)
        path = File.join(root, Config::FILE)
        Digest::SHA256.hexdigest(File.file?(path) ? File.binread(path) : "")
      end

      # @param root [String]
      # @return [String, nil]
      def branch(root)
        out, status = Open3.capture2("git", "-C", root.to_s, "symbolic-ref", "--short", "-q", "HEAD", err: File::NULL)
        status.success? ? out.strip : nil
      end

      # @param root [String]
      # @return [Hash] the file as YAML reads it, {} when absent or not a mapping
      def file_values(root)
        path = File.join(root, Config::FILE)
        return {} unless File.file?(path)

        data = YAML.safe_load_file(path, permitted_classes: [Date])
        data.is_a?(Hash) ? Config::Schema.jsonable(compact(data)) : {}
      rescue Psych::Exception
        {}
      end

      # Unset is unset however the page spells it: absent, null, "" or an
      # empty section. The form sends every default it drew, so without this
      # an untouched page would write a section of nulls.
      #
      # @param value [Object]
      # @return [Object]
      def compact(value)
        return value unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, inner), out|
          inner = compact(inner)
          out[key.to_s] = inner unless inner.nil? || inner == "" || inner == {}
        end
      end

      # Every schema error, by path; when the schema has none, the parser's
      # own sentence, placed on the key it names.
      #
      # @param values [Hash]
      # @param message [String] {Config.parse}'s refusal
      # @return [Array<Problem>]
      def problems(values, message)
        schema = Config::Schema.errors(Config::Schema.jsonable(values)).map do |error|
          path = error.fetch("data_pointer").split("/").drop(1).map { it.gsub("~1", "/").gsub("~0", "~") }
          Problem.new(path:, message: error.fetch("error"))
        end
        schema.empty? ? [parser_problem(message)] : schema
      end

      # @param message [String] e.g. ".openlanes.yml: merge.by: \"x\" is not one of …"
      # @return [Problem]
      def parser_problem(message)
        text = message.delete_prefix("#{Config::FILE}: ")
        dotted = text[/\A([a-z_]+(?:\.[\w-]+)*)[: ]/, 1]
        path = if dotted && Config::KEYS.include?(dotted.split(".").first)
                 dotted.split(".")
               else
                 Array(Config::KEYS.find { text.match?(/\b#{Regexp.escape(it)}\b/) })
               end
        Problem.new(path:, message: text)
      end
    end
  end
end
