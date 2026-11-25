# frozen_string_literal: true

# The facade spells out each writer's keywords. Forwarding `**` to a value
# type instead let a string key through, and the value dropped it: a
# signature was written without its note rather than refused.
RSpec.describe OpenLanes::Plans::PlanState, :tree do
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:state) { described_class.for(folder) }

  {
    sign!:       { agent: "a", round: 1, status: "Completed" },
    message!:    { from: "a", to: "b", body: "hi" },
    conversion!: { question: 1, digest: "d", original: "?", model: "m", outcome: "converted" },
    rule!:       { kind: :cap, pr: nil, round: nil, outcome: "struck", findings: {}, winner: nil, reason: "r", trigger: "t" }
  }.each do |writer, keywords|
    it "#{writer} refuses a string key where a keyword belongs, and writes nothing" do
      expect { state.public_send(writer, **keywords, "note" => "x") }
        .to raise_error(ArgumentError, /unknown keyword: "note"/)
      expect(state.exist?).to be(false)
    end
  end
end
