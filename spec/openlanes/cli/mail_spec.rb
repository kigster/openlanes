# frozen_string_literal: true

# `openlanes mail` is what a paired agent shells out to between steps, so
# the two commands are exercised the way an agent uses them: one sends, the
# other reads, against a real plan folder.
RSpec.describe "openlanes mail", :tree do
  let!(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "paired", files: { "spec.md" => spec_body, "plan.md" => "# P" } }
    path
  end

  # `send` publishes when Redis answers; these examples are about the file,
  # and must not reach a developer's own Redis. See cli/mail/send_spec.rb.
  before { allow(OpenLanes::Live).to receive(:connect).and_raise(OpenLanes::Live::Unavailable, "no Redis in this spec") }

  def run(command, **)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0

    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(dir: plans_root, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end

    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  def send(**) = run(OpenLanes::CLI::Mail::Send.new, **)

  def read(**) = run(OpenLanes::CLI::Mail::Read.new, **)

  def ack(**) = run(OpenLanes::CLI::Mail::Ack.new, **)

  def render(**) = run(OpenLanes::CLI::Mail::Render.new, **)

  it "delivers a message from one half to the other" do
    _out, err, status = send(body: "GET /returns/:id is up", plan: "001.00", from: "luke-backend", to: "rey-frontend")
    out, = read(plan: "001.00", for: "rey-frontend")

    aggregate_failures do
      expect(status).to eq(0)
      expect(err).to include("#1 → rey-frontend")
      expect(out).to include("luke-backend → rey-frontend", "GET /returns/:id is up")
    end
  end

  it "writes into the plan's own folder, where a person can read it after the round" do
    send(body: "hello", plan: "001", from: "luke-backend", to: "rey-frontend")

    expect(OpenLanes::Plans::PlanState.for(folder).messages.map { |m| m["body"] }).to eq(["hello"])
  end

  it "shows a reader nothing that was addressed to somebody else" do
    send(body: "for rey", plan: "001.00", from: "luke-backend", to: "rey-frontend")
    out, err, status = read(plan: "001.00", for: "luke-backend")

    aggregate_failures do
      expect(out).to be_empty
      expect(err).to include("Nothing for luke-backend")
      expect(status).to eq(0)
    end
  end

  it "shows only what arrived after the number the reader last saw" do
    3.times { |i| send(body: "message #{i + 1}", plan: "001.00", from: "luke-backend", to: "rey-frontend") }
    out, = read(plan: "001.00", for: "rey-frontend", after: "2")

    aggregate_failures do
      expect(out).to include("message 3")
      expect(out).not_to include("message 1", "message 2")
    end
  end

  # A poll that finds nothing is the ordinary case, not a failure: the
  # command is run before every significant step.
  it "prints nothing and exits zero before anybody has written" do
    out, _err, status = read(plan: "001.00", for: "rey-frontend")

    aggregate_failures do
      expect(out).to be_empty
      expect(status).to eq(0)
    end
  end

  it "refuses a plan the tree does not hold, naming the ones it does" do
    _out, err, status = send(body: "hello", plan: "009", from: "luke-backend", to: "rey-frontend")

    aggregate_failures do
      expect(err).to include("No plan 009", "001.00")
      expect(status).to eq(66)
    end
  end

  it "refuses a send with no recipient, rather than writing an entry nobody can read" do
    _out, err, status = send(body: "hello", plan: "001.00", from: "luke-backend")

    aggregate_failures do
      expect(err).to include("--to")
      expect(status).to eq(64)
      expect(File).not_to exist(File.join(folder, "mailbox.md"))
    end
  end

  it "refuses an empty message" do
    _out, err, status = send(body: "  ", plan: "001.00", from: "luke-backend", to: "rey-frontend")

    aggregate_failures do
      expect(err).to include("body")
      expect(status).to eq(64)
    end
  end

  describe "ack" do
    it "marks the reader's message read, and only that one" do
      send(body: "one", plan: "001.00", from: "luke-backend", to: "rey-frontend")
      send(body: "two", plan: "001.00", from: "luke-backend", to: "rey-frontend")
      _out, err, status = ack(number: "2", plan: "001.00", for: "rey-frontend")

      aggregate_failures do
        expect(status).to eq(0)
        expect(err).to include("#2 read by rey-frontend")
        expect(OpenLanes::Plans::PlanState.for(folder).messages.map { |m| m["read"] }).to eq(%w[no yes])
      end
    end

    it "exits non-zero on a number with no message" do
      _out, err, status = ack(number: "7", plan: "001.00", for: "rey-frontend")

      aggregate_failures do
        expect(status).to eq(65)
        expect(err).to include("no message #7")
      end
    end

    it "keeps both acks when two readers ack at the same moment" do
      send(body: "for rey", plan: "001.00", from: "luke-backend", to: "rey-frontend")
      send(body: "for luke", plan: "001.00", from: "rey-frontend", to: "luke-backend")

      [[1, "rey-frontend"], [2, "luke-backend"]].map do |number, reader|
        Thread.new { OpenLanes::Plans.mailbox(folder).ack(number, by: reader) }
      end.each(&:join)

      expect(OpenLanes::Plans::PlanState.for(folder).messages.map { |m| m["read"] }).to eq(%w[yes yes])
    end

    it "prints nothing under --quiet" do
      send(body: "one", plan: "001.00", from: "luke-backend", to: "rey-frontend")
      _out, err, status = ack(number: "1", plan: "001.00", for: "rey-frontend", quiet: true)

      expect([err, status]).to eq(["", 0])
    end
  end

  describe "render" do
    it "prints the whole exchange to STDOUT and writes nothing in the plan folder" do
      send(body: "GET /returns/:id is up", plan: "001.00", from: "luke-backend", to: "rey-frontend")
      before = Dir.children(folder).sort.to_h { |f| [f, File.mtime(File.join(folder, f))] }
      out, _err, status = render(plan: "001.00")

      aggregate_failures do
        expect(status).to eq(0)
        expect(out).to include("luke-backend → rey-frontend · unread", "GET /returns/:id is up")
        expect(Dir.children(folder).sort.to_h { |f| [f, File.mtime(File.join(folder, f))] }).to eq(before)
      end
    end
  end
end
