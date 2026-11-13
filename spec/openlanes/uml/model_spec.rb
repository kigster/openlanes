# frozen_string_literal: true

RSpec.describe OpenLanes::Uml::Model do
  subject(:model) { with_ruby_project(files) { |root| OpenLanes::Uml.model(root) } }

  let(:files) do
    {
      "lib/shop.rb"              => "module Shop\n  Error = Class.new(StandardError)\nend\n",
      "lib/shop/billing/base.rb" => "module Shop\n  module Billing\n    class Base; end\n  end\nend\n",
      "lib/shop/billing/card.rb" => <<~RUBY,
        module Shop
          module Billing
            class Card < Base
              include Shop::Audit::Trail
              Charge = Data.define(:amount)

              def pay = Charge.new(amount: Audit::Log.write(self))
              def fail! = raise Error
              def again = Card.new
            end
          end
        end
      RUBY
      "lib/shop/audit/trail.rb"  => "module Shop\n  module Audit\n    module Trail; end\n  end\nend\n",
      "lib/shop/audit/log.rb"    => "module Shop\n  module Audit\n    class Log\n      LEVELS = %w[info].freeze\n    end\n  end\nend\n",
      "spec/shop_spec.rb"        => "class Spy < Shop::Billing::Card; end\n"
    }
  end

  def edges = model.edges.map { [it.from, it.to, it.kind] }

  it "draws classes and included modules, never spec/ and never a folded value type" do
    expect(model.nodes.map(&:name)).to eq(%w[Shop::Audit::Log Shop::Audit::Trail Shop::Billing::Base Shop::Billing::Card Shop::Error])
  end

  it "types every edge once, the parent as inherits even where the body names it too" do
    expect(edges).to eq([
                          ["Shop::Billing::Card", "Shop::Audit::Log", :uses],
                          ["Shop::Billing::Card", "Shop::Audit::Trail", :includes],
                          ["Shop::Billing::Card", "Shop::Billing::Base", :inherits],
                          ["Shop::Billing::Card", "Shop::Error", :uses]
                        ])
  end

  it "groups by the first two segments, and a two-segment class with its parent" do
    expect(%w[Shop::Billing::Card Shop::Billing Shop::Error Shop].map { model.namespaces.of(it) })
      .to eq(%w[Shop::Billing Shop::Billing Shop Shop])
  end

  it "counts namespace dependencies once per pair of definitions" do
    expect(model.dependencies).to eq(%w[Shop::Billing Shop::Audit] => 2, %w[Shop::Billing Shop] => 1)
  end

  it "marks a drawn module as one, and never a class" do
    expect(%w[Shop::Audit::Trail Shop::Audit::Log].map { model.module?(it) }).to eq([true, false])
  end

  context "with a module that defines methods" do
    before do
      files["lib/shop/audit/clock.rb"] = "module Shop\n  module Audit\n    module Clock\n      module_function\n\n      " \
                                         "def now = Time.now\n    end\n  end\nend\n"
      files["lib/shop/audit.rb"] = "module Shop\n  module Audit\n    def self.log = Log.new\n  end\nend\n"
      files["lib/shop/billing/later.rb"] = "module Shop\n  module Billing\n    class Later\n      def at = Audit::Clock.now\n    end\n  end\nend\n"
    end

    it "draws it, and a facade under its own namespace, but never a module holding only constants" do
      expect(model.nodes.map(&:name) & %w[Shop Shop::Audit Shop::Audit::Clock Shop::Billing])
        .to eq(%w[Shop::Audit Shop::Audit::Clock])
    end

    it "draws the edges that reach it and leave it" do
      expect(edges).to include(["Shop::Billing::Later", "Shop::Audit::Clock", :uses], ["Shop::Audit", "Shop::Audit::Log", :uses])
    end
  end

  context "with a Rails application" do
    let(:files) do
      {
        "config/application.rb"         => "module Store\n  class Application; end\nend\n",
        "app/models/user.rb"            => "class User\n  def mailer = WelcomeMailer\nend\n",
        "app/mailers/welcome_mailer.rb" => "class WelcomeMailer; end\n",
        "lib/store/importer.rb"         => "module Store\n  class Importer\n    def run = User.new\n  end\nend\n"
      }
    end

    it "reads app/ and lib/, and groups top-level classes by their autoload directory" do
      expect(%w[User WelcomeMailer Store::Importer].map { model.namespaces.of(it) })
        .to eq(%w[app/models app/mailers Store])
    end

    it "draws the edge between them" do
      expect(edges).to include(["User", "WelcomeMailer", :uses], ["Store::Importer", "User", :uses])
    end
  end
end
