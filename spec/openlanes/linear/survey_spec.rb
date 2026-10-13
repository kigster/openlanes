# frozen_string_literal: true

# The survey exists because the import cannot see Linear, so someone has to
# answer "is any of this already there under another name?" before an import
# creates a twin. Both matching rules are exact after normalising; everything
# fuzzier is reported as a guess, never silently acted on.
RSpec.describe OpenLanes::Linear::Survey, :tree do
  let!(:tree) do
    plans do |t|
      t.plan "201.00",
        :new,
        "ledger-carryforward-vintages",
        files: { "spec.md" => spec_body(title: "Ledger Carryforward Vintages",
          goal: "Track ledger vintages precisely.") }
      t.plan "202.00", :new, "plaid-integration"
      t.plan "203.00", :new, "app-web"
    end
  end

  def survey(projects)
    described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), projects:)
  end

  def project(id, name, **extra)
    { "id" => id, "name" => name, "url" => "https://linear.app/t/project/#{id}" }.merge(extra)
  end

  describe "#matches" do
    let(:reconciled) do
      survey([project("p-ord", "Gem work 201.00 continued"),
              project("p-slug", "Plaid Integration"),
              project("p-hand", "Payments Platform")])
    end

    it "recognises a project whose name carries the plan number" do
      match = reconciled.matches.find { |m| m.project["id"] == "p-ord" }

      aggregate_failures do
        expect(match.subject.feature.slug).to eq("ledger-carryforward-vintages")
        expect(match.rule).to eq(:ordinal)
        expect(match.why).to eq("its name carries the plan number")
      end
    end

    it "recognises a project whose name is the plan's slug, however it was capitalised" do
      match = reconciled.matches.find { |m| m.project["id"] == "p-slug" }

      aggregate_failures do
        expect(match.subject.feature.slug).to eq("plaid-integration")
        expect(match.rule).to eq(:slug)
        expect(match.why).to eq("its name is the plan's slug")
      end
    end

    # These are the team's real, hand-curated projects — the ones an import
    # has no business touching — so they must survive unclaimed.
    it "leaves the team's own projects unmatched" do
      expect(reconciled.unmatched.map { |p| p["id"] }).to eq(%w[p-hand])
    end

    it "reports the plans no project covers, which an import would create" do
      expect(reconciled.uncovered.map { |s| s.feature.slug }).to eq(%w[app-web])
    end
  end

  describe "#near and #guess" do
    let(:ledger) { OpenLanes::Plans::Tree.new(dir: plans_root).subjects.find { |s| s.feature.slug == "ledger-carryforward-vintages" } }
    let(:noise_only) { OpenLanes::Plans::Tree.new(dir: plans_root).subjects.find { |s| s.feature.slug == "app-web" } }

    it "ranks the projects sharing the plan's words, best first" do
      near = survey([project("g-2", "Vintages Board", "description" => "Wine cellar"),
                     project("g-1", "Ledger Carryforward Work")]).near(ledger)

      expect(near.map { |p| p["id"] }).to eq(%w[g-1 g-2])
    end

    it "guesses the best project when it agrees on at least two words" do
      best, score = survey([project("g-1", "Ledger Carryforward Work")]).guess(ledger)

      aggregate_failures do
        expect(best["id"]).to eq("g-1")
        expect(score).to eq(2)
      end
    end

    # Half these plans mention "tax"; one shared word is not evidence.
    it "refuses to guess on a single shared word" do
      expect(survey([project("g-2", "Vintages Board")]).guess(ledger)).to be_nil
    end

    # "app" and "web" are noise, so this plan gives the matcher nothing to
    # hold — the honest answer is silence, not a zero-scored list.
    it "has no opinion about a plan whose name is all noise words" do
      polled = survey([project("g-1", "Ledger Carryforward Work")])

      aggregate_failures do
        expect(polled.near(noise_only)).to eq([])
        expect(polled.guess(noise_only)).to be_nil
      end
    end
  end

  describe "#undescribed" do
    it "reads whichever field the team writes in, and flags only true silence" do
      surveyed = survey([project("d-1", "Short line", "description" => "It exists for reasons."),
                         project("d-2", "Long form", "content" => "A whole document."),
                         project("d-3", "Bare")])

      aggregate_failures do
        expect(surveyed.undescribed.map { |p| p["id"] }).to eq(%w[d-3])
        expect(surveyed.described?(project("d-4", "Summary only", "summary" => "One sentence."))).to be(true)
      end
    end
  end

  describe "#project" do
    let(:surveyed) do
      survey([{ "id" => "p-pay", "name" => "Payments Platform",
               "url" => "https://linear.app/t/project/payments-platform" }])
    end

    it "finds a project by the URL a human can actually copy out of Linear" do
      expect(surveyed.project("HTTPS://linear.app/t/project/payments-platform")["id"]).to eq("p-pay")
    end

    it "finds a project by name, whatever the capitalisation" do
      expect(surveyed.project("payments platform")["id"]).to eq("p-pay")
    end

    it "finds a project by its id, spaces trimmed" do
      expect(surveyed.project("  p-pay  ")["id"]).to eq("p-pay")
    end

    # Not the URL and not quite the name: the slug of what was typed still
    # ends the URL, which is how a name pasted with punctuation resolves.
    it "falls back to matching the slug of the reference against the URL" do
      expect(surveyed.project("Payments Platform!")["id"]).to eq("p-pay")
    end

    it "names what this team actually has when nothing matches" do
      expect { surveyed.project("mystery") }.to raise_error(OpenLanes::Error, /no project matches "mystery".*Payments Platform\n\s+https:/m)
    end
  end
end
