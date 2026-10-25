# frozen_string_literal: true

RSpec.describe OpenLanes::Uml::Parser do
  def parse(source)
    with_ruby_project("lib/x.rb" => source) { |root| described_class.parse(File.join(root, "lib/x.rb"), file: "lib/x.rb") }
  end

  def find(definitions, name) = definitions.find { it.name == name }

  it "names nested and compact definitions in full" do
    definitions = parse(<<~RUBY)
      module Shop
        class Cart; end
      end
      class Shop::Order; end
    RUBY

    expect(definitions.map { [it.name, it.kind] }).to eq([["Shop", :module], ["Shop::Cart", :class], ["Shop::Order", :class]])
  end

  it "records the superclass and the mixins with the scope they were written in" do
    cart = find(parse("module Shop\n  class Cart < Base\n    include Pricing\n  end\nend\n"), "Shop::Cart")

    expect([cart.superclass, cart.mixins]).to eq([OpenLanes::Uml::Reference.new(path: "Base", scope: ["Shop"]),
                                                  [OpenLanes::Uml::Reference.new(path: "Pricing", scope: ["Shop::Cart", "Shop"])]])
  end

  it "records constant references, a leading :: as top-level only" do
    cart = find(parse("class Cart\n  def total = Tax::Rate.new.apply(::Money)\nend\n"), "Cart")

    expect(cart.references).to eq([OpenLanes::Uml::Reference.new(path: "Tax::Rate", scope: ["Cart"]),
                                   OpenLanes::Uml::Reference.new(path: "Money", scope: [])])
  end

  it "folds a Data.define in a class into that class, references and all" do
    definitions = parse("class Cart\n  Line = Data.define(:sku) do\n    def price = Catalog.price(sku)\n  end\nend\n")

    expect([find(definitions, "Cart::Line").owner, find(definitions, "Cart").references.map(&:path) - ["Data"]])
      .to eq(["Cart", ["Catalog"]])
  end

  it "keeps a Data.define in a module as a class of its own" do
    expect(find(parse("module Shop\n  Sku = Data.define(:code)\nend\n"), "Shop::Sku").kind).to eq(:class)
  end

  it "reads Class.new(Parent) as a class with a parent" do
    error = find(parse("module Shop\n  Error = Class.new(StandardError)\nend\n"), "Shop::Error")

    expect([error.kind, error.superclass.path]).to eq([:class, "StandardError"])
  end

  it "ignores a constant whose parent is a value it cannot know" do
    expect(find(parse("class Cart\n  def x = klass::Thing\nend\n"), "Cart").references).to eq([])
  end

  it "declares nothing for a plain constant" do
    expect(parse("module Shop\n  LIMIT = 3\nend\n").map(&:name)).to eq(["Shop"])
  end
end
