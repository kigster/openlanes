# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module CLI
    # `openlanes uml` — Mermaid class diagrams of the project being built, or
    # of OpenLanes itself, drawn from source that is parsed and never loaded.
    class Uml < Base
      # Standalone, because `uml self` draws the gem from anywhere; the
      # project's root is looked up only when the project is the target.
      standalone!
      desc "Print Mermaid class diagrams of the Ruby source, parsed with Prism and never loaded"

      argument :target, desc: "self to draw OpenLanes' own lib/, or a namespace to draw"
      argument :namespace, desc: "after self, the namespace to draw"

      option :output, aliases: ["-o"], desc: "Write here instead of STDOUT; - for STDOUT"
      option :directory, desc: "Write the map and one file per namespace into this directory"

      example ["                  # the namespace map of this project",
               "plans             # one namespace's class diagram",
               "self -o map.mmd   # OpenLanes' own map, to a file",
               "self --directory docs/architecture"]

      # @param target [String, nil]
      # @param namespace [String, nil]
      # @param options [Hash]
      # @return [void]
      def call(target: nil, namespace: nil, **options)
        drawing_self = target == "self"
        root = drawing_self ? OpenLanes::Uml::GEM_ROOT : project_root
        namespace = target unless drawing_self
        return write_all(root, options[:directory], options) if options[:directory]

        deliver(diagram(root, namespace), options[:output], options)
      end

      private

      # @return [String]
      def project_root
        Project.root || refuse("No project here: nothing in #{Dir.pwd} or above it holds " \
                               "#{Project::FILE}, #{OpenLanes::PLANS_DIR}/ or .git.",
          66)
      end

      # @return [String] Mermaid
      def diagram(root, namespace)
        return OpenLanes::Uml.map(root) unless namespace

        model = OpenLanes::Uml.model(root)
        OpenLanes::Uml::ClassDiagram.new(model, find_namespace(model, namespace)).render
      end

      # `plans`, `Plans` and `OpenLanes::Plans` all name one namespace.
      #
      # @return [String]
      def find_namespace(model, typed)
        names = model.namespace_names
        found = names.find { it == typed } || names.find { it.split("::").last.casecmp?(typed) || it.casecmp?(typed) }
        found || refuse("No namespace #{typed}. Namespaces: #{names.join(", ")}", 64)
      end

      # @return [void]
      def deliver(text, path, options)
        return $stdout.write(text) if path.nil? || path == "-"

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text)
        success("wrote the diagram to [#{path}]") unless quiet?(options)
      end

      # @return [void]
      def write_all(root, dir, options)
        title = root == OpenLanes::Uml::GEM_ROOT ? OpenLanes::Uml::SELF_TITLE : File.basename(root)
        written = OpenLanes::Uml.writer(root, title:).write(dir)
        success("wrote #{written.size} diagrams to [#{dir}]") unless quiet?(options)
      end
    end
  end
end
