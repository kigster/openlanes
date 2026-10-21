# frozen_string_literal: true

# docs/thread-safety.md lists every guard under lib/openlanes. A new mutex
# nobody wrote down is a guard nobody can reason about, so it fails here.
RSpec.describe "The thread-safety inventory" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:rows) { File.read(File.join(root, "docs/thread-safety.md")).lines.select { it.start_with?("| `lib/") } }
  let(:statuses) { rows.map { it.strip.split("|").last.strip } }
  let(:guard) { /\b(?:Mutex|Monitor|(?:Thread::)?(?:Sized)?Queue|ConditionVariable)\.new\b|Concurrent::\w+\.new\b/ }
  let(:guarded_files) do
    Dir[File.join(root, "lib/openlanes/**/*.rb")].select { File.read(it).match?(guard) }.map { it.delete_prefix("#{root}/") }
  end

  it "finds the guards it is meant to keep track of" do
    expect(guarded_files).to include("lib/openlanes/live/claims.rb", "lib/openlanes/execution/child.rb")
  end

  it "names every file under lib/openlanes that creates a guard" do
    expect(guarded_files.reject { |file| rows.join.include?("`#{file}`") }).to eq([])
  end

  it "has no unguarded row" do
    expect(statuses).not_to include("unguarded")
  end

  it "gives every row one of the known statuses" do
    expect(statuses - %w[guarded frozen thread-local]).to eq([])
  end
end
