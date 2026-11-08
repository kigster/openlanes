# frozen_string_literal: true

# Where the operator's own lessons live. The suite overrides it outright
# (spec_helper), so these examples pass their own env.
RSpec.describe OpenLanes::Memory do
  describe ".global_dir" do
    it "prefers $OPENLANES_MEMORY_HOME" do
      expect(described_class.global_dir(env: { "OPENLANES_MEMORY_HOME" => "/srv/lessons" })).to eq("/srv/lessons")
    end

    it "uses the XDG config directory" do
      expect(described_class.global_dir(env: { "XDG_CONFIG_HOME" => "/cfg" })).to eq("/cfg/openlanes/memory/lessons")
    end

    it "falls back to ~/.config when XDG_CONFIG_HOME is unset or relative, as the XDG spec requires" do
      home = File.join(Dir.home, ".config", "openlanes", "memory", "lessons")
      expect([described_class.global_dir(env: {}), described_class.global_dir(env: { "XDG_CONFIG_HOME" => "cfg" })])
        .to eq([home, home])
    end
  end

  describe ".section" do
    let(:root) { Dir.mktmpdir("project") }

    after { FileUtils.rm_rf(root) }

    it "reads the project's lessons and the global ones for one agent" do
      write_lesson(File.join(root, described_class::PROJECT_DIR), "L-1", lesson_meta("L-1", title: "Project rule"))
      write_lesson(ENV.fetch("OPENLANES_MEMORY_HOME"), "G-1", lesson_meta("G-1", title: "Operator rule"))

      expect(described_class.section(agent: OpenLanes::Agents.find("backend-coder"), root:))
        .to include("L-1 (medium) Project rule", "G-1 (medium) Operator rule")
    ensure
      FileUtils.rm_rf(Dir.glob(File.join(ENV.fetch("OPENLANES_MEMORY_HOME"), "*")))
    end
  end
end
