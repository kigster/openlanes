# frozen_string_literal: true

RSpec.describe OpenLanes::Uml::Writer do
  let(:files) { { "lib/shop/billing/card.rb" => "module Shop\n  module Billing\n    class Card; end\n  end\nend\n" } }
  let(:dir) { Dir.mktmpdir("uml-out") }

  def write_into(dir) = with_ruby_project(files) { |root| OpenLanes::Uml.writer(root, title: "Shop").write(dir) }

  after { FileUtils.rm_rf(dir) }

  it "writes the map as README.md, linking one page per namespace" do
    write_into(dir)

    expect([Dir.children(dir).sort, File.read(File.join(dir, "README.md"))])
      .to match([%w[README.md shop-billing.md], /\A#{Regexp.escape(described_class::MARKER)}\n\n# Shop namespaces\n.*\[shop-billing\]\(shop-billing.md\)/m])
  end

  it "wraps each diagram in a mermaid fence GitHub renders" do
    write_into(dir)

    expect(File.read(File.join(dir, "shop-billing.md"))).to include("```mermaid\nclassDiagram\n", "Card")
  end

  it "removes a page it wrote earlier for a namespace that is gone, and nothing it did not write" do
    File.write(File.join(dir, "shop-gone.md"), "#{described_class::MARKER}\n")
    File.write(File.join(dir, "notes.md"), "# Mine\n")
    write_into(dir)

    expect(Dir.children(dir).sort).to eq(%w[README.md notes.md shop-billing.md])
  end
end
