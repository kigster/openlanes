# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::Extractor do
  subject(:extractor) { described_class.new(label: "a test", adapter: -> { adapter }) }

  let(:node) { :the_form_step }
  let(:adapter) { instance_double(Inquirex::LLM::Adapter, call: result) }
  let(:result) { {} }

  describe ".on" do
    it "is nil when nothing can read a description" do
      expect(described_class.on(nil)).to be_nil
    end

    it "takes a route's label" do
      route = OpenLanes::Setup::Extraction::Route.new(label: "somewhere", adapter: -> { adapter })
      expect(described_class.on(route).label).to eq("somewhere")
    end
  end

  describe "#call" do
    subject(:answers) { extractor.call(node, "a shop") }

    context "with answers in and out of the closed lists" do
      let(:result) do
        { target_ci: %w[circleci travis], target_layout: "Monorepo", target_projects: ["web", " "], target_languages: [],
          merge_by: "AUTO", desired_codebase_quality: "perfect", target_secrets: nil, ignored: "x" }
      end

      it "keeps only what the lists hold" do
        expect(answers).to eq(target_ci: %w[circleci], target_layout: "monorepo", target_projects: "web", merge_by: "auto")
      end
    end

    it "hands the adapter the description" do
      answers
      expect(adapter).to have_received(:call).with(node, { description: "a shop" })
    end

    it "calls nothing for a blank description" do
      expect(extractor.call(node, "  ")).to eq({})
      expect(adapter).not_to have_received(:call)
    end

    context "when the adapter fails" do
      before { allow(adapter).to receive(:call).and_raise(StandardError, "key sk-not-real") }

      it { is_expected.to eq({}) }

      it "never logs the message, which can quote a key" do
        allow(OpenLanes::UI).to receive(:log)
        answers
        expect(OpenLanes::UI).to have_received(:log).with("extraction: no answers (StandardError)")
      end
    end
  end
end
