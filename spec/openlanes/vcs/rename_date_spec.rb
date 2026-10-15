# frozen_string_literal: true

# The date an archived plan's name carries: when it last changed state,
# which is when its folder was last renamed.
RSpec.describe OpenLanes::Vcs::RenameDate, :tree do
  let(:today) { Date.new(2030, 1, 1) }

  it "reads the date of the folder's latest rename from git, not of a later edit" do
    init_repo
    before = plans { |t| t.plan "001.00", :building, "x", files: { "spec.md" => spec_body } }
    before = Dir.glob(File.join(before, "001.00*")).first
    commit_all("start", date: "2026-08-01T10:00:00+00:00")
    after = File.join(plans_root, OpenLanes::Plans.plan_dirname("001.00", OpenLanes::Plans.status(:approved), "x"))
    repo_git("mv", before, after)
    commit_all("ship", date: "2026-09-15T10:00:00+00:00")
    File.write(File.join(after, "spec.md"), "#{spec_body}\nedited\n")
    commit_all("touch up", date: "2026-10-01T10:00:00+00:00")

    expect(described_class.for(after, today:)).to eq(Date.new(2026, 9, 15))
  end

  it "falls back to state.json's updated_at when git has no rename" do
    dir = plans { |t| t.plan "001.00", :approved, "x", files: { "state.json" => '{"updated_at":"2026-07-04T12:00:00-07:00"}' } }
    dir = Dir.glob(File.join(dir, "001.00*")).first

    expect(described_class.for(dir, today:)).to eq(Date.new(2026, 7, 4))
  end

  it "falls back to today when neither knows" do
    dir = plans { |t| t.plan "001.00", :approved, "x", files: { "state.json" => "not json" } }

    expect(described_class.for(Dir.glob(File.join(dir, "001.00*")).first, today:)).to eq(today)
  end
end
