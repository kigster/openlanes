# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# A throwaway project of real Ruby files, for the specs that draw diagrams
# from source. The parser reads files; handing it strings would test a path
# the command never takes.
module RubyProject
  # @param files [Hash{String => String}] relative path to source
  # @yieldparam root [String]
  # @return [Object] the block's value
  def with_ruby_project(files)
    Dir.mktmpdir("uml-project") do |root|
      files.each do |path, source|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), source)
      end
      yield File.realpath(root)
    end
  end
end

RSpec.configure { |config| config.include RubyProject }
