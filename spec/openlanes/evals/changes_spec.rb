# frozen_string_literal: true

RSpec.describe OpenLanes::Evals::Changes, :tree do
  subject(:changes) { described_class.between(before, dir) }

  let(:before) { { "lib/a.rb" => "one\ntwo\n", "lib/gone.rb" => "x\n", "README.md" => "same\n" } }
  let(:dir) do
    File.dirname(plans_root).tap do |root|
      {
        "lib/a.rb"                => "one\nthree\nfour\n",
        "lib/new.rb"              => "fresh\n",
        "README.md"               => "same\n",
        ".plans/001.00-x/spec.md" => "ignored\n",
        ".git/HEAD"               => "ignored\n"
      }.each do |name, body|
        FileUtils.mkdir_p(File.dirname(File.join(root, name)))
        File.write(File.join(root, name), body)
      end
    end
  end

  it "lists what was edited, added or deleted, and nothing the plans or git hold" do
    expect(changes.paths).to eq(%w[lib/a.rb lib/gone.rb lib/new.rb])
  end

  it "counts lines added plus lines removed" do
    expect(changes.lines).to eq(5)
  end

  it "matches globs across directories" do
    expect(changes.matching("lib/**/*.rb")).to eq(%w[lib/a.rb lib/gone.rb lib/new.rb])
  end

  it "does not let a single star cross a directory" do
    expect(changes.matching("*.rb")).to eq([])
  end
end
