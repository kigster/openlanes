# frozen_string_literal: true

module OpenLanes
  module Slack
    # A `.env` file, read and changed one variable at a time. Every line it
    # is not asked about is kept as it was typed, comments included, and a
    # line it changes keeps its `export` and its comment.
    class EnvFile
      # `NAME=value`, with the `export` a shell allows before it.
      LINE = /\A\s*(?<export>export\s+)?(?<name>[A-Za-z_]\w*)=(?<value>.*)\z/

      # A quoted value, as a shell reads one word: single-quoted runs,
      # double-quoted runs and backslash escapes, side by side. {#quoted}
      # writes `it's` as `'it'\''s'`, which is three of them.
      QUOTED = /\A(?:'[^']*'|"(?:[^"\\]|\\.)*"|\\.)+/

      # One run of {QUOTED}: single-quoted, double-quoted, or one escaped character.
      RUN = /'([^']*)'|"((?:[^"\\]|\\.)*)"|\\(.)/

      # Where a comment starts after a value: a `#` with whitespace before it,
      # as in a shell. `CHANNEL=#questions` is a value, not a comment.
      COMMENT = /\s+#/

      # A value that needs no quotes in a shell.
      BARE = %r{\A[\w.,:/@%+=-]+\z}

      # The file holds tokens.
      MODE = 0o600

      # Links followed before giving up, as the kernel does (ELOOP).
      MAX_LINKS = 40

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
             .to_h { [it[:name], parts(it[:value]).first] }
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
          rewritten(match, values.fetch(match[:name]))
        end
        added = missing.map { |name, value| "#{name}=#{quoted(value)}" }
        save("#{[*kept, *added].join("\n")}\n")
      end

      private

      # @return [Array<String>]
      def lines = File.file?(path) ? File.readlines(path, chomp: true) : []

      # A line that said `export` keeps saying it: a `.env` that a shell
      # sources needs it, or the variable never reaches the run. A comment
      # after the old value stays after the new one.
      #
      # @param match [MatchData] the line, as {LINE} read it
      # @param value [String]
      # @return [String]
      def rewritten(match, value)
        comment = parts(match[:value]).last
        "#{"export " if match[:export]}#{match[:name]}=#{quoted(value)}#{comment}"
      end

      # The value as a shell reads it, and the comment after it. Read whole,
      # `A=1 # one` was the value `1 # one`, and a rewrite dropped the comment.
      #
      # @param raw [String] everything after the `=`
      # @return [Array(String, String)] the value, and the comment with the
      #   whitespace before it, or nil when there is none
      def parts(raw)
        raw = raw.strip
        if (word = raw[QUOTED])
          rest = raw.delete_prefix(word)
          return [unquoted(word), rest.match?(/\A#{COMMENT}/) ? rest : nil]
        end

        at = raw.index(COMMENT) or return [raw, nil]
        [raw[0...at], raw[at..]]
      end

      # A quoted word's runs, joined, each undone as a shell undoes it: inside
      # single quotes nothing is special, and inside double quotes only a
      # backslash before `$`, a backtick, `"` or another backslash is.
      #
      # @param word [String] a match of {QUOTED}
      # @return [String]
      def unquoted(word)
        word.scan(RUN).map { |single, double, escaped| single || double&.gsub(/\\([$`"\\])/, "\\1") || escaped }.join
      end

      # Written beside the file and moved over it, so a crash half way leaves
      # the old tokens rather than half of the new. A link is written through,
      # since worktrees share one `.env` that way.
      #
      # @param text [String]
      # @return [void]
      def save(text)
        target = destination
        draft = "#{target}.#{Process.pid}.tmp"
        File.write(draft, text, perm: MODE)
        File.rename(draft, target)
      ensure
        File.delete(draft) if draft && File.exist?(draft)
      end

      # The file a link points at, through a chain of links, even when the
      # last one points at a file not made yet. Going by `File.exist?`, false
      # for such a link, put a plain file in the link's place and cut the
      # worktrees that share it off from what was written.
      #
      # @return [String]
      # @raise [OpenLanes::Error] on links that loop
      def destination
        link = path
        MAX_LINKS.times do
          return link unless File.symlink?(link)

          link = File.expand_path(File.readlink(link), File.dirname(link))
        end
        raise Error, "#{path}: more than #{MAX_LINKS} symbolic links to follow"
      end

      # @return [String]
      def quoted(value) = value.match?(BARE) ? value : "'#{value.gsub("'", "'\\\\''")}'"
    end
  end
end
