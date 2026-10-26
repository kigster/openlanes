# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Both of Viewer's paths shell out, so every example hands in lambdas and
# asserts on the commands. Launching a real viewer would pass on one machine
# and litter windows on another.
RSpec.describe OpenLanes::Presentation::Viewer do
  subject(:viewer) { described_class.new(launch:, pipe:) }

  let(:launched) { [] }
  let(:piped) { [] }
  let(:launch) {
    ->(*cmd) {
      launched << cmd
      true
    }
  }
  let(:pipe) do
    lambda do |cmd, &block|
      io = StringIO.new
      block.call(io)
      piped << [cmd, io.string]
    end
  end

  let(:paths) do
    %w[researcher backend-coder].map do |name|
      File.join(@dir, "#{name}.md").tap { |p| File.write(p, "# #{name}\n") }
    end
  end

  around do |example|
    Dir.mktmpdir("viewer") { |tmp|
      @dir = tmp
      example.run
    }
  end

  describe "#open" do
    it "hands each file to the system viewer, one open per file" do
      viewer.open(paths)

      expect(launched).to eq(paths.map { |p| ["open", p] })
    end

    it "takes a single path without ceremony" do
      viewer.open(paths.first)

      expect(launched).to eq([["open", paths.first]])
    end
  end

  describe "#mdfried" do
    context "when mdfried is already installed" do
      it "checks for the binary and does not install it again" do
        viewer.mdfried(paths.first)

        expect(launched).to eq([[described_class::DETECT]])
      end

      it "pipes each file's markdown into mdfried" do
        viewer.mdfried(paths)

        expect(piped).to eq([["mdfried", "# researcher\n"],
                             ["mdfried", "# backend-coder\n"]])
      end
    end

    context "when mdfried is missing" do
      let(:launch) {
        ->(*cmd) {
          launched << cmd
          cmd != [described_class::DETECT]
        }
      }

      it "installs it through brew before rendering" do
        viewer.mdfried(paths.first)

        expect(launched).to eq([[described_class::DETECT], [described_class::INSTALL]])
        expect(piped.size).to eq(1)
      end
    end

    context "when brew cannot install it either" do
      let(:launch) {
        ->(*cmd) {
          launched << cmd
          false
        }
      }

      it "raises instead of piping into a command that is not there" do
        expect { viewer.mdfried(paths) }.to raise_error(OpenLanes::Error, /brew install mdfried/)
        expect(piped).to be_empty
      end
    end
  end
end
