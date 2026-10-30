# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::Extraction::OllamaAdapter do
  subject(:adapter) { described_class.new(url: "http://127.0.0.1:#{server.addr[1]}/v1/chat/completions", model: "llama4") }

  let(:server) { TCPServer.new("127.0.0.1", 0) }
  let(:node) { Inquirex::LLM::Node.new(id: :stack, verb: :extract, prompt: "read", schema: Inquirex::LLM::Schema.new(ci: :string), from_steps: [:description]) }
  let(:status) { "200 OK" }
  let(:reply) { JSON.generate(choices: [{ message: { content: '{"ci":"circleci"}' } }]) }
  let!(:listener) do
    Thread.new do
      client = server.accept
      length = 0
      while (line = client.readline) != "\r\n"
        length = line.split(":").last.to_i if line.downcase.start_with?("content-length")
      end
      client.read(length)
      client.write("HTTP/1.1 #{status}\r\nContent-Length: #{reply.bytesize}\r\nConnection: close\r\n\r\n#{reply}")
      client.close
    end
  end

  after { listener.join(1) }

  it "reads the answer over plain HTTP" do
    expect(adapter.call(node, { description: "a shop" })[:ci]).to eq("circleci")
  end

  context "when the server refuses" do
    let(:status) { "500 Oops" }

    it "fails without quoting the reply" do
      expect { adapter.call(node, { description: "a shop" }) }.to raise_error(Inquirex::LLM::Errors::AdapterError, "Ollama error 500")
    end
  end
end
