# frozen_string_literal: true

module OpenLanes
  module Apps
    # The `app:` block of `.openlanes.yml`: what kind of app a project builds
    # and the processes that run it, in the order they start.
    #
    # Written by backend-coder on a plan's first build (M12) and only ever read here.
    # It is new surface that every project will copy, so anything it does not
    # know is refused with the file named, exactly as {Config} refuses an
    # unknown top-level key: a `restart-on:` typo silently ignored is a
    # watcher that never fires and nobody can say why.
    #
    # @!attribute [r] kind
    #   @return [String, nil] free text, `web` or `desktop` (M11); recorded,
    #     not interpreted here
    # @!attribute [r] processes
    #   @return [Array<OpenLanes::Apps::ProcessSpec>] in start order
    Definition = Data.define(:kind, :processes) do
      # @return [OpenLanes::Apps::ProcessSpec, nil] the process marked
      #   `preview: true`; nil when none is, which means no Preview tab
      def preview = processes.find(&:preview?)

      # @param name [String]
      # @return [OpenLanes::Apps::ProcessSpec, nil]
      def process(name) = processes.find { it.name == name.to_s }

      # Every process the Preview tab's Restart backend button restarts:
      # all but the one it shows, in declared order.
      #
      # @return [Array<OpenLanes::Apps::ProcessSpec>]
      def backend = processes.reject(&:preview?)

      # @return [Hash] as `.openlanes.yml` spells it
      def to_h = { "kind" => kind, "processes" => processes.map(&:to_h) }.compact
    end

    class Definition
      # Keys the `app:` mapping may hold.
      KEYS = %w[kind processes].freeze

      # Keys each process may hold.
      PROCESS_KEYS = %w[name start ready restart_on preview].freeze

      # A process name: what `PORT_<NAME>`, the Preview tab and `target:`
      # all carry, so nothing a shell or a URL would trip over.
      NAME = /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/

      class << self
        # @param value [Object] the parsed `app:` value
        # @param path [String] the file, for every error
        # @return [OpenLanes::Apps::Definition]
        # @raise [OpenLanes::Error] naming the file and what is wrong
        def parse(value, path:)
          fail_with(path, "app: must be a mapping with processes:") unless value.is_a?(Hash)

          data = value.transform_keys(&:to_s)
          unknown!(path, "app", data.keys - KEYS, KEYS)
          kind = data["kind"]
          fail_with(path, "app.kind: #{kind.inspect} is not a word like web") unless kind.nil? || kind.is_a?(String)

          list = data["processes"]
          fail_with(path, "app.processes: must be a list of at least one process") unless list.is_a?(Array) && !list.empty?

          processes = list.each_with_index.map { |entry, index| process(entry, index, path) }
          checked(new(kind: kind&.strip, processes:), path)
        end

        private

        # @return [OpenLanes::Apps::ProcessSpec]
        def process(entry, index, path)
          where = "app.processes[#{index}]"
          fail_with(path, "#{where}: must be a mapping with name: and start:") unless entry.is_a?(Hash)

          data = entry.transform_keys(&:to_s)
          unknown!(path, where, data.keys - PROCESS_KEYS, PROCESS_KEYS)
          name = data["name"]
          fail_with(path, "#{where}: needs name:, letters, digits, - or _") unless name.is_a?(String) && name.match?(NAME)

          ProcessSpec.new(name:,
            start:      start(data["start"], "app.processes.#{name}", path),
            ready:      ready(data["ready"], "app.processes.#{name}", path),
            restart_on: restart_on(data["restart_on"], "app.processes.#{name}", path),
            preview:    preview(data["preview"], "app.processes.#{name}", path))
        end

        # @return [String]
        def start(value, where, path)
          return value.strip if value.is_a?(String) && !value.strip.empty?

          fail_with(path, "#{where}: needs start:, the shell line that runs it")
        end

        # @return [String, nil]
        def ready(value, where, path)
          return nil if value.nil?
          return value if value.is_a?(String) && value.start_with?("/")

          fail_with(path, "#{where}.ready: #{value.inspect} is not an HTTP path like /up")
        end

        # @return [Array<String>]
        def restart_on(value, where, path)
          globs = value.is_a?(String) ? [value] : value
          return [] if globs.nil?
          return globs if globs.is_a?(Array) && globs.all? { it.is_a?(String) && !it.strip.empty? }

          fail_with(path, "#{where}.restart_on: must be a glob or a list of globs")
        end

        # @return [Boolean]
        def preview(value, where, path)
          return value == true if [true, false, nil].include?(value)

          fail_with(path, "#{where}.preview: #{value.inspect} is not true or false")
        end

        # Two processes that one name, one `PORT_` variable or two preview
        # flags would confuse.
        #
        # @return [OpenLanes::Apps::Definition]
        def checked(definition, path)
          names = definition.processes.map(&:name)
          twice = names.select { names.count(it) > 1 }.uniq
          fail_with(path, "app.processes: #{twice.join(", ")} named twice") unless twice.empty?

          envs = definition.processes.group_by(&:port_env).select { _2.size > 1 }
          envs.each do |env, specs|
            fail_with(path, "app.processes: #{specs.map(&:name).join(" and ")} would both be #{env}")
          end

          previews = definition.processes.select(&:preview?)
          if previews.size > 1
            fail_with(path, "app.processes: only one process may be preview: true, not #{previews.map(&:name).join(" and ")}")
          end
          definition
        end

        # @return [void]
        def unknown!(path, where, unknown, known)
          return if unknown.empty?

          fail_with(path, "#{where}: unknown key#{"s" unless unknown.size == 1} #{unknown.join(", ")}; known: #{known.join(", ")}")
        end

        # @return [void] never returns
        def fail_with(path, message) = raise(Error, "#{path}: #{message}")
      end
    end
  end
end
