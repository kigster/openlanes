# frozen_string_literal: true

# `openlanes start` as a workflow. Its page is the only way in, so a missing
# live board is a refusal, not a reason to go on headless.
RSpec.describe OpenLanes::Engine::StartWorkflow, :tree do
  before { plans { |t| t.plan("001.00", :building, "tax-rule-dsl", files: { "spec.md" => spec_body }) } }

  def start
    err = CapturedStream.new
    original, $stderr = $stderr, err
    described_class.new(tree: OpenLanes::Plans.tree(plans_root),
      rescan: 5,
      isolation: "shared",
      log: File.join(plans_root, "..", "progress.log")).call
  ensure
    $stderr = original
  end

  it "refuses with 69 when Redis is not there" do
    allow(OpenLanes::Live).to receive(:connect)
      .and_raise(OpenLanes::Live::Unavailable, "Redis at redis://h/0 is unavailable")
    failure = start.failure

    expect([failure.status, failure.message]).to match([69, a_string_including("openlanes start needs Redis")])
  end
end
