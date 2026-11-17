# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "yaml"

module OpenLanes
  module Web
    # The settings page's model (plan 058, B1): `.openlanes/config.yml` as the page
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
      # @!attribute [r] file
      #   @return [String] the file a save writes, relative to the root, so
      #     the page names the legacy file on a project that still has it
      View = Data.define(:schema, :keys, :values, :defaults, :etag, :branch, :file) do
        # @return [Hash{Symbol => Object}]
        def to_json_hash = to_h
      end

      # One refused value: the key path it sits at, and why.
      Problem = Data.define(:path, :message) do
        # @return [Hash{Symbol => Object}]
        def to_json_hash = { path:, message: }
      end

      # Both places a project file can sit, the current one first. The remote
      # may add or move the file at the one a checkout does not use, so a
      # save looks at both.
      FILES = [Project::FILE, Project::LEGACY_FILE].freeze

      module_function

      # @param root [String]
      # @return [Boolean] whether the root holds the file at both paths, the
      #   state every command refuses
      def both?(root) = FILES.all? { File.file?(File.join(root, it)) }

      # @param root [String] the project root, the main checkout
      # @return [View]
      def read(root)
        View.new(schema: Config::Schema.document,
          keys: Config::KEYS,
          values: file_values(root),
          defaults: Config::Schema.defaults,
          etag: etag(root),
          branch: branch(root),
          file: file(root))
      end

      # @param values [Hash] the whole file as the page would have it
      # @param path [String] the file a save would write, as {.file} names it
      # @return [Array<Problem>] empty when {Config.parse} accepts it
      def validate(values, path: Config::FILE)
        parse(values, path:)
        []
      rescue Error => e
        problems(compact(values), e.message, path)
      end

      # @param values [Hash] the whole file, already {.validate}d
      # @param path [String] the file a save would write: the parser names it
      #   in what it says, and a legacy project is not saving {Config::FILE}
      # @return [Config]
      # @raise [OpenLanes::Error] when it does not parse
      def parse(values, path: Config::FILE) = Config.parse(text(values), path:)

      # @param values [Hash]
      # @return [String] the YAML {Config.parse} is given
      def text(values) = YAML.dump(compact(values))

      # The project file this root has, relative to it: the legacy name while
      # a project still carries it. Saving to {Config::FILE} there would leave
      # two files, and every command refuses a root that holds both.
      #
      # @param root [String]
      # @return [String]
      def file(root)
        Project.config_path(root).delete_prefix("#{root}/")
      rescue Error
        Config::FILE
      end

      # Writes the project file, making `.openlanes/` for a project that has
      # no config file yet.
      #
      # @param root [String]
      # @param text [String]
      # @return [void]
      def write(root, text)
        path = File.join(root, file(root))
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text)
      end

      # @param root [String]
      # @return [String] sha256 of the file, of nothing when there is none
      def etag(root)
        path = File.join(root, file(root))
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
        path = File.join(root, file(root))
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
      # @param file [String] the path that refusal starts with
      # @return [Array<Problem>]
      def problems(values, message, file = Config::FILE)
        schema = Config::Schema.errors(Config::Schema.jsonable(values)).map do |error|
          path = error.fetch("data_pointer").split("/").drop(1).map { it.gsub("~1", "/").gsub("~0", "~") }
          Problem.new(path:, message: readable(error))
        end
        schema.empty? ? [parser_problem(message, file)] : schema
      end

      # A refused pattern, said in the key's own words. The validator's text
      # quotes the regex (`does not match pattern: ^\s*[/~]`), which tells a
      # person typing `events.log` into a directory field nothing.
      #
      # @param error [Hash] one json_schemer error
      # @return [String]
      def readable(error)
        description = error.dig("schema", "description")
        return error.fetch("error") unless error["type"] == "pattern" && description

        "#{error["data"].inspect} is not accepted here: #{description}"
      end

      # @param message [String] e.g. ".openlanes/config.yml: merge.by: \"x\" is not one of …"
      # @param file [String] the path the parser was given
      # @return [Problem]
      def parser_problem(message, file = Config::FILE)
        text = message.delete_prefix("#{file}: ")
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
