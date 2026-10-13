# frozen_string_literal: true

# Real directories: a source of fixture skills and a destination, both thrown
# away afterwards. The suite never touches ~/.agents/skills.
RSpec.describe OpenLanes::Skills::Installer do
  subject(:installer) { OpenLanes::Skills.installer(into:, source:) }

  let(:top) { File.realpath(Dir.mktmpdir("openlanes-skills")) }
  let(:source) { File.join(top, "skills") }
  let(:into) { File.join(top, "home", ".agents", "skills") }

  after { FileUtils.rm_rf(top) }

  def skill(name, description)
    FileUtils.mkdir_p(File.join(source, name, "references"))
    File.write(File.join(source, name, "SKILL.md"), "---\nname: #{name}\ndescription: #{description}\n---\n\n# #{name}\n")
    File.write(File.join(source, name, "references", "notes.md"), "notes for #{name}\n")
  end

  def actions(outcomes) = outcomes.to_h { [it.skill.name, it.action] }

  before do
    skill("alpha", "Does the first thing. Then more.")
    skill("beta", "Does the second thing.")
  end

  it "copies every skill, whole directories included" do
    installer.call
    expect(File.read(File.join(into, "alpha", "references", "notes.md"))).to eq("notes for alpha\n")
  end

  it "copies rather than links" do
    installer.call
    expect(File.symlink?(File.join(into, "alpha"))).to be(false)
  end

  it "reports each one installed" do
    expect(actions(installer.call)).to eq("alpha" => :installed, "beta" => :installed)
  end

  context "with a skill already there" do
    before do
      FileUtils.mkdir_p(File.join(into, "alpha"))
      File.write(File.join(into, "alpha", "SKILL.md"), "mine\n")
    end

    it "keeps it" do
      outcomes = installer.call
      expect([actions(outcomes), File.read(File.join(into, "alpha", "SKILL.md"))])
        .to eq([{ "alpha" => :kept, "beta" => :installed }, "mine\n"])
    end

    it "replaces it under overwrite" do
      outcomes = installer.call(overwrite: true)
      expect([actions(outcomes), File.read(File.join(into, "alpha", "SKILL.md"))])
        .to match([{ "alpha" => :replaced, "beta" => :installed }, include("name: alpha")])
    end
  end

  # Replacing what a link points at would rewrite somebody's checkout.
  context "with a link where a skill goes" do
    let(:elsewhere) { File.join(top, "checkout", "alpha") }

    before do
      FileUtils.mkdir_p([elsewhere, into])
      File.write(File.join(elsewhere, "SKILL.md"), "theirs\n")
      File.symlink(elsewhere, File.join(into, "alpha"))
    end

    it "removes the link and leaves its target alone" do
      installer.call(overwrite: true)
      expect([File.symlink?(File.join(into, "alpha")), File.read(File.join(elsewhere, "SKILL.md"))])
        .to eq([false, "theirs\n"])
    end
  end

  it "changes nothing on a dry run" do
    outcomes = installer.call(dry_run: true)
    expect([actions(outcomes).values.uniq, Dir.exist?(into)]).to eq([[:installed], false])
  end
end
