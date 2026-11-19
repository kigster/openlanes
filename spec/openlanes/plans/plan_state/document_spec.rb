# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::Document, :tree do
  subject(:document) { described_class.new(dir: folder) }

  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end

  it "reads a skeleton, naming the plan, before anything is written" do
    expect(document.read.slice("version", "plan", "stages")).to eq("version" => 1,
      "plan" => { "ordinal" => "001.00", "slug" => "work" },
      "stages" => [])
  end

  it "refuses a file that is not JSON, naming it" do
    File.write(document.path, "{ nope")
    expect { document.read }.to raise_error(OpenLanes::Error, /state\.json is not valid JSON/)
  end

  it "loses nothing when two threads update at once" do
    Array.new(2) { |i| Thread.new { 20.times { |n| document.update { it["stages"] << { "n" => "#{i}-#{n}" } } } } }.each(&:join)
    expect(document.read["stages"].size).to eq(40)
  end

  it "writes pretty JSON with a trailing newline, and leaves no temp file behind" do
    document.update { it["state"] = "building" }
    expect([File.read(document.path).end_with?("}\n"), Dir.glob("#{document.path}.*.tmp")]).to eq([true, []])
  end

  it "keeps one lock across a rename of the folder, since the key is the plan's number" do
    moved = folder.sub("work", "work-renamed")
    key = document.send(:lock_key)
    expect(described_class.new(dir: moved).send(:lock_key)).to eq(key)
  end

  it "reads the epoch for a time it cannot parse" do
    expect(described_class.parse_time("not a time")).to eq(Time.at(0))
  end
end
