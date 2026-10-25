# frozen_string_literal: true

RSpec.describe OpenLanes::CLI::Uml do
  subject(:command) { described_class.new }

  let(:files) do
    {
      ".git/HEAD"                => "ref: refs/heads/main\n",
      "lib/shop/billing/card.rb" => "module Shop\n  module Billing\n    class Card\n      def log = Audit::Log\n    end\n  end\nend\n",
      "lib/shop/audit/log.rb"    => "module Shop\n  module Audit\n    class Log; end\n  end\nend\n"
    }
  end

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    original = [$stdout, $stderr]
    $stdout, $stderr = out, err
    status = 0
    begin
      command.call(**)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original
    end
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  def in_project(&) = with_ruby_project(files) { |root| Dir.chdir(root) { yield root } }

  it "prints the project's namespace map" do
    out, = in_project { run }

    expect(out).to start_with("classDiagram\n").and include("Shop__Billing ..> Shop__Audit : 1")
  end

  it "prints one namespace by its last segment, in any case" do
    out, = in_project { run(target: "billing") }

    expect(out).to include(%(class Shop__Billing__Card["Card"]), "Shop__Billing__Card ..> Shop__Audit__Log : uses")
  end

  it "refuses a namespace the project does not have, naming those it does" do
    _, err, status = in_project { run(target: "nowhere") }

    expect([status, unwrapped(err)]).to match([64, /No namespace nowhere\. Namespaces: Shop::Audit, Shop::Billing/])
  end

  it "writes to the file -o names" do
    content = in_project do |root|
      run(output: "out/map.mmd", quiet: true)
      File.read(File.join(root, "out/map.mmd"))
    end

    expect(content).to start_with("classDiagram\n")
  end

  it "writes the map and every namespace with --directory" do
    names = in_project do |root|
      run(directory: "docs/architecture", quiet: true)
      Dir.children(File.join(root, "docs/architecture")).sort
    end

    expect(names).to eq(%w[README.md shop-audit.md shop-billing.md])
  end

  it "draws OpenLanes itself for self, from anywhere" do
    out, = Dir.mktmpdir { |dir| Dir.chdir(dir) { run(target: "self", namespace: "uml") } }

    expect(out).to include(%(class OpenLanes__Uml__Parser["Parser"]))
  end

  it "refuses outside a project" do
    allow(OpenLanes::Project).to receive(:root).and_return(nil)
    _, err, status = run

    expect([status, unwrapped(err)]).to match([66, /No project here/])
  end
end
