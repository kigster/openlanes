# frozen_string_literal: true

# The human-mode watch (M4) inside the tick loop. GitHub is a double; the
# clock is a variable; the plans are real folders that really move.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:state) { OpenLanes::Engine::StateFile.new(path: OpenLanes::Engine::StateFile.for(tree)) }
  let(:clock) { [100.0] }
  let(:github) { instance_double(OpenLanes::Vcs::GitHub, pulls: rows, review_comments: comments) }
  let(:comments) { [{ author: "octo", body: "Rename the method", url: "https://github.com/o/r/pull/11#c1" }] }
  let(:rows) do
    [{ number: 11, open: true, state: "Open 🟡", labels: %w[review-rejected] },
     { number: 12, open: true, state: "Open 🟡", labels: %w[ready-to-merge] },
     { number: 13, open: false, state: "Merged 🟣", labels: [] },
     { number: 14, open: false, state: "Closed 🔴", labels: [] }]
  end
  let(:watch) { OpenLanes::Engine::PrWatch.new(github:, clock: -> { clock.first }) }
  let(:boards) { [] }
  # leah handles only ⚪️, so no agent starts on these plans: what moves them is the watch.
  let(:runner) do
    OpenLanes::Engine::Runner.new(tree:,
      executor: ->(*) { raise "no agent should start" },
      agents:   OpenLanes::Agents::Registry.new.only("leah-researcher"),
      state:,
      sleeper:  ->(_) {})
  end
  let(:dispatcher) do
    described_class.new(runner:, state:, sleeper: ->(_) {}, on_board: ->(b) { boards << b }, stay: true, watch:)
  end

  def files = { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## U1\n" }
  def status_of(ordinal) = tree.reload.find(ordinal).status.key

  before do
    plans do |t|
      t.plan "001.00", :in_review, "rejected", files:, prs: [t.open(11, "a")]
      t.plan "002.00", :in_review, "waiting", files:, prs: [t.open(12, "b")]
      t.plan "003.00", :in_review, "merged", files:, prs: [t.open(13, "c")]
      t.plan "004.00", :in_review, "closed", files:, prs: [t.open(14, "d")]
    end
    allow(OpenLanes::Execution::Control).to receive(:quit?).and_return(false)
  end

  # Ticks until the poll's thread has returned and its outcomes are applied.
  def tick_until_settled
    dispatcher.tick
    dispatcher.instance_variable_get(:@watching)&.join
    dispatcher.tick
  end

  it "asks GitHub nothing before 15 s have passed" do
    dispatcher.tick
    clock[0] = 114.0
    dispatcher.tick

    expect(github).not_to have_received(:pulls)
  end

  context "when 15 s have passed" do
    before do
      dispatcher.tick
      clock[0] = 115.0
      tick_until_settled
    end

    it "moves a rejected plan to 🔴 and leaves the comments for luke and rey" do
      mail = OpenLanes::Plans::Mailbox.new(dir: tree.reload.find("001.00").feature.path).messages

      aggregate_failures do
        expect(status_of("001.00")).to eq(:rejected)
        expect(mail.map(&:to)).to include("luke-backend", "rey-frontend")
        expect(mail.first.body).to include("Rename the method")
      end
    end

    it "moves a merged plan to ✅ and a closed one to ❌" do
      aggregate_failures do
        expect(status_of("003.00")).to eq(:approved)
        expect(status_of("004.00")).to eq(:discarded)
      end
    end

    it "puts the pull request still open on the board and in the state file" do
      state.save
      reread = OpenLanes::Engine::StateFile.new(path: state.path).load

      aggregate_failures do
        expect(status_of("002.00")).to eq(:in_review)
        expect(boards.last.waiting_on).to eq("002.00" => [12])
        expect(reread.waiting_on).to eq("002.00" => [12])
      end
    end

    it "makes one pulls call for every plan" do
      expect(github).to have_received(:pulls).once
    end
  end

  it "carries on when GitHub cannot be read, and tries again next interval" do
    allow(github).to receive(:pulls).and_raise(OpenLanes::Error, "gh: HTTP 502")
    dispatcher.tick
    clock[0] = 115.0
    tick_until_settled

    aggregate_failures do
      expect(status_of("001.00")).to eq(:in_review)
      expect(boards.last.waiting_on).to eq({})
    end
  end

  it "never watches without a watch, as under plain openlanes run" do
    plain = described_class.new(runner:, state:, sleeper: ->(_) {}, stay: false)
    plain.tick
    clock[0] = 1000.0
    plain.tick

    aggregate_failures do
      expect(github).not_to have_received(:pulls)
      expect(plain.board.waiting_on).to eq({})
    end
  end
end
