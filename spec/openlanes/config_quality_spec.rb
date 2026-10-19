# frozen_string_literal: true

# `desired_codebase_quality:` (R4), which replaced M5's `build_quality`.
RSpec.describe OpenLanes::Config do
  def parse(text) = described_class.parse(text, path: "/p/.openlanes.yml")

  it "reads high and mvp, in any case" do
    aggregate_failures do
      expect(parse("desired_codebase_quality: high\n")).to have_attributes(desired_codebase_quality: :high, quality_unset?: false)
      expect(parse("desired_codebase_quality: MVP\n")).to have_attributes(desired_codebase_quality: :mvp, quality_unset?: false)
    end
  end

  it "reads as still to be asked, when the file says nothing" do
    expect(parse("jobs: 2\n")).to have_attributes(quality_unset?: true, desired_codebase_quality: nil)
  end

  it "refuses M5's dropped levels and anything else, naming the file" do
    aggregate_failures do
      %w[top_notch medium 3].each do |level|
        expect { parse("desired_codebase_quality: #{level}\n") }
          .to raise_error(OpenLanes::Error, %r{/p/\.openlanes\.yml: desired_codebase_quality: .* is not one of high, mvp})
      end
    end
  end

  it "refuses build_quality, the key it replaced" do
    expect { parse("build_quality: high\n") }.to raise_error(OpenLanes::Error, /unknown key build_quality/)
  end

  it "defaults max_rejections from M5's column, below merge.max_rejections" do
    aggregate_failures do
      expect(parse("desired_codebase_quality: high\n").max_rejections).to eq(2)
      expect(parse("desired_codebase_quality: mvp\n").max_rejections).to eq(1)
      expect(parse("desired_codebase_quality: mvp\nmerge:\n  max_rejections: 3\n").max_rejections).to eq(3)
      expect(described_class.new.max_rejections).to eq(2)
    end
  end

  it "writes it back, before merge:" do
    expect(described_class.new(desired_codebase_quality: :mvp, merge_by: :auto).to_yaml)
      .to eq("desired_codebase_quality: mvp\nmerge:\n  by: auto\n")
  end
end
