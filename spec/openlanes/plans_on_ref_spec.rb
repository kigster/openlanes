# frozen_string_literal: true

# A branch's numbers decide where an adopted pull request's plan goes, and an
# archived plan still holds its number.
RSpec.describe OpenLanes, ".plans_on_ref", :tree do
  let(:root) { File.dirname(plans_root) }

  def git(*)
    system("git",
      "-C",
      root,
      "-c",
      "user.name=Test Author",
      "-c",
      "user.email=test@example.com",
      *,
      out: File::NULL,
      err: File::NULL)
  end

  it "reads the inactive subfolders on the ref as well as the top level" do
    plans do |t|
      t.plan "001.00", :new, "open", files: { "spec.md" => spec_body }
      t.plan "005.00", :approved, "done", under: "archive", archived_on: Date.new(2026, 9, 1), files: { "spec.md" => spec_body }
    end
    git("init", "-q", "-b", "main")
    git("add", ".")
    git("commit", "-q", "-m", "plans")

    expect(described_class.plans_on_ref(root, "main").map(&:to_s)).to contain_exactly("001.00", "005.00")
  end
end
