# frozen_string_literal: true

require "digest"

RSpec.describe OpenLanes::Web::PlanFiles, :tree do
  subject(:files) { described_class.new(plans_dir: plans_root) }

  let(:spec_md) { "---\nstarts: research\ncreated: 2026-10-15\n---\n\n# The spec\n" }
  let(:folder) do
    plans do |t|
      t.plan("017.00",
        :blocked,
        "view-markdowns",
        files: { "spec.md" => spec_md, "plan.md" => "# The plan\n", "blocked.md" => "## B1 Which\n", "notes.txt" => "no" })
    end
    Dir[File.join(plans_root, "017.00*")].first
  end

  before { folder }

  def etag_of(body) = %("#{Digest::SHA256.hexdigest(body)}")

  describe "#list" do
    it "lists the readable names the folder has, in whitelist order" do
      expect(files.list("017")).to eq(%w[spec.md plan.md blocked.md])
    end

    it "lists all six when the folder has all six" do
      described_class::READABLE.each { File.write(File.join(folder, it), "# #{it}\n") }
      expect(files.list("017.00")).to eq(described_class::READABLE)
    end

    it "lists none for an empty folder" do
      plans { |t| t.plan("018.00", :new, "empty") }
      expect(files.list("018.00")).to eq([])
    end

    it "refuses a plan that does not exist" do
      expect { files.list("099.00") }.to raise_error(described_class::NotFound, "there is no plan 099.00")
    end

    it "refuses an ordinal that is not one" do
      expect { files.list("abc") }.to raise_error(described_class::NotFound, "not a plan number")
    end
  end

  describe "#read" do
    it "returns the raw bytes and their quoted SHA-256" do
      expect(files.read("017.00", "spec.md").to_h).to eq(body: spec_md, etag: etag_of(spec_md))
    end

    it "refuses a name off the whitelist" do
      expect { files.read("017.00", "notes.txt") }.to raise_error(described_class::NotFound, "not a plan file: notes.txt")
    end

    it "refuses a traversing name" do
      expect { files.read("017.00", "../spec.md") }.to raise_error(described_class::NotFound)
    end

    it "refuses a whitelisted file the plan does not have" do
      expect { files.read("017.00", "design.md") }.to raise_error(described_class::NotFound, "017.00 has no design.md")
    end
  end

  describe "#write" do
    let(:edited) { spec_md.sub("# The spec", "# The spec, edited") }

    it "writes the file and returns its new ETag" do
      etag = files.write("017.00", "spec.md", body: edited, if_match: etag_of(spec_md))
      expect([etag, File.read(File.join(folder, "spec.md"))]).to eq([etag_of(edited), edited])
    end

    it "leaves no temp file behind" do
      files.write("017.00", "spec.md", body: edited, if_match: etag_of(spec_md))
      expect(Dir.children(folder).sort).to eq(%w[blocked.md notes.txt plan.md spec.md])
    end

    it "refuses a stale ETag and leaves the file alone" do
      expect { files.write("017.00", "spec.md", body: edited, if_match: etag_of("older")) }
        .to raise_error(described_class::Stale, "spec.md changed since it was read; reload it")
      expect(File.read(File.join(folder, "spec.md"))).to eq(spec_md)
    end

    it "refuses changed frontmatter in spec.md" do
      body = edited.sub("starts: research", "starts: building")
      expect { files.write("017.00", "spec.md", body:, if_match: etag_of(spec_md)) }
        .to raise_error(described_class::FrontmatterChanged, "the frontmatter of spec.md is locked")
      expect(File.read(File.join(folder, "spec.md"))).to eq(spec_md)
    end

    it "refuses frontmatter removed from spec.md" do
      expect { files.write("017.00", "spec.md", body: "# The spec\n", if_match: etag_of(spec_md)) }
        .to raise_error(described_class::FrontmatterChanged)
    end

    it "refuses frontmatter added to a plan.md that had none" do
      expect { files.write("017.00", "plan.md", body: "---\nstarts: building\n---\n# The plan\n", if_match: etag_of("# The plan\n")) }
        .to raise_error(described_class::FrontmatterChanged, "the frontmatter of plan.md is locked")
    end

    it "writes a plan.md body with no frontmatter" do
      files.write("017.00", "plan.md", body: "# The plan, v2\n", if_match: etag_of("# The plan\n"))
      expect(File.read(File.join(folder, "plan.md"))).to eq("# The plan, v2\n")
    end

    it "refuses blocked.md as read only" do
      expect { files.write("017.00", "blocked.md", body: "x", if_match: etag_of("## B1 Which\n")) }
        .to raise_error(described_class::ReadOnly, "blocked.md is read only")
    end

    it "refuses an unknown ordinal" do
      expect { files.write("099.00", "spec.md", body: "x", if_match: "x") }.to raise_error(described_class::NotFound)
    end
  end
end
