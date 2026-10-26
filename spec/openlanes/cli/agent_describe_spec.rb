# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# `agents describe` opens definition files in a viewer rather than printing
# them: the file is the whole truth, and a pager-sized prompt dumped to the
# terminal was scrolling the table it followed off the screen.
RSpec.describe OpenLanes::CLI::Agents::Describe do
  subject(:command) { described_class.new(agents:, viewer:) }

  let(:agents) { OpenLanes::Agents::Registry.new(dir: @dir) }
  let(:viewer) { instance_double(OpenLanes::Presentation::Viewer, open: nil, mdfried: nil) }

  around do |example|
    Dir.mktmpdir("agents") do |tmp|
      @dir = tmp
      %w[researcher backend-coder unblocker].each do |name|
        File.write(File.join(tmp, "#{name}.md"), <<~MD)
          ---
          name: #{name}
          description: #{name} does its one thing.
          handles: [building]
          ---
          Prompt for #{name}.
        MD
      end
      example.run
    end
  end

  def path(name) = File.join(@dir, "#{name}.md")

  def run(**)
    err = StringIO.new
    status = 0

    original = $stderr
    $stderr = err
    begin
      command.call(**)
    rescue SystemExit => e
      status = e.status
    ensure
      $stderr = original
    end

    [strip_ansi(err.string), status]
  end

  it "opens the one agent a fragment singles out" do
    _, status = run(name: "researcher")

    expect(status).to eq(0)
    expect(viewer).to have_received(:open).with([path("researcher")])
  end

  it "opens every definition when given no name" do
    run

    expect(viewer).to have_received(:open)
      .with([path("backend-coder"), path("researcher"), path("unblocker")])
  end

  it "routes through mdfried when asked to stay in the terminal" do
    run(name: "backend-coder", mdfried: true)

    expect(viewer).to have_received(:mdfried).with([path("backend-coder")])
    expect(viewer).not_to have_received(:open)
  end

  it "hands every definition to mdfried when no name narrows it" do
    run(mdfried: true)

    expect(viewer).to have_received(:mdfried)
      .with([path("backend-coder"), path("researcher"), path("unblocker")])
  end

  # A fragment that fits several agents is a question, not an order.
  it "refuses an ambiguous fragment and names the candidates" do
    err, status = run(name: "e")

    expect(status).to eq(65)
    expect(err).to include("unblocker", "researcher", "backend-coder")
    expect(viewer).not_to have_received(:open)
  end

  it "refuses an unknown name and lists what it does know" do
    err, status = run(name: "ghost-agent")

    expect(status).to eq(65)
    expect(err).to include("ghost-agent").and include("backend-coder")
  end
end
