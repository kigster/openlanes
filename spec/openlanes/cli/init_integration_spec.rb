# frozen_string_literal: true

require "open3"

# The end-to-end proof for plan 011: the real binary, in a real folder, with
# both API keys removed from its environment and nothing stubbed.
RSpec.describe "openlanes init, end to end" do
  let(:exe) { File.expand_path("../../../exe/openlanes", __dir__) }
  let(:top) { File.realpath(Dir.mktmpdir("openlanes-init-e2e")) }
  let(:repo) { File.join(top, "shop") }
  let(:env) { { "ANTHROPIC_API_KEY" => nil, "OPENAI_API_KEY" => nil, "NO_COLOR" => "1" } }

  before { FileUtils.mkdir_p(File.join(repo, ".git")) }
  after { FileUtils.rm_rf(top) }

  def init(*)
    out, err, status = Open3.capture3(env, exe, "init", *, chdir: repo, stdin_data: "")
    [out, err, status.exitstatus]
  end

  def read(path) = File.read(File.join(repo, path))

  context "with a Rails folder" do
    before do
      File.write(File.join(repo, "Gemfile"), "source 'https://rubygems.org'\ngem 'rails'\n")
      File.write(File.join(repo, "Gemfile.lock"), "GEM\n  specs:\n    rails (8.0.1)\n")
    end

    it "records every decision, writes stack.md and the CI file, and reconfigures with a diff" do
      _out, err, status = init("-y", "--ci", "github_actions", "--merge-by", "auto", "--quality", "mvp")
      expect([status, err]).to match([0, satisfy { !it.include?("Error") }])

      config = OpenLanes::Config.load(repo)
      expect(config).to have_attributes(ci: { provider: :github_actions, config: ".github/workflows/ci.yml" },
        merge_by: :auto,
        desired_codebase_quality: :mvp)
      expect([config.stack[:language], config.stack[:frameworks]]).to eq(["ruby", ["rails"]])
      expect(read("docs/decisions/stack.md")).to match(/ruby/i).and match(/rails/i)
      ci = read(".github/workflows/ci.yml")
      expect(ci).to include("bundle exec rspec")

      out, _err, status = init("--reconfigure", "-y", "--quality", "high")
      expect([status, out]).to match([0, include("- desired_codebase_quality: mvp", "+ desired_codebase_quality: high")])
      expect([read(".github/workflows/ci.yml"), OpenLanes::Config.load(repo).desired_codebase_quality]).to eq([ci, :high])
    end
  end

  context "with a folder holding two languages" do
    before do
      File.write(File.join(repo, "Gemfile"), "")
      File.write(File.join(repo, "go.mod"), "module shop\n")
    end

    it "writes no stack and no stack.md" do
      _out, _err, status = init("-y")
      expect([status, YAML.safe_load_file(File.join(repo, ".openlanes.yml")).key?("stack"),
              File.exist?(File.join(repo, "docs/decisions/stack.md"))]).to eq([0, false, false])
    end
  end
end
