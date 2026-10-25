# frozen_string_literal: true

# docs/architecture/ is generated from lib/ by `just update-architecture`.
# A pull request that moves a class and forgets to regenerate leaves a
# picture of code that no longer exists; this is where that shows.
# docs/architecture/before/ is the frozen snapshot from before the 4.0
# refactor and is never compared.
RSpec.describe "docs/architecture" do
  let(:dir) { File.join(OpenLanes::Uml::GEM_ROOT, "docs", "architecture") }
  let(:expected) { OpenLanes::Uml.writer(OpenLanes::Uml::GEM_ROOT, title: OpenLanes::Uml::SELF_TITLE).files }
  let(:on_disk) { Dir.glob(File.join(dir, "*.md")).to_h { [File.basename(it), File.read(it)] } }

  it "is current with lib/; run `just update-architecture` when it is not" do
    stale = (expected.keys | on_disk.keys).reject { expected[it] == on_disk[it] }

    expect(stale).to eq([])
  end

  it "keeps the frozen before/ snapshot" do
    expect(File.read(File.join(dir, "before", "README.md"))).to include("Frozen", "classDiagram")
  end
end
