# frozen_string_literal: true

# The `resync prs` workflow, without the dry-cli command around it.
RSpec.describe OpenLanes::Lifecycle, ".retitle_prs", :tree do
  let(:github) { instance_double(OpenLanes::Vcs::GitHub) }

  def retitle(commit: false)
    described_class.retitle_prs(tree: OpenLanes::Plans.tree(plans_root),
      github:,
      adopt: false,
      root: File.dirname(plans_root),
      commit:)
  end

  before { plans { |t| t.plan("001.00", :new, "done-already") } }

  it "succeeds with the changes it would make" do
    allow(github).to receive(:pulls).and_return([{ number: 1, title: "[001.00] Done already", branch: "",
                                                   url: "u", files: [], state: "Open 🟡", open: true }])

    expect(retitle.value!).to eq([])
  end

  it "fails with a status-69 refusal when GitHub refuses" do
    allow(github).to receive(:pulls).and_raise(OpenLanes::Error, "could not list pull requests via `gh`: boom")

    expect(retitle.failure).to eq(OpenLanes::Refusal.new(message: "could not list pull requests via `gh`: boom",
      status: 69))
  end
end
