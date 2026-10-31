# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::Extraction::Ollama do
  subject(:ollama) { described_class.new(host:, get:) }

  let(:host) { nil }
  let(:asked) { [] }
  let(:body) { JSON.generate(models: [{ name: "llama4" }, { other: 1 }]) }
  let(:get) { ->(uri) { body.tap { asked << uri.to_s } } }

  its(:models) { is_expected.to eq(%w[llama4]) }
  its(:chat_url) { is_expected.to eq("http://127.0.0.1:11434/v1/chat/completions") }

  it "asks the default host" do
    ollama.models
    expect(asked).to eq(["http://127.0.0.1:11434/api/tags"])
  end

  context "with OLLAMA_HOST as a bind address, with no scheme" do
    let(:host) { "0.0.0.0:11500/" }

    its(:chat_url) { is_expected.to eq("http://127.0.0.1:11500/v1/chat/completions") }
  end

  context "with OLLAMA_HOST as a full address" do
    let(:host) { "https://ollama.example.test" }

    its(:chat_url) { is_expected.to eq("https://ollama.example.test/v1/chat/completions") }
  end

  context "when nothing answers" do
    let(:get) { ->(_uri) { raise Errno::ECONNREFUSED } }

    its(:models) { is_expected.to eq([]) }
  end

  context "when something else answers" do
    let(:body) { "<html>" }

    its(:models) { is_expected.to eq([]) }
  end

  context "with a real socket" do
    subject(:ollama) { described_class.new(host:) }

    let(:server) { TCPServer.new("127.0.0.1", 0) }
    let(:host) { "127.0.0.1:#{server.addr[1]}" }

    it "reads the models" do
      thread = Thread.new do
        client = server.accept
        client.readline
        reply = JSON.generate(models: [{ name: "qwen3" }])
        client.write("HTTP/1.1 200 OK\r\nContent-Length: #{reply.bytesize}\r\nConnection: close\r\n\r\n#{reply}")
        client.close
      end
      expect(ollama.models).to eq(%w[qwen3])
      thread.join
    end
  end
end
