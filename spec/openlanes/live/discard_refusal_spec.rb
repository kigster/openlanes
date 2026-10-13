# frozen_string_literal: true

require_relative "live_context"

RSpec.describe "Discarding a plan that cannot go back", :tree do
  include_context "with a live run"

  let(:runner) do
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :worktree,
      worktree: OpenLanes::Vcs::Worktree.new(root: File.dirname(plans_root)),
      claims:,
      sleeper: ->(_) {})
  end

  before { plans { |t| t.plan "001.00", :rejected, "fixes", files: { "spec.md" => spec_body } } }

  it "is refused before any agent is stopped" do
    expect { dispatcher.discard("001.00") }
      .to raise_error(OpenLanes::Error, "001.00 cannot go back: 🔴 Changes Requested has no state behind it to go back to")
  end

  it "is refused for a plan that is not there" do
    expect { dispatcher.discard("009.00") }.to raise_error(OpenLanes::Error, "there is no plan 009.00")
  end
end
