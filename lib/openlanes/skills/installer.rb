# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module Skills
    # Copies the bundled skills into a skill directory.
    #
    # Copies, never links: a link into the gem's versioned install path
    # dangles the moment `gem cleanup` removes that version, and the skill
    # disappears with no error anywhere. Re-running after an upgrade is the
    # price, and the report says what that run changed.
    class Installer
      # What happened to one skill.
      #
      # @!attribute [r] skill
      #   @return [OpenLanes::Skills::Skill]
      # @!attribute [r] action
      #   @return [Symbol] :installed, :kept or :replaced
      # @!attribute [r] target
      #   @return [String]
      Outcome = Data.define(:skill, :action, :target)

      # @param into [String] the destination directory
      # @param skills [Array<OpenLanes::Skills::Skill>]
      def initialize(into:, skills:)
        @into = File.expand_path(into)
        @skills = skills
      end

      # @return [String]
      attr_reader :into

      # @param overwrite [Boolean] replace a skill already there
      # @param dry_run [Boolean] decide, and change nothing
      # @return [Array<Outcome>]
      def call(overwrite: false, dry_run: false)
        @skills.map do |skill|
          target = File.join(into, skill.name)
          action = action_for(skill, overwrite)
          copy(skill, target, replacing: action == :replaced) unless dry_run || action == :kept
          Outcome.new(skill:, action:, target:)
        end
      end

      private

      # @return [Symbol]
      def action_for(skill, overwrite)
        return :installed unless skill.installed?(into)

        overwrite ? :replaced : :kept
      end

      # A link already standing where the skill goes is removed, not
      # followed: replacing what it points at would edit somebody's checkout.
      #
      # @return [void]
      def copy(skill, target, replacing:)
        if replacing
          File.symlink?(target) ? File.unlink(target) : FileUtils.rm_rf(target)
        end
        FileUtils.mkdir_p(into)
        FileUtils.cp_r(skill.path, target)
      end
    end
  end
end
