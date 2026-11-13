# frozen_string_literal: true

RSpec.describe OpenLanes::Memory::Secrets do
  # Built at run time so no line of this file is itself a secret-shaped string.
  let(:key) { "sk-ant-#{"a1B2" * 8}" }

  {
    "a private key"                           => "-----BEGIN RSA PRIVATE KEY-----",
    "a GitHub token"                          => "ghp_#{"a1" * 18}",
    "an AWS access key"                       => "AKIA#{"A1" * 8}",
    "a URL carrying credentials"              => "redis://deploy:#{"pw" * 3}@cache.internal:6379/0",
    "a key, token or password set to a value" => "DB_PASSWORD=#{"hunter" * 2}",
    "an email address"                        => "ask dana.reyes@example.test about it",
    "a long random-looking string"            => "aB3#{"xY9k" * 12}"
  }.each do |kind, text|
    it "finds #{kind}" do
      expect(described_class.scan("first line\n#{text}\n").map { [it.kind, it.line] }).to include([kind, 2])
    end
  end

  it "names the kind and the line, and never the text that matched" do
    found = described_class.scan("use #{key} here")
    expect([found.map(&:to_s), found.join.include?(key)]).to eq([["line 1: an Anthropic or OpenAI key"], false])
  end

  it "lets ordinary lesson text through: commit ids, clone URLs, and talk about secrets" do
    text = <<~TEXT
      Fixed in 4fcb6eb2c0a94d3e8f1b2a7c5d6e9f0a1b2c3d4e. Clone with git@github.com:acme/app.git.
      Read the token from the environment; never write a password into a spec.
      The API key lives in Rails credentials, see https://example.test/docs/setup.
    TEXT
    expect(described_class.clean?(text)).to be(true)
  end

  describe ".scan_tree" do
    let(:dir) { Dir.mktmpdir("openlanes-folder") }

    after { FileUtils.rm_rf(dir) }

    it "reports each file that holds something, and nothing for a clean or missing folder" do
      FileUtils.mkdir_p(File.join(dir, "memory", "lessons"))
      File.write(File.join(dir, "memory", "lessons", "L-0001.md"), "token: #{key}\n")
      File.write(File.join(dir, "config.yml"), "jobs: 4\n")
      expect([described_class.scan_tree(dir).keys.map { File.basename(it) }, described_class.scan_tree(File.join(dir, "absent"))])
        .to eq([["L-0001.md"], {}])
    end
  end

  # The requirement itself, held against this repository on every run.
  it "finds nothing under this repository's own .openlanes folder, and nothing there is ignored" do
    root = File.expand_path("../../..", __dir__)
    expect([OpenLanes::Memory.secrets(root:), OpenLanes::Memory.ignored(root:)]).to eq([{}, []])
  end
end
