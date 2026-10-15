# frozen_string_literal: true

RSpec.describe OpenLanes::Presentation::ApiDocs, :tree do
  subject(:result) { OpenLanes::Presentation.api_docs.call(OpenLanes::Plans.tree(plans_root)) }

  let(:valid) do
    <<~YAML
      openapi: 3.1.0
      info:
        title: Returns
        version: "1"
      paths:
        /returns/{id}:
          get: {}
    YAML
  end

  def plan_with(ordinal, slug, openapi)
    plans { |t| t.plan ordinal, :building, slug, files: { "spec.md" => spec_body, "plan.md" => "# P", "openapi.yaml" => openapi } }
  end

  context "with two good documents and one missing paths:" do
    before do
      plan_with("001.00", "returns", valid)
      plan_with("002.00", "refunds", valid.sub("Returns", "Refunds"))
      plan_with("003.00", "half-written", "openapi: 3.1.0\ninfo:\n  title: Half\n")
      plans { |t| t.plan "004.00", :building, "no-contract", files: { "spec.md" => spec_body, "plan.md" => "# P" } }
    end

    it "finds both good ones, in plan order, with their titles" do
      expect(result.found.map { [File.basename(File.dirname(it.path)), it.title, it.version] })
        .to match([[include("returns"), "Returns", "3.1.0"], [include("refunds"), "Refunds", "3.1.0"]])
    end

    it "reports the one without paths: as the only problem" do
      expect([result.problems.size, result.problems.first.path, result.problems.first.reason])
        .to match([1, include("half-written"), "has no top-level paths:"])
    end

    it "is not ok" do
      expect(result.ok?).to be(false)
    end
  end

  it "reports a file that does not parse, with the parser's reason" do
    plan_with("001.00", "broken", "openapi: 3.1.0\npaths:\n  - [unclosed\n")

    expect([result.found, result.problems.map(&:reason)]).to match([[], [start_with("does not parse as YAML:")]])
  end

  it "reports a document that is not a mapping" do
    plan_with("001.00", "list", "- openapi\n- paths\n")

    expect(result.problems.map(&:reason)).to eq(["is not a YAML mapping"])
  end

  it "names both keys when both are missing" do
    plan_with("001.00", "empty", "info: {}\n")

    expect(result.problems.map(&:reason)).to eq(["has no top-level openapi: or paths:"])
  end

  it "is ok, and empty, when no plan carries a contract" do
    plans { |t| t.plan "001.00", :building, "plain", files: { "spec.md" => spec_body, "plan.md" => "# P" } }

    expect([result.found, result.problems, result.ok?]).to eq([[], [], true])
  end
end
