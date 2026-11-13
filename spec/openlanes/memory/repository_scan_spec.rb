# frozen_string_literal: true

require "open3"

# The `.openlanes/` folder is committed with the project, so a secret typed
# into it by hand would be published with the next push. This spec runs the
# same scan CI runs over the repository's own folder, so the build fails on
# one, and holds the folder to the rule that nothing under it is ignored and
# nothing a running process owns is kept there.
RSpec.describe "the committed .openlanes folder" do
  let(:root) { File.expand_path("../../..", __dir__) }
  let(:folder) { File.join(root, OpenLanes::Memory::ROOT_DIR) }

  # What a running process owns churns on every run, and does not belong in
  # a folder a person reviews.
  let(:process_owned) { [/\.lock\z/, /\.pid\z/, %r{(\A|/)cache/}, %r{(\A|/)traces/}, %r{(\A|/)usage\.json\z}] }

  it "holds no secret" do
    expect(OpenLanes::Memory.secrets(root:)).to eq({})
  end

  it "has nothing git ignores" do
    expect(OpenLanes::Memory.ignored(root:)).to eq([])
  end

  it "has no rule in .gitignore that would match a file under it" do
    probe = File.join(OpenLanes::Memory::ROOT_DIR, "memory", "lessons", "L-0001-probe.md")
    out, = Open3.capture2("git", "-C", root, "check-ignore", "--no-index", probe, err: File::NULL)

    expect(out).to eq("")
  end

  it "holds nothing a running process owns" do
    files = File.directory?(folder) ? Dir.glob("**/*", File::FNM_DOTMATCH, base: folder) : []

    expect(files.select { |path| process_owned.any? { path.match?(it) } }).to eq([])
  end

  context "with a fake key planted in a copy" do
    let(:copy) { Dir.mktmpdir("openlanes-scan") }
    let(:fake) { "sk-ant-api03-#{"A1b2C3d4" * 6}" }

    after { FileUtils.rm_rf(copy) }

    it "fails on it, naming the file and line but not the value" do
      FileUtils.cp_r(folder, copy) if File.directory?(folder)
      planted = File.join(copy, OpenLanes::Memory::ROOT_DIR, "memory", "inbox", "planted.md")
      FileUtils.mkdir_p(File.dirname(planted))
      File.write(planted, "---\ntitle: harmless\n---\n\nkey: #{fake}\n")

      found = OpenLanes::Memory.secrets(root: copy)

      expect(found.keys).to eq([planted])
      expect(found.values.join).not_to include(fake)
    end
  end
end
