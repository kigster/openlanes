# frozen_string_literal: true

require "open3"
require "tmpdir"

# The gem ships the control room as web/dist, a build product nobody commits.
# These examples hold the build order in place: a gem built before the page
# would install a control room that serves a 404, and nothing else would say so.
RSpec.describe "packaging" do
  let(:root) { File.expand_path("../..", __dir__) }

  # Recipe name => [dependencies, body], read from the justfile's own layout:
  # a header at column 0 (`name params: deps`), its body indented beneath.
  def recipes
    current = nil
    File.readlines(File.join(root, "justfile"), chomp: true).each_with_object({}) do |line, found|
      if (header = line.match(/\A([a-z][\w-]*)[^:]*:(?!=)(.*)\z/))
        current = header[1]
        found[current] = [header[2].split.map { |dep| dep.delete_prefix("(").split("(").first }, +""]
      elsif line.match?(/\A\s+\S/) && current
        found[current][1] << line << "\n"
      elsif !line.strip.empty?
        current = nil
      end
    end
  end

  def depends_on?(table, name, target, seen = [])
    return true if name == target
    return false if seen.include?(name) || !table.key?(name)

    table[name][0].any? { |dep| depends_on?(table, dep, target, seen + [name]) }
  end

  it "keeps web/dist out of git" do
    expect(File.readlines(File.join(root, ".gitignore"), chomp: true)).to include("/web/dist")
  end

  it "builds the page before every justfile recipe that builds the gem" do
    table = recipes
    builders = table.select { |_, (_, body)| body.match?(/\bgem build\b/) }.keys

    expect(builders).not_to be_empty
    expect(builders).to all(satisfy { |name| depends_on?(table, name, "web-build") })
  end

  it "aborts gem build when web/dist/index.html is missing, naming just web-build" do
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(root, "openlanes.gemspec"), dir)
      FileUtils.mkdir_p(File.join(dir, "lib", "openlanes"))
      FileUtils.cp(File.join(root, "lib", "openlanes", "version.rb"), File.join(dir, "lib", "openlanes"))
      script = '$0 = "gem"; ARGV.replace(["build"]); load "openlanes.gemspec"'

      _out, err, status = Open3.capture3(RbConfig.ruby, "-e", script, chdir: dir)

      expect(status).not_to be_success
      expect(err).to include("web/dist/index.html is missing").and include("just web-build")
    end
  end

  # Plan 035: `openlanes setup` bundles the shipped Brewfile; bin/ holds
  # contributor tools, which an installed gem cannot run.
  describe "the gem's files" do
    let(:files) { Gem::Specification.load(File.join(root, "openlanes.gemspec")).files }

    it "ships the runtime Brewfile and not the contributor's" do
      expect(files).to include("Brewfile")
      expect(files).not_to include("Brewfile.dev")
    end

    it "ships nothing from bin/" do
      expect(files.grep(%r{\Abin/})).to be_empty
    end

    it "keeps bin/setup bundling both Brewfiles in a checkout" do
      script = File.read(File.join(root, "bin", "setup"))
      expect(script).to include('--file="${project_root}/Brewfile"', '--file="${project_root}/Brewfile.dev"')
    end

    it "lists in the Brewfile every tool the engine shells out to" do
      brews = File.read(File.join(root, "Brewfile")).scan(/^brew '([^']+)'/).flatten
      expect(brews).to include("git", "gh", "redis", "just", "imagemagick", "vips", "jq")
    end
  end

  describe "README.md" do
    let(:readme) { File.read(File.join(root, "README.md")) }

    it "names the binary, port and config file the code uses" do
      expect(readme).to include("openlanes run", "127.0.0.1:11000", ".openlanes.yml")
    end

    # `agentilda-ai-setup` is a real repository the README links, so a bare
    # `tilda` would match it; the retired binary is the whole word.
    it "names none of the retired ones" do
      expect(readme).not_to match(/\btilda\b|4747|agentilda:/)
    end
  end
end
