# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::BlockedFile do
  let(:text) do
    <<~MD
      # Blocked

      ## B1 Budget

      Seven units will not fit.

      ## A1

      Split them.

      ## B2 Rebase

      Should I rebase first?
    MD
  end

  describe ".bodies" do
    it "reads each question up to the next heading or answer" do
      expect(described_class.bodies(text)).to eq(1 => "\nSeven units will not fit.\n\n", 2 => "\nShould I rebase first?\n")
    end
  end

  describe ".replace" do
    it "rewrites one body and leaves the headings and the answer alone" do
      expect(described_class.replace(text, 1, "Fit?\n\na) Split (Recommended)\nb) Wait")).to eq(<<~MD)
        # Blocked

        ## B1 Budget

        Fit?

        a) Split (Recommended)
        b) Wait

        ## A1

        Split them.

        ## B2 Rebase

        Should I rebase first?
      MD
    end

    it "rewrites the last question in the file" do
      expect(described_class.replace(text, 2, "New")).to end_with("## B2 Rebase\n\nNew\n")
    end

    it "gives a heading at the very end a line of its own" do
      expect(described_class.replace("## B1 Rebase?", 1, "Body")).to eq("## B1 Rebase?\n\nBody\n")
    end

    it "is nil for a question the file does not hold" do
      expect(described_class.replace(text, 3, "x")).to be_nil
    end
  end
end
