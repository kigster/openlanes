# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::Journal do
  def line(value) = JSON.generate("openlanes_memory" => value)

  describe ".scan" do
    subject(:scanned) { described_class.scan(text) }

    let(:text) do
      <<~TEXT
        Reading the spec first.
        #{line("kind" => "decision", "text" => "Money is integer cents")}
        {"status": "ok"}
          `#{line("kind" => "override", "text" => "BigDecimal after all", "overrides" => 1)}`
      TEXT
    end

    it "reads every entry line, in order, and nothing else" do
      expect(scanned).to eq([described_class::Entry.new(kind: "decision", text: "Money is integer cents"),
                             described_class::Entry.new(kind: "override", text: "BigDecimal after all", overrides: 1)])
    end

    it "finds nothing in text that never names the key" do
      expect(described_class.scan("{\"kind\": \"done\", \"text\": \"x\"}\nplain")).to eq([])
    end
  end

  describe ".read" do
    {
      "an unknown kind"                       => [{ "kind" => "wish", "text" => "x" }, /kind "wish" is not one of/],
      "no text"                               => [{ "kind" => "note", "text" => "  " }, /text is missing/],
      "a value that is not an object"         => ["note", /is not an object/],
      "an override number of zero"            => [{ "kind" => "override", "text" => "x", "overrides" => 0 }, /entry number/],
      "a number on something not an override" => [{ "kind" => "decision", "text" => "x", "overrides" => 2 },
                                                  /only an override/]
    }.each do |what, (value, reason)|
      it "refuses #{what}, saying why" do
        expect(described_class.read(line(value))).to have_attributes(class: described_class::Rejection, reason:)
      end
    end

    it "refuses a line that is not JSON" do
      expect(described_class.read('{"openlanes_memory": {"kind": "note",')).to have_attributes(reason: /not JSON/)
    end

    # The answer is the harness's to write, from blocked.md.
    it "ignores an answer the agent claims for itself" do
      entry = described_class.read(line("kind" => "question", "text" => "Which DB?", "answer" => "Postgres", "ref" => "B1"))
      expect(entry).to eq(described_class::Entry.new(kind: "question", text: "Which DB?"))
    end

    it "cuts text that runs past the limit" do
      entry = described_class.read(line("kind" => "note", "text" => "x" * 900))
      expect(entry.text.length).to eq(described_class::TEXT_LIMIT)
    end
  end

  describe ".line" do
    it "prints what .read reads back" do
      printed = described_class.line("override", "Undo it", overrides: 4)
      expect(described_class.read(printed)).to eq(described_class::Entry.new(kind: "override", text: "Undo it", overrides: 4))
    end
  end

  describe described_class::Entry do
    it "leaves what it does not carry out of its JSON" do
      expect(described_class.new(kind: "done", text: "U1").to_json_h).to eq("kind" => "done", "text" => "U1")
    end
  end
end
