# frozen_string_literal: true

# A seam, not a client library. What is worth testing is the failure
# reporting: Linear declines a mutation in three different ways, and two of
# them are not errors.
RSpec.describe OpenLanes::Linear::API do
  subject(:api) { described_class.new(transport:) }

  let(:transport) { ->(_document, _variables) { response } }
  let(:response) { { "data" => {} } }

  describe "authentication" do
    it "refuses to be built with no way to authenticate" do
      allow(ENV).to receive(:[]).with("LINEAR_API_KEY").and_return(nil)

      expect { described_class.new }.to raise_error(OpenLanes::Error, /Set LINEAR_API_KEY.*--format json/m)
    end

    it "is content with a token" do
      expect { described_class.new(token: "lin_api_x") }.not_to raise_error
    end
  end

  describe "#team" do
    let(:response) do
      { "data" => { "teams" => { "nodes" => [{ "id" => "t-1", "name" => "Tax", "key" => "TAX",
                                           "states" => { "nodes" => [{ "id" => "s-1" }] },
                                           "labels" => { "nodes" => [] } }] } } }
    end

    it "returns the team with its states and labels in one round trip" do
      expect(api.team("tax")).to include(id: "t-1", key: "TAX", states: [{ "id" => "s-1" }])
    end

    context "when no team wears that key" do
      let(:response) { { "data" => { "teams" => { "nodes" => [] } } } }

      it "says which key it looked for" do
        expect { api.team("nope") }.to raise_error(OpenLanes::Error, /no Linear team has the key NOPE/)
      end
    end
  end

  describe "reporting a refusal" do
    context "when Linear returns errors" do
      let(:response) { { "errors" => [{ "message" => "Entity not found" }, { "message" => "and again" }] } }

      it "repeats what Linear actually said" do
        expect { api.query("query { x }") }.to raise_error(OpenLanes::Error, /Entity not found; and again/)
      end
    end

    # A failed mutation comes back as `success: false` with no errors array,
    # which reads as a success to anything only checking for errors.
    context "when a mutation reports itself unsuccessful" do
      let(:response) { { "data" => { "issueCreate" => { "success" => false, "issue" => nil } } } }

      it "does not mistake it for having worked" do
        expect { api.create_issue(title: "x") }.to raise_error(OpenLanes::Error, /declined the issueCreate/)
      end
    end

    context "when the response has neither data nor errors" do
      let(:response) { {} }

      it "says so rather than returning nil into the caller" do
        expect { api.query("query { x }") }.to raise_error(OpenLanes::Error, /returned no data/)
      end
    end

    # A mutation can also come back with the errors array empty but the
    # payload itself missing, which is a third way of not having worked.
    context "when the mutation payload is absent entirely" do
      let(:response) { { "data" => {} } }

      it "reports the missing payload instead of digging into nil" do
        expect { api.create_project(name: "x") }.to raise_error(OpenLanes::Error, /returned no projectCreate payload/)
      end
    end
  end

  # The default transport. Nothing here touches the network: Net::HTTP.start
  # is intercepted and handed a canned response, so what is under test is the
  # request this class builds and how it reads what comes back.
  describe "the HTTP transport" do
    subject(:api) { described_class.new(token: "lin_api_x") }

    let(:requests) { [] }
    let(:http_response) { success('{"data":{"ok":true}}') }

    before do
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) { |request|
        requests << request
        http_response
      }
      allow(Net::HTTP).to receive(:start) { |*_args, **_opts, &block| block.call(http) }
    end

    # @param body [String]
    # @return [Net::HTTPSuccess]
    def success(body)
      Net::HTTPOK.new("1.1", "200", "OK").tap { |r| r.define_singleton_method(:body) { body } }
    end

    # @param code [String]
    # @return [Net::HTTPResponse]
    def failure(code)
      Net::HTTPResponse::CODE_TO_OBJ.fetch(code).new("1.1", code, "Nope")
                                    .tap { |r| r.define_singleton_method(:body) { "" } }
    end

    it "parses a successful response into its data" do
      expect(api.query("query { x }")).to eq("ok" => true)
    end

    # Linear's personal keys are sent verbatim; adding the customary
    # `Bearer` prefix is precisely the mistake that returns a 400.
    it "sends the token verbatim, without a Bearer prefix" do
      api.query("query { x }", a: 1)
      request = requests.first

      aggregate_failures do
        expect(request["Authorization"]).to eq("lin_api_x")
        expect(request["Content-Type"]).to eq("application/json")
        expect(JSON.parse(request.body)).to eq("query" => "query { x }", "variables" => { "a" => 1 })
      end
    end

    context "when Linear answers 401" do
      let(:http_response) { failure("401") }

      # A 400/401 here is nearly always the Bearer-prefix mistake, so the
      # error says so instead of leaving the reader to discover it.
      it "points at the token and the Bearer trap" do
        expect { api.query("query { x }") }.to raise_error(OpenLanes::Error, /HTTP 401.*Check LINEAR_API_KEY.*without a `Bearer` prefix/m)
      end
    end

    context "when Linear answers with a server error" do
      let(:http_response) { failure("503") }

      it "reports the status without the token hint, which would mislead" do
        expect { api.query("query { x }") }.to raise_error(OpenLanes::Error) { |e| expect(e.message).to eq("Linear returned HTTP 503") }
      end
    end

    context "when the body is not JSON" do
      let(:http_response) { success("<html>gateway timeout</html>") }

      it "folds the parse failure into the could-not-reach report" do
        expect { api.query("query { x }") }.to raise_error(OpenLanes::Error, /could not reach Linear at http/)
      end
    end

    context "when the connection never opens" do
      before { allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED) }

      it "names the endpoint it could not reach" do
        expect { api.query("query { x }") }.to raise_error(OpenLanes::Error, /could not reach Linear at #{described_class::ENDPOINT}/o)
      end
    end
  end
end
