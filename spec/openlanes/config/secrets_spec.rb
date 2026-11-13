# frozen_string_literal: true

RSpec.describe OpenLanes::Config::Secrets do
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

  it "refuses a token-shaped value at any depth, naming the key path" do
    expect { parse("project: ghp_abcdef1234567890\n") }
      .to raise_error(OpenLanes::Error, /project looks like a secret.*environment variable/)
    expect { parse("merge:\n  method: sk-ant-xyz\n") }
      .to raise_error(OpenLanes::Error, /merge\.method looks like a secret/)
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
