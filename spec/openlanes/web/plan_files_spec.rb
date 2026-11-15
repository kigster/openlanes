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

    it "lists every readable name when the folder has them all" do
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

    it "leaves out a symlink, whether it points outside the folder or at a sibling" do
      outside = File.join(plans_root, "..", "outside.txt")
      File.write(outside, "not a plan file\n")
      File.symlink(outside, File.join(folder, "design.md"))
      File.symlink(File.join(folder, "spec.md"), File.join(folder, "research.md"))
      expect(files.list("017.00")).to eq(%w[spec.md plan.md blocked.md])
    end

    it "lists a plan whose .plans directory is itself reached through a symlink" do
      link = "#{plans_root}-link"
      File.symlink(plans_root, link)
      expect(described_class.new(plans_dir: link).list("017.00")).to eq(%w[spec.md plan.md blocked.md])
    ensure
      File.delete(link)
    end
  end

  # A transition renames the folder between the tree scan and the read. The scan is stubbed to answer with a
  # path that is gone, as a request that scanned a moment too early would hold it.
  describe "a folder renamed mid-request" do
    let(:stale) do
      feature = instance_double(OpenLanes::Plans::Feature, path: "#{folder}-moved")
      instance_double(OpenLanes::Plans::Tree, find: instance_double(OpenLanes::Plans::Subject, feature:))
    end

    def scan_stale(times:)
      scans = 0
      allow(OpenLanes::Plans).to receive(:tree).and_wrap_original do |tree, dir|
        (scans += 1) <= times ? stale : tree.call(dir)
      end
    end

    it "lists the folder on the second pass" do
      scan_stale(times: 1)
      expect(files.list("017.00")).to eq(%w[spec.md plan.md blocked.md])
    end

    it "raises not-found, rather than listing nothing, when the folder is still gone" do
      scan_stale(times: 9)
      expect { files.list("017.00") }
        .to raise_error(described_class::NotFound, "plan 017.00 moved while it was read; try again")
      expect(OpenLanes::Plans).to have_received(:tree).twice
    end

    it "reads the file on the second pass" do
      scan_stale(times: 1)
      expect(files.read("017.00", "plan.md").body).to eq("# The plan\n")
    end

    it "raises not-found for a file that vanishes between the check and the read" do
      allow(File).to receive(:size).and_call_original
      allow(File).to receive(:size).with(File.join(folder, "plan.md")).and_raise(Errno::ENOENT)
      expect { files.read("017.00", "plan.md") }.to raise_error(described_class::NotFound, /moved while it was read/)
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

    it "refuses a symlink to a file outside the folder as if it were absent" do
      outside = File.join(plans_root, "..", "outside.txt")
      File.write(outside, "not a plan file\n")
      File.symlink(outside, File.join(folder, "design.md"))
      expect { files.read("017.00", "design.md") }.to raise_error(described_class::NotFound, "017.00 has no design.md")
    end

    it "serves a file of exactly the cap" do
      File.write(File.join(folder, "research.md"), "x" * described_class::MAX_BYTES)
      expect(files.read("017.00", "research.md").body.bytesize).to eq(described_class::MAX_BYTES)
    end

    it "refuses a file over the cap, saying how large it is" do
      File.write(File.join(folder, "research.md"), "x" * (described_class::MAX_BYTES + 1))
      expect { files.read("017.00", "research.md") }
        .to raise_error(described_class::TooLarge, "research.md is 1025 KB; files over 1024 KB are not shown here")
    end

    it "refuses a file that grew past the cap after its size was taken" do
      path = File.join(folder, "research.md")
      File.write(path, "x" * (described_class::MAX_BYTES + 1))
      allow(File).to receive(:size).and_call_original
      allow(File).to receive(:size).with(path).and_return(10)
      expect { files.read("017.00", "research.md") }.to raise_error(described_class::TooLarge)
    end

    it "refuses bytes that are not UTF-8" do
      File.binwrite(File.join(folder, "research.md"), "\xFF\xFE binary".b)
      expect { files.read("017.00", "research.md") }
        .to raise_error(described_class::NotText, "research.md is not UTF-8 text, so it cannot be shown")
    end

    it "refuses a NUL byte, which is valid UTF-8 and still not text" do
      File.binwrite(File.join(folder, "research.md"), "# Title\0\n")
      expect { files.read("017.00", "research.md") }.to raise_error(described_class::NotText)
    end

    it "serves multibyte UTF-8" do
      File.write(File.join(folder, "research.md"), "# Caf\u00e9 \u2b50\n")
      expect(files.read("017.00", "research.md").body).to eq("# Caf\u00e9 \u2b50\n")
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

    it "refuses a body over the cap and leaves the file alone" do
      body = spec_md + ("x" * described_class::MAX_BYTES)
      expect { files.write("017.00", "spec.md", body:, if_match: etag_of(spec_md)) }.to raise_error(described_class::TooLarge)
      expect(File.read(File.join(folder, "spec.md"))).to eq(spec_md)
    end

    it "refuses to write through a symlink" do
      outside = File.join(plans_root, "..", "outside.md")
      File.write(outside, "# Outside\n")
      File.delete(File.join(folder, "plan.md"))
      File.symlink(outside, File.join(folder, "plan.md"))
      expect { files.write("017.00", "plan.md", body: "# Mine\n", if_match: etag_of("# Outside\n")) }
        .to raise_error(described_class::NotFound)
      expect(File.read(outside)).to eq("# Outside\n")
    end

    it "refuses blocked.md as read only" do
      expect { files.write("017.00", "blocked.md", body: "x", if_match: etag_of("## B1 Which\n")) }
        .to raise_error(described_class::ReadOnly, "blocked.md is read only")
    end

    it "lists and reads pull-requests.md but refuses to write it" do
      File.write(File.join(folder, "pull-requests.md"), "# Pull Requests\n")
      expect(files.list("017.00").last).to eq("pull-requests.md")
      expect(files.read("017.00", "pull-requests.md").body).to eq("# Pull Requests\n")
      expect { files.write("017.00", "pull-requests.md", body: "x", if_match: etag_of("# Pull Requests\n")) }
        .to raise_error(described_class::ReadOnly, "pull-requests.md is read only")
    end

    it "refuses an unknown ordinal" do
      expect { files.write("099.00", "spec.md", body: "x", if_match: "x") }.to raise_error(described_class::NotFound)
    end
  end
end
