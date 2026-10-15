# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::Choices do
  def parse(text) = described_class.parse(text)
  def labels(text) = parse(text).options.map(&:label)

  describe ".parse" do
    # Verbatim from a real blocked.md: every option run into one paragraph,
    # the recommendation a bare word, and the free-text choice written out.
    context "with the options inline in one paragraph, as agents write them" do
      subject(:choices) { parse(File.read(File.expand_path("../../fixtures/choices/inline-recommended.md", __dir__))) }

      it "keeps everything before a) as the context" do
        expect(choices.context).to start_with("web/cypress/e2e/chat.cy.ts (I1) needs someone")
          .and end_with("Cypress itself has not been run.")
      end

      it "reads a, b and c, and drops the free-text choice the page's box already is" do
        expect(choices.options.map(&:letter)).to eq(%w[a b c])
      end

      it "marks a recommended and strips the marker from its label" do
        aggregate_failures do
          expect(choices.recommended.letter).to eq("a")
          expect(choices.options.first.label).to start_with("A second openlanes web --demo process")
          expect(choices.options.first.label).to end_with("(luke-backend owns both).")
          expect(choices.options.last.answer).to eq("c) Narrow I1 to steps 1 and 5, and cover steps 2 to 4 in the Ruby suite with two hubs.")
        end
      end
    end

    it "reads one option per line" do
      choices = parse("Rebase or merge?\n\na) Rebase onto main (Recommended)\nb) Merge main in\n")
      expect(choices.to_a).to eq([{ letter: "a", label: "Rebase onto main", recommended: true, answer: "a) Rebase onto main" },
                                  { letter: "b", label: "Merge main in", recommended: false, answer: "b) Merge main in" }])
    end

    it "reads options separated by blank lines" do
      expect(labels("Which?\n\na) One\n\nb) Two\n")).to eq(%w[One Two])
    end

    it "reads (a), a. and capitals at the start of a line" do
      aggregate_failures do
        expect(labels("Which?\n(a) One\n(b) Two")).to eq(%w[One Two])
        expect(labels("Which?\na. One\nb. Two")).to eq(%w[One Two])
        expect(labels("Which?\nA) One\nB) Two")).to eq(%w[One Two])
      end
    end

    it "reads bullet-prefixed and bold-wrapped markers" do
      aggregate_failures do
        expect(parse("Which?\n- a) One\n- b) Two").deconstruct).to eq(["Which?", parse("Which?\na) One\nb) Two").options])
        expect(labels("Which?\n- **a)** One\n- **b)** Two")).to eq(%w[One Two])
        expect(labels("Which?\n**a) One**\n**b) Two**")).to eq(%w[One Two])
      end
    end

    it "reads a recommendation however it is written" do
      aggregate_failures do
        expect(parse("Which?\na) One [recommended]\nb) Two").recommended.label).to eq("One")
        expect(parse("Which?\na) One\nb) **Recommended:** Two").recommended.label).to eq("Two")
        expect(parse("Which?\na) One — recommended\nb) Two").recommended.label).to eq("One")
      end
    end

    it "leaves 'recommended' in the middle of a label as prose" do
      choices = parse("Which?\na) Use the recommended layout\nb) Two")
      expect([choices.recommended, choices.options.first.label]).to eq([nil, "Use the recommended layout"])
    end

    it "invents no recommendation, and keeps only the first of two" do
      aggregate_failures do
        expect(parse("Which?\na) One\nb) Two").recommended).to be_nil
        expect(parse("Which?\na) One (Recommended)\nb) Two (Recommended)").options.map(&:recommended)).to eq([true, false])
      end
    end

    it "reads numbered options as letters" do
      aggregate_failures do
        expect(parse("Which should I do?\n1. Rebase\n2. Merge").options.map(&:answer)).to eq(["a) Rebase", "b) Merge"])
        expect(labels("Pick one:\n1) Rebase\n2) Merge")).to eq(%w[Rebase Merge])
        expect(labels("Which?\nOption 1: Rebase\nOption 2: Merge")).to eq(%w[Rebase Merge])
      end
    end

    it "reads the W30 yes/no mark as a) yes, b) no, answered with the bare word" do
      choices = parse("answers: yes, no\n\nShould I rebase onto main?")
      expect([choices.context, choices.options.map(&:answer), choices.yes_no?]).to eq(["Should I rebase onto main?", %w[yes no], true])
    end

    it "takes the last run of letters, when the context mentions one of its own" do
      choices = parse("Either a) or b) was tried last week. Now?\n\na) Retry\nb) Give up")
      expect([choices.context, choices.options.map(&:label)]).to eq(["Either a) or b) was tried last week. Now?", %w[Retry Give\ up]])
    end

    context "when the text is not a choice" do
      it "is nil for plain prose, a single option, or nothing" do
        aggregate_failures do
          expect(parse("Should keys carry the path?")).to be_nil
          expect(parse("Which?\na) Only this")).to be_nil
          expect(parse("Which?\na) One\nb) Type something instead")).to be_nil
          expect(parse(nil)).to be_nil
        end
      end

      it "is nil for letters out of order" do
        expect(parse("Which?\nb) Two\nc) Three")).to be_nil
      end

      # Done so far is the false positive the judge exists for; the parser's
      # share is to refuse a list that more prose follows.
      it "is nil for a list that prose follows" do
        expect(parse("Which?\na) One\nb) Two\n\nI will wait for your answer.")).to be_nil
      end

      it "is nil for a numbered list of steps under nothing that asks" do
        expect(parse("Done so far:\n1. Built the parser\n2. Wrote its spec")).to be_nil
      end

      it "reads no inline numbers or words like e.g. as markers" do
        expect(parse("Done, e.g. the parser. 1) is fine, 2) too.")).to be_nil
      end
    end
  end

  describe ".yes_no" do
    it "is yes and no about the context, neither recommended" do
      choices = described_class.yes_no(" Rebase? ")
      expect([choices.context, choices.options.map(&:label), choices.recommended]).to eq(["Rebase?", %w[yes no], nil])
    end
  end
end
