# frozen_string_literal: true

module OpenLanes
  class Config
    # The `commands:` part of the config schema, read off the dry-cli
    # registry rather than written by hand (S5): one property per command,
    # each holding exactly the options that command declares. A flag added
    # to a command is in the schema the next time it is built, and nobody
    # has to remember a second file.
    module CommandsSchema
      # A flag typed on the command line is a string, so a string option's
      # default in the file may be a number too: `commands.run.timeout: 1800`
      # was valid before the schema, and stays so.
      SCALAR = %w[string number].freeze

      # dry-cli's option types, as JSON Schema types.
      TYPES = { boolean: "boolean", integer: "integer", array: "array" }.freeze

      module_function

      # @param registry [Dry::CLI::Registry] a module extended with it
      # @return [Hash{String => Object}] the JSON Schema object for `commands:`
      def build(registry = OpenLanes::CLI)
        properties = commands(registry).sort.to_h { |name, command| [name, command_schema(name, command)] }
        { "type"                 => "object",
          "description"          => "Per-command option defaults, by command name: run, \"resync dirs\"",
          "default"              => {},
          "additionalProperties" => false,
          "properties"           => properties }
      end

      # @param registry [Dry::CLI::Registry]
      # @return [Hash{String => Class}] every command, by its full name
      def commands(registry)
        root = registry.instance_variable_get(:@commands).instance_variable_get(:@root)
        walk(root, []).to_h
      end

      # @param node [Dry::CLI::CommandRegistry::Node]
      # @param path [Array<String>]
      # @return [Array<Array(String, Class)>]
      def walk(node, path)
        own = node.command && !path.empty? ? [[path.join(" "), node.command]] : []
        own + node.children.flat_map { |name, child| walk(child, path + [name]) }
      end

      # @param name [String]
      # @param command [Class] a Dry::CLI::Command
      # @return [Hash{String => Object}]
      def command_schema(name, command)
        options = command.options.sort_by { it.name.to_s }.to_h { [it.name.to_s, option_schema(it)] }
        { "type"                 => "object",
          "description"          => portable(command.description.to_s.split("\n\n").first || "openlanes #{name}"),
          "default"              => {},
          "additionalProperties" => false,
          "properties"           => options }
      end

      # @param option [Dry::CLI::Option]
      # @return [Hash{String => Object}]
      def option_schema(option)
        type = TYPES.fetch(option.type&.to_sym, SCALAR)
        { "type"        => type,
          "items"       => ({ "type" => SCALAR } if type == "array"),
          "enum"        => option.values&.map(&:to_s),
          "description" => portable(option.options[:desc].to_s), # #desc appends the values, which enum already says
          "default"     => portable(option.default) }.compact
      end

      # The checked-in file is built on one machine and checked on every
      # other, so nothing may name the machine it was built on: the home
      # directory reads as `~`. A description's first paragraph is kept and
      # the rest dropped, since some commands list what is installed locally.
      #
      # @param value [Object]
      # @return [Object]
      def portable(value) = value.is_a?(String) ? value.gsub(Dir.home, "~") : value
    end
  end
end
