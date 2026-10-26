# frozen_string_literal: true

require "stringio"

RSpec.describe OpenLanes::Launcher do
  subject(:launcher) { described_class.new(argv, StringIO.new, StringIO.new, stderr, kernel) }

  let(:argv) { %w[plans] }
  let(:stderr) { StringIO.new }
  let(:kernel) { class_double(Kernel, exit: nil) }
  let(:cli) { instance_double(Dry::CLI) }

  before do
    allow(Dry::CLI).to receive(:new).and_return(cli)
    allow(cli).to receive(:call, &outcome)
    launcher.execute!
  end

  describe "when the command returns" do
    let(:outcome) { proc {} }

    it { expect(kernel).to have_received(:exit).with(0) }
  end

  describe "when the command exits with a status" do
    let(:outcome) { proc { exit(64) } }

    it { expect(kernel).to have_received(:exit).with(64) }
  end

  describe "when the command raises" do
    let(:outcome) { proc { raise ArgumentError, "bad plan" } }

    it { expect(kernel).to have_received(:exit).with(1) }
    it { expect(stderr.string).to include("Error: bad plan") }
  end

  # A ScriptError is no StandardError; exiting 0 in `ensure` once hid it.
  describe "when loading the command fails" do
    let(:outcome) { proc { raise LoadError, "cannot load such file -- openlanes/cli/app/app" } }

    it { expect(kernel).to have_received(:exit).with(1) }
    it { expect(stderr.string).to include("cannot load such file") }
  end

  describe "with --no-color" do
    let(:argv) { %w[plans --no-color] }
    let(:outcome) { proc {} }

    it { expect(cli).to have_received(:call).with(arguments: %w[plans]) }
  end
end
