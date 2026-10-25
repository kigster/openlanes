# frozen_string_literal: true

require "prism"

module OpenLanes
  module Uml
    # Reads one Ruby file with Prism and lists what it declares. The file is
    # parsed, never loaded: drawing a Rails application must not boot it, and
    # drawing a half-written file must not run its top level.
    class Parser < Prism::Visitor
      MIXINS = %i[include extend prepend].freeze

      # @param path [String] the file to read
      # @param file [String] the same path, as the diagram names it
      # @return [Array<OpenLanes::Uml::Definition>]
      def self.parse(path, file: path)
        visitor = new(file)
        Prism.parse_file(path).value.accept(visitor)
        visitor.definitions
      end

      # @return [Array<OpenLanes::Uml::Definition>]
      attr_reader :definitions

      # @param file [String]
      def initialize(file)
        super()
        @file = file
        @frames = []
        @definitions = []
      end

      # @param node [Prism::ClassNode]
      # @return [void]
      def visit_class_node(node)
        superclass = node.superclass && reference_to(node.superclass)
        node.superclass&.accept(self)
        within(declare(node.constant_path, :class, superclass:)) { node.body&.accept(self) }
      end

      # @param node [Prism::ModuleNode]
      # @return [void]
      def visit_module_node(node)
        within(declare(node.constant_path, :module)) { node.body&.accept(self) }
      end

      # `Task = Data.define(...)` is a value type of the class it sits in;
      # `Error = Class.new(StandardError)` is a class like any other.
      #
      # @param node [Prism::ConstantWriteNode]
      # @return [void]
      def visit_constant_write_node(node)
        Constructor.new(node.value).then do |made|
          declare_assigned(node.name.to_s, made) if made.kind
        end
        node.value.accept(self)
      end

      # @param node [Prism::CallNode]
      # @return [void]
      def visit_call_node(node)
        if frame && node.receiver.nil? && MIXINS.include?(node.name)
          frame.mixins.concat(Array(node.arguments&.arguments).filter_map { reference_to(it) })
        end
        super
      end

      # @param node [Prism::ConstantReadNode]
      # @return [void]
      def visit_constant_read_node(node) = note(node)

      # @param node [Prism::ConstantPathNode]
      # @return [void]
      def visit_constant_path_node(node) = note(node)

      private

      # @return [OpenLanes::Uml::Definition, nil] the innermost open declaration
      def frame = @frames.last

      def within(definition)
        @frames.push(definition)
        yield
      ensure
        @frames.pop
      end

      def declare(constant, kind, superclass: nil)
        name = [frame&.name, constant.full_name].compact.join("::").delete_prefix("::")
        Definition.open(name:, kind:, file: @file, superclass:).tap { @definitions << it }
      end

      # A value type folds into the class that declares it; one declared in a
      # module, or at the top, has no class to fold into and stands alone.
      def declare_assigned(constant, made)
        name = [frame&.name, constant].compact.join("::")
        owner = frame&.class? && made.kind == :value ? frame.name : nil
        kind = made.kind == :value && owner.nil? ? :class : made.kind
        superclass = made.parent && reference_to(made.parent)
        @definitions << Definition.open(name:, kind:, file: @file, superclass:, owner:)
      end

      def note(node)
        reference = reference_to(node)
        frame.references << reference if frame && reference
      end

      # @return [OpenLanes::Uml::Reference, nil] nil for `foo::Bar`, whose
      #   parent is a value the parser cannot know
      def reference_to(node)
        return nil unless node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)

        path = node.full_name
        path.start_with?("::") ? Reference.new(path: path.delete_prefix("::"), scope: []) : Reference.new(path:, scope:)
      rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
        nil
      end

      # @return [Array<String>] the lexical scopes, innermost first
      def scope = @frames.reverse.map(&:name)
    end
  end
end
