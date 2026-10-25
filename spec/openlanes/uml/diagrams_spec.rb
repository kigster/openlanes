# frozen_string_literal: true

RSpec.describe "the uml diagrams" do
  let(:files) do
    {
      "lib/shop/billing/card.rb" => "module Shop\n  module Billing\n    class Card < Base\n      include Shop::Audit::Trail\n      " \
                                    "def log = Shop::Audit::Log\n    end\n    class Base; end\n  end\nend\n",
      "lib/shop/audit/log.rb"    => "module Shop\n  module Audit\n    class Log; end\n    module Trail; end\n  end\nend\n"
    }
  end

  def draw = with_ruby_project(files) { |root| yield OpenLanes::Uml.model(root) }

  it "maps namespaces with the count of edges between them" do
    map = draw { OpenLanes::Uml::NamespaceMap.new(it).render }

    expect(map).to eq(<<~MERMAID)
      classDiagram
        class Shop__Audit["Shop::Audit"]
        class Shop__Billing["Shop::Billing"]
        Shop__Billing ..> Shop__Audit : 2
    MERMAID
  end

  it "draws one namespace's classes by short name and what they reach by full name" do
    diagram = draw { OpenLanes::Uml::ClassDiagram.new(it, "Shop::Billing").render }

    expect(diagram).to eq(<<~MERMAID)
      classDiagram
        class Shop__Audit__Log["Shop::Audit::Log"]
        class Shop__Audit__Trail["Shop::Audit::Trail"]
        <<module>> Shop__Audit__Trail
        class Shop__Billing__Base["Base"]
        class Shop__Billing__Card["Card"]
        Shop__Billing__Card ..> Shop__Audit__Log : uses
        Shop__Billing__Card ..|> Shop__Audit__Trail : includes
        Shop__Billing__Card --|> Shop__Billing__Base : inherits
    MERMAID
  end

  it "says so when a namespace declares no class" do
    files["lib/shop/none.rb"] = "module Shop\n  module None\n    module Helpers\n      def self.x = 1\n    end\n  end\nend\n"

    expect(draw { OpenLanes::Uml::ClassDiagram.new(it, "Shop::None").render }).to include('note "Shop::None declares no class"')
  end
end
