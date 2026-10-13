# frozen_string_literal: true

# Frontmatter is the one place a user's own file meets a parser, so what it
# accepts is a promise. `YAML.safe_load` with its defaults refuses to build a
# Date, which made `date: 2026-08-31` — a line every markdown convention
# allows — read as frontmatter that would not parse at all.
RSpec.describe OpenLanes::Frontmatter do
  def split(content) = described_class.split(content)

  it "returns the mapping and the body" do
    meta, body = split("---\ntitle: Tax Rule DSL\n---\nRules read like statute.\n")

    expect(meta).to eq("title" => "Tax Rule DSL")
    expect(body.strip).to eq("Rules read like statute.")
  end

  it "loads a date rather than refusing the whole file" do
    meta, = split("---\ntitle: Tax Rule DSL\ndate: 2026-08-31\n---\nbody\n")

    expect(meta["title"]).to eq("Tax Rule DSL")
    expect(meta["date"]).to eq(Date.new(2026, 8, 31))
  end

  it "loads a timestamp too" do
    meta, = split("---\nwritten: 2026-08-31 09:30:00\n---\nbody\n")

    expect(meta["written"]).to be_a(Time)
  end

  it "still refuses a class it was never told about" do
    expect { split("---\nwhen: !ruby/object:Struct {}\n---\nbody\n") }
      .to raise_error(Psych::DisallowedClass)
  end

  it "reads a file with no frontmatter as all body" do
    meta, body = split("Just prose.\n")

    expect(meta).to eq({})
    expect(body).to eq("Just prose.\n")
  end

  it "reads frontmatter that is not a mapping as no keys" do
    meta, body = split("---\n- one\n- two\n---\nbody\n")

    expect(meta).to eq({})
    expect(body).to eq("body\n")
  end

  it "reads empty frontmatter as no keys" do
    meta, = split("---\n\n---\nbody\n")

    expect(meta).to eq({})
  end

  it "raises on frontmatter that is not YAML at all" do
    expect { split("---\ntitle: [unclosed\n---\nbody\n") }.to raise_error(Psych::SyntaxError)
  end
end
