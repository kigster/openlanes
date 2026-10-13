# frozen_string_literal: true

require "tmpdir"

# `pull-requests.md` is written by `create --prs` and read back by the state
# machine, so the two halves have to agree exactly. Every example here is a
# round trip rather than a string comparison: what matters is not how the
# markdown looks but that the parser recovers what the renderer put in.
RSpec.describe OpenLanes::Plans::PullRequests do
  def round_trip(prs)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, described_class::FILENAME), described_class.render(prs))
      described_class.new(dir:).all
    end
  end

  def pr(number:, title: "A change", state: "Merged 🟣", body: "It did a thing.")
    { number:, title:, state:, body:, url: "https://github.com/o/r/pull/#{number}" }
  end

  describe ".render" do
    it "recovers every pull request it wrote" do
      recovered = round_trip([pr(number: 12), pr(number: 15, state: "Open 🟡")])

      expect(recovered.map { |p| [p.number, p.state] }).to eq([["12", "Merged 🟣"], ["15", "Open 🟡"]])
    end

    # A pipe ends a cell, and "guard against a || b" is an ordinary title.
    it "survives a title containing a table delimiter" do
      recovered = round_trip([pr(number: 12, title: "Guard against a || b")])

      expect(recovered.first.title).to eq("Guard against a || b")
    end

    it "keeps the state machine's vocabulary, so the folder can be judged by it" do
      recovered = round_trip([pr(number: 12, state: "Merged 🟣")])

      expect(recovered.first).to be_merged
    end

    # The bodies are the raw material a retroactive spec.md is written from —
    # a specification cannot be synthesized from a list of numbers.
    it "writes each description below the table, where the parser ignores it" do
      rendered = described_class.render([pr(number: 12, body: "Adds /healthz and /readyz.")])

      aggregate_failures do
        expect(rendered).to include("Adds /healthz and /readyz.")
        expect(round_trip([pr(number: 12, body: "Adds /healthz and /readyz.")]).size).to eq(1)
      end
    end

    it "says so plainly when a pull request carried no description" do
      expect(described_class.render([pr(number: 12, body: "")])).to include("No description was written")
    end
  end

  # Found by a fixture, confirmed against `render` + `parse`: every title this
  # tool writes now opens with a plan number, so the row reads
  # `[[013.00] Ship it](url)` — and a markdown link whose text starts with `[`
  # does not parse. The title came back with the URL glued to it and the URL
  # came back nil, losing every pull request link on the index page and every
  # attachment on every Linear issue.
  describe "a title that already carries its plan number" do
    let(:round_trip) do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "pull-requests.md"),
          described_class.render([{ number: 4, title:, url: "https://example.com/repo/pull/4",
                                   state: "Merged 🟣", body: "why" }]))
        OpenLanes::Plans::PullRequests.new(dir:).all.first
      end
    end

    let(:title) { "[013.00] Ship the thing" }

    it "survives being written and read back" do
      expect(round_trip.title).to eq("[013.00] Ship the thing")
    end

    it "keeps the url, which is the part whose loss is not cosmetic" do
      expect(round_trip.url).to eq("https://example.com/repo/pull/4")
    end

    context "with a pipe in it as well, which ends a table cell" do
      let(:title) { "[013.00] Guard against a || b" }

      it "survives both escapes at once" do
        expect(round_trip).to have_attributes(title:, url: "https://example.com/repo/pull/4")
      end
    end
  end

  describe ".upsert", :tree do
    let(:path) { File.join(plans_root, "pull-requests.md") }
    let(:rows) { [{ number: 9, title: "[004.00](A) Needs a Reviewer", url: "https://github.com/example/repo/pull/9", state: "Open 🟡", body: "" }] }

    it "writes a whole document when the file does not exist" do
      described_class.upsert(path, rows)
      expect(described_class.new(dir: plans_root).all.map(&:number)).to eq(["9"])
    end

    # luke and rey sign pull-requests.md before any pull request exists. The
    # harness then records the pull request it opened, and used to rewrite
    # the file whole, which deleted their signatures.
    it "keeps ledger notes that were in the file before the table" do
      OpenLanes::Plans::Ledger.append(path, "> [2026-09-04 11:29:20 AM PDT] [ agent: luke-backend   status: Started, round 1 ]")
      described_class.upsert(path, rows)
      text = File.read(path)
      aggregate_failures do
        expect(text).to include("agent: luke-backend")
        expect(described_class.new(dir: plans_root).all.map(&:number)).to eq(["9"])
      end
    end

    it "replaces an existing table in place, keeping what is above and below it" do
      File.write(path, "# Pull Requests\n\n| Pull Request Number | Pull Request Name | Status |\n| --: | :-- | --: |\n| 3 | [old](https://github.com/example/repo/pull/3) | Open 🟡 |\n\n> [!NOTE]\n>\n> [2026-09-04 11:29:20 AM PDT] [ agent: rey-frontend   status: Completed, round 1 ]\n")
      described_class.upsert(path, rows + [{ number: 3, title: "old", url: "https://github.com/example/repo/pull/3", state: "Open 🟡", body: "" }])
      text = File.read(path)
      aggregate_failures do
        expect(text.scan("Pull Request Number").size).to eq(1)
        expect(text).to include("agent: rey-frontend")
        expect(described_class.new(dir: plans_root).all.map(&:number)).to contain_exactly("9", "3")
      end
    end
  end
end
