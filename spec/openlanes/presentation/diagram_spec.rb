# frozen_string_literal: true

# The diagram exists so that nobody hand-draws a second picture of the state
# machine next to the one {Documentation} already generates. These examples
# are what stop this generator itself from becoming that second picture: every
# state and every edge {StateMachine} allows has to appear here, so adding a
# state or rerouting a transition without this diagram following is a failing
# build.
RSpec.describe OpenLanes::Presentation::Diagram do
  subject(:diagram) { described_class.new }

  let(:rendered) { diagram.render }

  describe "#render" do
    it "names every state the machine knows — emoji and label" do
      aggregate_failures do
        OpenLanes::Plans::STATUSES.each do |status|
          expect(rendered).to include(status.emoji), "#{status.key}: emoji missing"
          expect(rendered).to include(status.label), "#{status.key}: label missing"
        end
      end
    end

    it "draws exactly the edges the machine allows — no more, no fewer" do
      actual = OpenLanes::Plans::StateMachine.inbound.flat_map { |to, froms| froms.map { |from| [from, to] } }

      expect(parsed_edges(rendered).sort).to eq(actual.sort)
    end

    it "walks the main spine from New through Deployed, in order, on one line" do
      chain = []
      key = :new
      while key
        chain << key
        key = OpenLanes::Plans::StateMachine::SPINE[key]
      end

      spine_line = rendered.lines.find { |l| l.include?("New") && l.include?("Deployed") }

      expect(spine_line).not_to be_nil
      positions = chain.map { |k| spine_line.index(OpenLanes::Plans::STATUS_BY_KEY.fetch(k).label) }
      expect(positions).to eq(positions.sort), "spine states are not in machine order"
    end

    it "lists every terminal state — the ones nothing follows" do
      terminal = OpenLanes::Plans::STATUSES.select(&:terminal?)

      aggregate_failures do
        terminal.each { |s| expect(rendered).to include(s.label) }
        expect(rendered).to include("TERMINAL")
      end
    end

    it "flags the look-alike families the state machine defines" do
      OpenLanes::Plans::StateMachine::FAMILIES.each do |members|
        members.each { |key| expect(rendered).to include(OpenLanes::Plans::STATUS_BY_KEY.fetch(key).label) }
      end
    end

    it "points back at the state machine as the source" do
      expect(rendered).to include("lib/openlanes/state_machine.rb")
    end

    it "is plain text with no unclosed colour codes when NO_COLOR is set" do
      expect(rendered).not_to include("\e[")
    end

    it "ends with a single trailing newline" do
      expect(rendered).to end_with("\n")
      expect(rendered).not_to end_with("\n\n")
    end
  end

  describe "drift" do
    # The failure this catches: someone adds a state or reroutes a transition
    # in the machine, and this diagram quietly keeps showing the old shape.
    it "draws exactly as many terminal states as StateMachine reports" do
      drawn = rendered[/^TERMINAL.*?\n\n(.*?)\n\n/m, 1].to_s.lines.reject(&:empty?)

      expect(drawn.size).to eq(OpenLanes::Plans::STATUSES.count(&:terminal?))
    end

    it "draws exactly as many spine rejoins as StateMachine::SPINE has off-chain entries" do
      chain = []
      key = :new
      while key
        chain << key
        key = OpenLanes::Plans::StateMachine::SPINE[key]
      end

      off_chain = OpenLanes::Plans::StateMachine::SPINE.except(*chain)
      rejoin_block = rendered[/^REJOINING THE SPINE.*?\n\n(.*?)\n\n/m, 1].to_s.lines.reject(&:empty?)

      expect(rejoin_block.size).to eq(off_chain.size)
    end
  end

  # Reconstructs the [from, to] edges the rendered text actually draws, so the
  # "exactly the edges the machine allows" example does not degrade into
  # "these two emoji appear somewhere" — the failure that would let a missing
  # or extra edge through unnoticed.
  #
  # @param rendered [String]
  # @return [Array<Array(Symbol, Symbol)>]
  def parsed_edges(rendered)
    spine_edges(rendered) + rejoin_edges(rendered) + fan_out_edges(rendered)
  end

  # The main spine: one line, several `──▶`-joined labels; every adjacent pair
  # is an edge.
  #
  # @param rendered [String]
  # @return [Array<Array(Symbol, Symbol)>]
  def spine_edges(rendered)
    line = rendered.split(/^MAIN SPINE.*?\n\n/, 2).last.to_s.lines.first.to_s
    labels_in(line).each_cons(2).to_a
  end

  # Rejoins: one `from ──▶ to` pair per line.
  #
  # @param rendered [String]
  # @return [Array<Array(Symbol, Symbol)>]
  def rejoin_edges(rendered)
    block = rendered.split(/^REJOINING THE SPINE.*?\n\n/, 2).last.to_s.split("\n\n", 2).first.to_s
    block.lines.filter_map { |line|
      pair = labels_in(line)
      pair if pair.size == 2
    }
  end

  # Everything else: a header line naming the source, followed by `├─▶`/`└─▶`
  # lines each naming one target of that source.
  #
  # @param rendered [String]
  # @return [Array<Array(Symbol, Symbol)>]
  def fan_out_edges(rendered)
    block = rendered.split(/^OTHER TRANSITIONS.*?\n\n/, 2).last.to_s.split(/^TERMINAL/, 2).first.to_s

    edges = []
    current_from = nil
    block.lines.each do |line|
      if line.match?(/^\s+[├└]─▶/)
        to_key = label_in(line)
        edges << [current_from, to_key] if current_from && to_key
      else
        key = label_in(line)
        current_from = key if key
      end
    end
    edges
  end

  # @param line [String]
  # @return [Symbol, nil] the state whose label appears in the line, if any
  # Longest label first, because one label can be a prefix of another:
  # "Building" appears inside "Building UI", and taking the first match would
  # read every 🎨 segment as a 🟡 one.
  def label_in(line)
    OpenLanes::Plans::STATUSES.select { |s| line.include?(s.label) }.max_by { |s| s.label.length }&.key
  end

  # @param line [String]
  # @return [Array<Symbol>] every state label on the line, in reading order
  def labels_in(line)
    line.split("──▶").filter_map { |segment| label_in(segment) }
  end
end
