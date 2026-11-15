# frozen_string_literal: true

RSpec.describe OpenLanes::Config::Secrets do
  # Shaped like a GitHub token, and made up.
  let(:token) { "ghp_#{"a1B2c3D4" * 4}" }

  def parse(yaml) = OpenLanes::Config.parse(yaml, path: ".openlanes/config.yml")

  it "refuses a redis_url with a password, pointing at REDIS_URL" do
    ["redis://:pw@host:6379/0", "redis://user:pw@host:6379/0", "rediss://u:p@h"].each do |url|
      expect { parse("redis_url: #{url}\n") }
        .to raise_error(OpenLanes::Error, %r{\.openlanes/config\.yml: redis_url carries a password.*REDIS_URL})
    end
  end

  it "accepts a redis_url without a password" do
    expect(parse("redis_url: redis://user@10.0.4.2:6379/0\n").redis_url).to eq("redis://user@10.0.4.2:6379/0")
    expect(parse("redis_url: redis://10.0.4.2:6379/0\n").redis_url).to eq("redis://10.0.4.2:6379/0")
  end

  # Issue 251: the check read the top-level key only, so the settings page
  # committed and pushed a password written under a command.
  it "refuses a redis_url with a password under any command, naming the key path" do
    %w[run web].each do |command|
      expect { parse("commands:\n  #{command}:\n    redis_url: redis://:pw@host:6379/0\n") }
        .to raise_error(OpenLanes::Error, /commands\.#{command}\.redis_url carries a password.*REDIS_URL/)
    end
  end

  it "refuses a redis_url whose password is a query parameter" do
    ["redis://host:6379/0?password=pw", "redis://host/0?db=1&PASSWORD=pw"].each do |url|
      expect { parse("redis_url: '#{url}'\n") }.to raise_error(OpenLanes::Error, /redis_url carries a password/)
    end
    expect(parse("redis_url: 'redis://host:6379/0?password='\n").redis_url).to eq("redis://host:6379/0?password=")
  end

  it "refuses a redis_url that does not parse as a URL but still carries a password" do
    expect(described_class.password?("redis://user:p w@host")).to be(true)
    expect(described_class.password?("redis://ho st:6379")).to be(false)
  end

  it "refuses a token used as the redis_url's user name" do
    expect { parse("redis_url: redis://#{token}@host:6379/0\n") }
      .to raise_error(OpenLanes::Error, /redis_url looks like a secret/)
  end

  it "refuses a token-shaped value at any depth, naming the key path" do
    expect { parse("project: #{token}\n") }
      .to raise_error(OpenLanes::Error, /project looks like a secret.*environment variable/)
    expect { parse("merge:\n  method: sk-ant-api03-#{"Lm4Np5Qr" * 3}\n") }
      .to raise_error(OpenLanes::Error, /merge\.method looks like a secret/)
  end

  it "refuses a token anywhere inside a command line, not only at its start" do
    yaml = "coverage:\n  command: CODECOV_TOKEN=#{token} bundle exec rspec\n  report_command: echo 1\n  minimum: 9\n"
    expect { parse(yaml) }.to raise_error(OpenLanes::Error, /coverage\.command looks like a secret/)
  end

  it "refuses a URL with a password inside a command line" do
    yaml = "coverage:\n  command: DATABASE_URL=postgres://app:pw@db/app rspec\n  report_command: echo 1\n  minimum: 9\n"
    expect { parse(yaml) }.to raise_error(OpenLanes::Error, /coverage\.command looks like a secret/)
  end

  # `project: sk-8 ski club` was refused when the pattern was a bare prefix.
  it "lets words that merely start like a token through" do
    ["sk-8 ski club", "sk-server --port 1", "ghp_short", "xoxb-1", "AKIA Motors", "task-#{"a" * 20}"].each do |value|
      expect { described_class.refuse!({ "project" => value }, "f.yml") }.not_to raise_error, value
    end
  end

  it "refuses a credential-named key with a value" do
    expect { described_class.refuse!({ "linear" => { "api_key" => "abc" } }, "f.yml") }
      .to raise_error(OpenLanes::Error, /f\.yml: linear\.api_key looks like a secret/)
    expect { described_class.refuse!({ "x" => { "github_token" => "abc" } }, "f.yml") }
      .to raise_error(OpenLanes::Error, /x\.github_token/)
  end

  it "parses a token budget written as a string" do
    expect { parse("commands:\n  run:\n    max_tokens: 200k\n") }.not_to raise_error
  end

  it "lets a harmless value through under every string-typed key in the config schema" do
    schema = JSON.parse(File.read(File.expand_path("../../../schemas/openlanes-config.schema.json", __dir__)))
    paths = []
    collect = lambda do |node, keys|
      (node["properties"] || {}).each do |key, child|
        types = Array(child["type"])
        paths << [*keys, key] if types.include?("string")
        collect.call(child, [*keys, key])
      end
    end
    collect.call(schema, [])

    expect(paths).not_to be_empty
    paths.each do |keys|
      settings = keys.reverse.reduce("harmless") { |inner, key| { key => inner } }
      expect { described_class.refuse!(settings, "f.yml") }.not_to raise_error, keys.join(".")
    end
  end

  it "lets an empty credential-named key and numeric token counts through" do
    expect { described_class.refuse!({ "api_key" => "", "budget" => { "max_tokens" => 100 } }, "f.yml") }
      .not_to raise_error
  end
end
