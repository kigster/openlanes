# frozen_string_literal: true

require "json"

module OpenLanes
  module Setup
    class ArchitectureScan
      # The package names one folder's dependency manifests declare.
      class Manifests
        # The files read for names, and that mark a folder as a project.
        FILES = %w[Gemfile Gemfile.lock package.json pyproject.toml requirements.txt go.mod Cargo.toml mix.exs].freeze

        # A package at the start of a line of requirements.txt or a TOML list.
        PYTHON_PACKAGE = /^\s*"?([A-Za-z0-9][\w.-]*)/

        # @param folder [String]
        def initialize(folder)
          @folder = folder
        end

        # @return [Array<String>]
        def names = (gems + packages + python).uniq

        private

        # @return [Array<String>]
        def gems
          read("Gemfile.lock").scan(/^\s+([\w.-]+) \(/).flatten + read("Gemfile").scan(/^\s*gem ['"]([\w.-]+)['"]/).flatten
        end

        # @return [Array<String>]
        def packages
          package = JSON.parse(read("package.json"))
          return [] unless package.is_a?(Hash)

          %w[dependencies devDependencies].flat_map { package.fetch(it, {}).keys }
        rescue JSON::ParserError
          []
        end

        # @return [Array<String>]
        def python = (read("requirements.txt") + read("pyproject.toml")).scan(PYTHON_PACKAGE).flatten.map(&:downcase)

        # @return [String] empty when the file is absent
        def read(name)
          path = File.join(@folder, name)
          File.file?(path) ? File.read(path, encoding: "UTF-8").scrub : ""
        end
      end
    end
  end
end
