# frozen_string_literal: true

module OpenLanes
  module Skills
    # One bundled skill: a directory holding a `SKILL.md` whose frontmatter
    # names and describes it.
    #
    # @!attribute [r] name
    #   @return [String] the frontmatter `name`, else the directory's
    # @!attribute [r] description
    #   @return [String] the whole frontmatter `description`
    # @!attribute [r] path
    #   @return [String] the skill's directory
    Skill = Data.define(:name, :description, :path) do
      # What `skills install -h` prints beside the name: a description is
      # written for an agent deciding whether to load it, and runs long.
      #
      # @return [String]
      def summary = description.split(/(?<=[.!?])\s+/, 2).first.to_s.strip

      # @param into [String]
      # @return [Boolean] whether a skill of this name is already there
      def installed?(into) = File.exist?(File.join(into, name)) || File.symlink?(File.join(into, name))
    end

    class Skill
      FILENAME = "SKILL.md"

      # @param dir [String]
      # @return [Array<OpenLanes::Skills::Skill>] every `<dir>/*/SKILL.md`, by name
      def self.all(dir)
        Dir.glob(File.join(dir, "*", FILENAME)).map { load(File.dirname(it)) }.sort_by(&:name)
      end

      # @param path [String] a skill directory
      # @return [OpenLanes::Skills::Skill]
      def self.load(path)
        meta = frontmatter(File.read(File.join(path, FILENAME), encoding: "UTF-8"))
        new(name: meta.fetch("name", File.basename(path)).to_s,
          description: meta.fetch("description", "").to_s.gsub(/\s+/, " ").strip,
          path:)
      end

      # Agents read a SKILL.md leniently, and a description with `word: word`
      # in it is not valid YAML as a plain scalar. Refusing such a skill
      # here would hide one the agents load fine, so a header YAML rejects
      # is read a line at a time instead.
      #
      # @param text [String]
      # @return [Hash{String => String}]
      def self.frontmatter(text)
        Frontmatter.split(text).first
      rescue Psych::Exception
        header = text[/\A---\s*\n(.*?)\n---/m, 1].to_s
        header.scan(/^([a-z][\w-]*):[ \t]*(.*)$/).to_h.transform_values { it.strip.delete_prefix('"').delete_suffix('"') }
      end
      private_class_method :frontmatter
    end
  end
end
