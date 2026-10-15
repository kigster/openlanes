# frozen_string_literal: true

# Each namespace answers for itself through a handful of module methods, so
# the CLI never has to know which class inside it does the work. These pin
# that every front door opens onto the class it names.
RSpec.describe "module facades", :tree do
  let!(:dir) do
    plans { |t| t.plan "001.00", :new, "first", files: { "spec.md" => spec_body } }
  end

  let(:tree) { OpenLanes::Plans.tree(dir) }

  describe OpenLanes::Plans do
    it "opens the tree it was given" do
      expect(tree.features.map(&:slug)).to eq(%w[first])
    end

    it "parses an ordinal" do
      expect(described_class.ordinal("1").to_s).to eq("001.00")
    end

    it "parses a folder into a feature" do
      expect(described_class.feature(tree.features.first.path).slug).to eq("first")
    end

    it "wraps a feature as a subject" do
      expect(described_class.subject(tree.features.first)).to be_a(OpenLanes::Plans::Subject)
    end

    it "opens a plan's mailbox" do
      expect(described_class.mailbox(tree.features.first.path).messages).to eq([])
    end

    it "builds the index" do
      expect(described_class.index(tree:, project: "X").render).to include("001.00")
    end
  end

  describe OpenLanes::Lifecycle do
    it "reports nothing to rename in a tree whose names are honest" do
      expect(described_class.resync_dirs(tree:).call(commit: false)).to be_empty
    end

    it "creates the next plan" do
      result = described_class.create(dir:, words: %w[second plan])
      expect(File.basename(result.value!)).to start_with("002.00")
    end
  end

  describe OpenLanes::Agents do
    it "loads the shipped definitions" do
      expect(described_class.registry.find("luke-backend")).to be_a(OpenLanes::Agents::Agent)
    end

    it "finds one agent by name" do
      expect(described_class.find("hansolo-reviewer").name).to eq("hansolo-reviewer")
    end
  end

  describe OpenLanes::Engine do
    it "places the restart file in the tree" do
      expect(described_class.state_file(tree).path).to eq(File.join(dir, OpenLanes::Engine::StateFile::FILENAME))
    end
  end

  describe OpenLanes::Execution do
    it "builds an executor rooted where it is told" do
      expect(described_class.executor(root: dir, dry_run: true)).to be_a(OpenLanes::Execution::Executor)
    end
  end

  describe OpenLanes::Vcs do
    it "builds a worktree manager" do
      expect(described_class.worktree(root: dir)).to be_a(OpenLanes::Vcs::Worktree)
    end

    it "builds a publisher" do
      expect(described_class.publisher(root: dir, dry_run: true)).to be_a(OpenLanes::Vcs::Publisher)
    end
  end

  describe OpenLanes::Apps do
    let(:definition) do
      OpenLanes::Apps::Definition.new(kind: "web", processes: [OpenLanes::Apps::ProcessSpec.new(name: "web", start: "x")])
    end

    it "reads the app a config declares, and nil when it declares none" do
      expect([described_class.definition(OpenLanes::Config.new(app: definition)), described_class.definition(OpenLanes::Config.new)])
        .to eq([definition, nil])
    end

    it "builds the registry, a supervisor, a watcher and a runner" do
      built = [described_class.registry(path: File.join(dir, "ports.json")),
               described_class.supervisor(definition:, root: dir, plan: "012.00", branch: "b"),
               described_class.watcher(root: dir, definition:),
               described_class.runner(definition:, root: dir, plan: "012.00", branch: "b")]
      expect(built.map(&:class)).to eq([OpenLanes::Apps::Ports, OpenLanes::Apps::Supervisor, OpenLanes::Apps::Watcher, OpenLanes::Apps::Runner])
    end
  end

  describe OpenLanes::Presentation do
    it "derives the conventions document" do
      expect(described_class.documentation).to include("New")
    end

    it "draws the state diagram" do
      expect(described_class.diagram).not_to be_empty
    end

    it "reports on a tree" do
      expect(described_class.reporter(tree:).render).to include("001.00")
    end
  end
end
