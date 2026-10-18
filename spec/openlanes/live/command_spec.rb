# frozen_string_literal: true

RSpec.describe "A live command and its reply" do
  describe OpenLanes::Live::Command do
    def parse(**fields) = described_class.parse({ id: "01J", kind: "stop_all", plan: nil, agent: nil, payload: {} }.merge(fields))

    context "when read from JSON" do
      subject(:command) { described_class.parse('{"id":"01J","kind":"answer","plan":"4","payload":{"question":"B2","text":" yes "}}') }

      it "normalises its ordinal and strips payload fields it is asked for" do
        aggregate_failures do
          expect(command.wire).to eq(id: "01J", kind: "answer", plan: "004.00", agent: nil, payload: { "question" => "B2", "text" => " yes " })
          expect(command["text"]).to eq("yes")
          expect(command["absent"]).to eq("")
        end
      end
    end

    it "addresses a car by plan and agent" do
      expect(parse(kind: "stop", plan: "001.00", agent: "luke-backend").car).to eq("001.00/luke-backend")
    end

    it "keeps a plan that is not an ordinal as written, for the engine to refuse" do
      expect(parse(kind: "discard", plan: "next").plan).to eq("next")
    end

    {
      "a bad id"                  => [{ id: "has space" }, /id must be/],
      "an unknown kind"           => [{ kind: "dance" }, /unknown kind "dance"/],
      "a plan kind with none"     => [{ kind: "discard" }, /discard needs a plan/],
      "an agent kind with none"   => [{ kind: "stop", plan: "001.00" }, /stop needs an agent/],
      "a missing payload field"   => [{ kind: "answer", plan: "001.00", payload: { question: "B1" } }, /answer needs payload text/],
      "a payload that is not one" => [{ payload: [1] }, /not a command/]
    }.each do |what, (fields, message)|
      it "refuses #{what}" do
        expect { parse(**fields) }.to raise_error(described_class::Invalid, message)
      end
    end

    describe "the lane controls the copilot sends" do
      %w[stop_plan restart_plan].each do |kind|
        it "lets #{kind} name a plan and no agent" do
          expect(parse(kind:, plan: "20")).to have_attributes(kind:, plan: "020.00", agent: nil)
        end

        it "refuses #{kind} with no plan" do
          expect { parse(kind:) }.to raise_error(described_class::Invalid, /#{kind} needs a plan/)
        end
      end

      it "lets set_concurrency carry a limit and no plan" do
        expect(parse(kind: "set_concurrency", payload: { limit: 3 })["limit"]).to eq("3")
      end

      it "refuses set_concurrency with no limit" do
        expect { parse(kind: "set_concurrency") }.to raise_error(described_class::Invalid, /set_concurrency needs payload limit/)
      end
    end

    it "refuses JSON that is not an object" do
      expect { described_class.parse("[1]") }.to raise_error(described_class::Invalid, /JSON object/)
    end

    it "refuses what is not JSON" do
      expect { described_class.parse("{") }.to raise_error(described_class::Invalid, /not a command/)
    end
  end

  describe OpenLanes::Live::Reply do
    it "goes on the wire as the page's Reply" do
      expect(described_class.new(id: "01J", status: "refused", reason: "no", at: Time.utc(2026, 10, 13)).to_json)
        .to eq('{"id":"01J","status":"refused","reason":"no","at":"2026-10-13T00:00:00Z"}')
    end
  end
end
