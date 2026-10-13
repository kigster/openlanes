# frozen_string_literal: true

RSpec.describe OpenLanes::Config do
  def parse(text) = described_class.parse(text, path: "/p/.openlanes.yml")

  it "reads redis_url, the live run's Redis (W16)" do
    expect(parse("redis_url: rediss://:pw@cache:6380/2\n").redis_url).to eq("rediss://:pw@cache:6380/2")
  end

  it "writes it back" do
    expect(described_class.new(jobs: 2, redis_url: "redis://h/0").to_yaml).to eq("jobs: 2\nredis_url: redis://h/0\n")
  end

  it "refuses an address that is not a Redis URL, naming the file" do
    expect { parse("redis_url: http://h/0\n") }
      .to raise_error(OpenLanes::Error, %r{/p/\.openlanes\.yml: redis_url: "http://h/0" is not a redis://, rediss://, unix:// URL})
  end

  it "has none by default" do
    expect(parse("jobs: 2\n").redis_url).to be_nil
  end
end
