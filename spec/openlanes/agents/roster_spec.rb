# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# `openlanes agents`. Everything here is read from the definition files,
# so the examples write real ones rather than stubbing the loader: a summary of
# an agent that Ruby maintains separately is the drift this command exists to
# prevent.
RSpec.describe OpenLanes::Agents::Roster do
  subject(:roster) { described_class.new(agents: OpenLanes::Agents::Registry.new(dir: dir)) }

  let(:dir) { @dir }

  around do |example|
    Dir.mktmpdir("agents") do |tmp|
      @dir = tmp
      write(tmp, "luke-backend", <<~MD)
        ---
        name: luke-backend
        description: Builds one work unit from a plan.
        handles: [building, rejected]
        advances_to: ready_for_review
        model: sonnet
        allowed_tools: [Read, Write]
        ---
        You are implementing one work unit.
      MD
      write(tmp, "hansolo-reviewer", <<~MD)
        ---
        name: hansolo-reviewer
        description: Reads the diff against the plan.
        handles: [ready_for_review]
        model: sonnet
        ---
        You are reviewing.
      MD
      write(tmp, "lando-broker", <<~MD)
        ---
        name: lando-broker
        description: Drains blocked.md.
        handles: [blocked, product_blocked]
        model: sonnet
        ---
        You are draining.
      MD
      example.run
    end
  end

  def write(dir, name, body) = File.write(File.join(dir, "#{name}.md"), body)

  def plain(text) = text.gsub(/\e\[[0-9;]*[a-zA-Z]/, "")

  describe "#list" do
    let(:table) { plain(roster.list) }

    # The fixtures are written luke first, so name order is an actual sort,
    # not the order the files happened to load in.
    it "names every agent, in name order" do
      expect(table.scan(/^│ (\S+-\S+)\s/).flatten).to eq(%w[hansolo-reviewer lando-broker luke-backend])
    end

    # Words only. The widget measures a cell in characters and the terminal
    # draws an emoji in two, so a status emoji in a cell breaks the frame.
    it "writes each state as its words" do
      expect(table).to include("Building", "Ready for Review")
    end

    # The regression this guards: the variation-selector emoji (⭐️, ⭕️,
    # 🅱️) cost two characters and two cells, so a row carrying one used to
    # land a column short of every row that did not.
    it "keeps no status emoji in any cell" do
      expect(table).not_to match(/[⭐⭕⚪🅱🕰🟡🟢🔴🎨👀✅🔎📋]/)
    end

    # Every row is the same width, which is the whole point of dropping them.
    it "draws a frame whose rows all line up" do
      widths = table.lines.map { |line| line.chomp.chars.size }.uniq
      expect(widths.size).to eq(1)
    end

    # An agent with no advances_to is never offered work by the loop. Printing
    # a blank there would read as "advances to nothing in particular".
    it "says read-only rather than leaving the destination blank" do
      expect(table).to match(/hansolo-reviewer.*read-only/)
    end

    # Only `unblock` starts an agent that handles nothing but settled states,
    # and the folder's name afterwards comes from what its files justify.
    it "says by contents for an agent only a command starts" do
      expect(table).to match(/lando-broker.*by contents/)
    end

    it "says so plainly when there are no definitions to list" do
      Dir.mktmpdir("empty") do |empty|
        expect(described_class.new(agents: OpenLanes::Agents::Registry.new(dir: empty)).list).to include("No agent definitions")
      end
    end
  end
end
