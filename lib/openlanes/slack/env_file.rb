# frozen_string_literal: true

module OpenLanes
  module Slack
    # A `.env` file, read and changed one variable at a time. Every line it
    # is not asked about is kept as it was typed, comments included.
    class EnvFile
      # `NAME=value`, with the `export` a shell allows before it.
      LINE = /\A\s*(?<export>export\s+)?(?<name>[A-Za-z_]\w*)=(?<value>.*)\z/

      # A value that needs no quotes in a shell.
      BARE = %r{\A[\w.,:/@%+=-]+\z}

      # The file holds tokens.
      MODE = 0o600

      # @param path [String]
      def initialize(path)
        @path = path
      end

      # @return [String]
      attr_reader :path

      # @param name [String]
      # @return [String, nil] nil when unset or blank
      def [](name) = to_h[name]

      # @return [Hash{String => String}] every variable with a value; the last
      #   line for a name wins, as it does in a shell
      def to_h
        lines.filter_map { LINE.match(it) }
             .to_h { [it[:name], unquoted(it[:value].strip)] }
             .reject { |_, value| value.empty? }
      end

      # @param values [Hash{String => String}]
      # @return [Hash{String => String}] those the file does not hold already
      def changes(values) = values.reject { |name, value| self[name] == value }

      # @param values [Hash{String => String}]
      # @return [void]
      def write(values)
        missing = values.dup
        kept = lines.map do |line|
          match = LINE.match(line)
          next line unless match && values.key?(match[:name])

          missing.delete(match[:name])
          # A line that said `export` keeps saying it: a `.env` that a shell
          # sources needs it, or the variable never reaches the run.
          "#{"export " if match[:export]}#{match[:name]}=#{quoted(values.fetch(match[:name]))}"
        end
        added = missing.map { |name, value| "#{name}=#{quoted(value)}" }
        save("#{[*kept, *added].join("\n")}\n")
      end

      private

      # @return [Array<String>]
      def lines = File.file?(path) ? File.readlines(path, chomp: true) : []

      # Written beside the file and moved over it, so a crash half way leaves
      # the old tokens rather than half of the new. A link is written through,
      # since worktrees share one `.env` that way.
      #
      # @param text [String]
      # @return [void]
      def save(text)
        target = File.exist?(path) ? File.realpath(path) : path
        draft = "#{target}.#{Process.pid}.tmp"
        File.write(draft, text, perm: MODE)
        File.rename(draft, target)
      ensure
        File.delete(draft) if draft && File.exist?(draft)
      end

      # @return [String]
      def quoted(value) = value.match?(BARE) ? value : "'#{value.gsub("'", "'\\\\''")}'"

      # Single quotes are undone the way {#quoted} made them, `'\''` and all,
      # so a value written here reads back as itself.
      #
      # @return [String]
      def unquoted(value)
        return value.delete_prefix("'").delete_suffix("'").gsub("'\\''", "'") if value.match?(/\A'.*'\z/)

        value.match(/\A"(.*)"\z/)&.[](1) || value
      end
    end
  end
end
