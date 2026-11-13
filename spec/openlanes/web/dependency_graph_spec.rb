# frozen_string_literal: true

RSpec.describe OpenLanes::Web::DependencyGraph, :tree do
  subject(:graph) { described_class.new(OpenLanes::Plans::Tree.new(dir: plans_root)).to_h }

  def spec_md(depends_on, summary: nil)
    front = ["depends_on: #{depends_on}", summary && "summary: #{summary}"].compact.join("\n")
    "---\n#{front}\n---\n\n# T\n\n## What we are trying to achieve\n\nThe goal of it.\n"
  end

  before do
    plans do |t|
      t.plan "001.00", :approved, "shipped", under: "archive", files: { "spec.md" => spec_md("[none]") }
      t.plan "002.00", :planned, "base", files: { "spec.md" => spec_md('["001.00"]', summary: "Base work.") }
      t.plan "003.00", :building, "middle", files: { "spec.md" => spec_md('["002.00"]') }
      t.plan "004.00", :new, "top", files: { "spec.md" => spec_md('["003.00", "002.00", "099.00"]') }
    end
  end

  it "has one node per plan, archive included, marked archived" do
    expect(graph[:plans].map { it.values_at(:ordinal, :state, :archived) }).to contain_exactly(
      ["001.00", "approved", true], ["002.00", "planned", false], ["003.00", "building", false], ["004.00", "new", false]
    )
  end

  it "has one edge per depends_on entry the tree holds, dependency to dependent" do
    expect(graph[:edges]).to eq([{ from: "001.00", to: "002.00" }, { from: "002.00", to: "003.00" },
                                 { from: "002.00", to: "004.00" }, { from: "003.00", to: "004.00" }])
  end

  it "lists the states in STATUSES order" do
    expect(graph[:states].map { it[:key] }).to eq(OpenLanes::Plans::STATUSES.map { it.key.to_s })
  end

  it "summarises each plan from its summary: key, or the goal paragraph" do
    expect(graph[:plans].to_h { it.values_at(:ordinal, :summary) }).to include("002.00" => "Base work.",
      "003.00" => "The goal of it.")
  end
end
