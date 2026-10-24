# frozen_string_literal: true

RSpec.describe OpenLanes::Config do
  def parse(text) = described_class.parse(text, path: "/p/.openlanes.yml")

  it "lets a person merge unless told otherwise (M4)" do
    aggregate_failures do
      expect(described_class.new.merger).to eq(:human)
      expect(described_class.new).to be_human_merges
    end
  end

  it "reads merge.by" do
    expect(parse("merge:\n  by: auto\n")).to have_attributes(merge_by: :auto, merger: :auto, human_merges?: false)
  end

  it "writes it back" do
    expect(described_class.new(jobs: 2, merge_by: :human).to_yaml).to eq("jobs: 2\nmerge:\n  by: human\n")
  end

  it "refuses a merger it does not know, naming the file" do
    expect { parse("merge:\n  by: robot\n") }
      .to raise_error(OpenLanes::Error, %r{/p/\.openlanes\.yml: merge\.by: "robot" is not one of human, auto})
  end

  it "refuses merge: that is not a mapping" do
    expect { parse("merge: human\n") }.to raise_error(OpenLanes::Error, /merge: must be a mapping/)
  end

  it "refuses an unknown key under merge:" do
    expect { parse("merge:\n  when: never\n") }.to raise_error(OpenLanes::Error, /merge: unknown key when; known: by, max_rejections/)
  end

  describe "max_rejections (M6)" do
    it "defaults to two" do
      expect(described_class.new.max_rejections).to eq(2)
    end

    it "reads merge.max_rejections, beside merge.by or alone" do
      aggregate_failures do
        expect(parse("merge:\n  max_rejections: 3\n")).to have_attributes(max_rejections: 3, merger: :human)
        expect(parse("merge:\n  by: auto\n  max_rejections: 1\n")).to have_attributes(max_rejections: 1, merger: :auto)
      end
    end

    it "writes it back" do
      expect(described_class.new(merge_by: :auto, merge_max_rejections: 3).to_yaml).to eq("merge:\n  by: auto\n  max_rejections: 3\n")
    end

    it "refuses anything but a whole number above zero" do
      expect { parse("merge:\n  max_rejections: 0\n") }
        .to raise_error(OpenLanes::Error, /merge\.max_rejections: 0 is not a whole number above zero/)
    end

    ["-1", '"two"'].each do |value|
      it "refuses #{value}" do
        expect { parse("merge:\n  max_rejections: #{value}\n") }
          .to raise_error(OpenLanes::Error, /merge\.max_rejections: .* is not a whole number above zero/)
      end
    end
  end
end
