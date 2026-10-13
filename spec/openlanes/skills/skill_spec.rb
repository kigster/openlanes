# frozen_string_literal: true

RSpec.describe OpenLanes::Skills::Skill do
  let(:dir) { File.realpath(Dir.mktmpdir("openlanes-skill")) }

  after { FileUtils.rm_rf(dir) }

  def write(name, header)
    FileUtils.mkdir_p(File.join(dir, name))
    File.write(File.join(dir, name, "SKILL.md"), "---\n#{header}---\n\n# Body\n")
  end

  it "reads the name and description from the frontmatter" do
    write("x", "name: alpha\ndescription: Does a thing. Use it often.\n")
    expect(described_class.all(dir).first).to have_attributes(name: "alpha", summary: "Does a thing.")
  end

  it "falls back to the directory name" do
    write("gamma", "description: Something.\n")
    expect(described_class.all(dir).map(&:name)).to eq(%w[gamma])
  end

  # Agents read SKILL.md leniently, and `word: word` inside a plain scalar is
  # not valid YAML, so a header YAML rejects is still read.
  it "reads a header that is not valid YAML" do
    write("delta", "name: delta\ndescription: Create a plan: choose the lane. Then stop.\n")
    expect(described_class.all(dir).first).to have_attributes(name: "delta", summary: "Create a plan: choose the lane.")
  end

  it "says whether a skill is already in a directory" do
    write("alpha", "name: alpha\ndescription: A.\n")
    target = File.join(dir, "installed")
    FileUtils.mkdir_p(File.join(target, "alpha"))
    expect(described_class.all(dir).first.installed?(target)).to be(true)
  end
end
