# frozen_string_literal: true

# V2 and V4 in docs/decisions/decisions-on-agent-names-models-and-reviewers.md:
# each reviewer reports one verdict, and the dispatcher's label follows from
# them, one rejection rejecting and the majority deciding the rest.
RSpec.describe OpenLanes::Plans::Verdict do
  def vote(word, agent: "staff-reviewer", vulnerability: false) = described_class::Vote.new(agent:, word:, vulnerability:)

  let(:security) { "security-reviewer" }

  describe ".call" do
    subject(:verdict) { described_class.call(votes) }

    context "with one reviewer that called it great" do
      let(:votes) { [vote(:great)] }

      it { expect(verdict.names).to eq(%w[review-approved]) }
      it { is_expected.to be_passing }
    end

    context "with one reviewer that passed it" do
      let(:votes) { [vote(:passed)] }

      it { expect(verdict.names).to eq(%w[review-passed]) }
      it { is_expected.to be_passing }
    end

    context "with two great of three" do
      let(:votes) { [vote(:great), vote(:passed, agent: security), vote(:great, agent: "design-reviewer")] }

      it { expect(verdict.names).to eq(%w[review-approved]) }
    end

    context "with one great of three" do
      let(:votes) { [vote(:great), vote(:passed, agent: security), vote(:passed, agent: "design-reviewer")] }

      it { expect(verdict.names).to eq(%w[review-passed]) }
    end

    context "with one rejection among two great" do
      let(:votes) { [vote(:great), vote(:great, agent: security), vote(:rejected, agent: "design-reviewer")] }

      it { expect(verdict.names).to eq(%w[review-rejected]) }
      it { is_expected.not_to be_passing }
    end

    context "when security-reviewer reports a vulnerability" do
      let(:votes) { [vote(:great), vote(:rejected, agent: security, vulnerability: true)] }

      it { expect(verdict.names).to eq(%w[review-rejected review-vulnerability]) }
      it { expect(verdict.ignored).to be_empty }
    end

    context "when another reviewer reports a vulnerability" do
      let(:votes) { [vote(:rejected, vulnerability: true)] }

      it { expect(verdict.names).to eq(%w[review-rejected]) }
      it { expect(verdict.ignored).to eq(votes) }
    end

    context "with no votes" do
      let(:votes) { [] }

      it { expect { verdict }.to raise_error(ArgumentError, /no reviewer/) }
    end
  end

  describe ".vote" do
    subject(:parsed) { described_class.vote(agent:, note:) }

    let(:agent) { "staff-reviewer" }

    {
      "great"                    => :great,
      "Great, nothing to reject" => :great,
      "approved"                 => :great,
      "passed"                   => :passed,
      "rejected 1/2"             => :rejected,
      "slop"                     => :rejected
    }.each do |note, word|
      context "with the note #{note.inspect}" do
        let(:note) { note }

        it { expect(parsed.word).to eq(word) }
        it { expect(parsed.agent).to eq(agent) }
        it { is_expected.not_to be_vulnerability }
      end
    end

    context "with a rejection naming a vulnerability" do
      let(:agent) { "security-reviewer" }
      let(:note) { "rejected 1/2 vulnerability" }

      it { is_expected.to be_rejected }
      it { is_expected.to be_vulnerability }
    end

    context "with a great note that mentions a vulnerability" do
      let(:note) { "great, the vulnerability is fixed" }

      it { is_expected.to be_great }
      it { is_expected.not_to be_vulnerability }
    end

    ["nothing to reject", "", nil, "verified"].each do |note|
      context "with the note #{note.inspect}" do
        let(:note) { note }

        it { is_expected.to be_nil }
      end
    end
  end

  describe "OpenLanes::Plans.verdict" do
    it "logs a vulnerability from a reviewer outside security" do
      allow(OpenLanes::UI).to receive(:log)
      OpenLanes::Plans.verdict([vote(:rejected, vulnerability: true)])

      expect(OpenLanes::UI).to have_received(:log).with(/ignored vulnerability from staff-reviewer/, level: :warn)
    end
  end
end
