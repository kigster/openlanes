# frozen_string_literal: true

module OpenLanes
  module Uml
    # What the right-hand side of a constant assignment builds, when it
    # builds a type: `Data.define(...)` and `Struct.new(...)` make a value
    # type, `Class.new(Parent)` a class. Anything else (a frozen array, a
    # regex) is a plain constant and declares nothing.
    class Constructor
      VALUES = { "Data" => :define, "Struct" => :new }.freeze

      # @return [Symbol, nil] :value, :class, or nil for a plain constant
      attr_reader :kind

      # @return [Prism::Node, nil] the superclass `Class.new` was handed
      attr_reader :parent

      # @param node [Prism::Node] the assigned value
      def initialize(node)
        call = node.is_a?(Prism::CallNode) ? node : nil
        receiver = call&.receiver
        name = receiver.is_a?(Prism::ConstantReadNode) ? receiver.name.to_s : nil
        @kind = kind_of(name, call&.name)
        @parent = @kind == :class ? call.arguments&.arguments&.first : nil
      end

      private

      # @param receiver [String, nil]
      # @param message [Symbol, nil]
      # @return [Symbol, nil]
      def kind_of(receiver, message)
        return :value if receiver && VALUES[receiver] == message
        return :class if receiver == "Class" && message == :new

        nil
      end
    end
  end
end
