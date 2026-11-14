# frozen_string_literal: true

# `openlanes review PR LABEL` is the only door a review label goes through, so
# what it says when CI is red is the whole point of it.
RSpec.describe OpenLanes::CLI::Review do
  subject(:command) { described_class.new }

  let(:review) { instance_double(OpenLanes::Vcs::Review) }
  let(:initial) { OpenLanes::Plans::ReviewLabel::INITIAL.name }
  let(:rejected) { OpenLanes::Plans::ReviewLabel::REJECTED.name }
  let(:passing) { OpenLanes::Plans::ReviewLabel.passing.first.name }

  def result(**fields)
    OpenLanes::Vcs::Review::Result.new(
      pr: 12, from: [initial], to: rejected, ci: :green, refused: false, reason: nil, dry_run: false, **fields
    )
  end

  def run(pull_request, label, **)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(pull_request:, label:, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  before { allow(OpenLanes::Vcs).to receive(:review).and_return(review) }

  it "renders the transition from the old label to the new one" do
    allow(review).to receive(:call).with(pr: "12", label: rejected, dry_run: false).and_return(result)
    out, err, status = run("12", rejected)

    expect([status, out, err]).to match([0, include("12\t#{initial}\t#{rejected}\tgreen\tok"),
                                         include("#{initial} → #{rejected}")])
  end

  it "refuses a passing verdict while CI is red, and exits non-zero" do
    allow(review).to receive(:call).and_return(
      result(to: passing, ci: :red, refused: true, reason: "CI is red")
    )
    out, err, status = run("12", passing)

    expect([status, out, err.gsub(/\s+/, " ")]).to match(
      [1, include("refused"), include("CI is red").and(include("Only #{rejected} is accepted"))]
    )
  end

  it "prints the dry-run footer and passes the flag through" do
    allow(review).to receive(:call).with(pr: "12", label: rejected, dry_run: true).and_return(result(dry_run: true))
    _out, err, status = run("12", rejected, dry_run: true)

    expect([status, err]).to match([0, include("nothing was changed")])
  end

  it "rejects an unknown label with the valid list, before calling GitHub" do
    allow(review).to receive(:call)
    _out, err, status = run("12", "looks-fine")
    expect(review).not_to have_received(:call)

    flat = err.gsub(/[│┌┐└┘─]/, " ").gsub(/\s+/, " ")
    expect([status, flat]).to match([64, include("looks-fine", *OpenLanes::Plans::ReviewLabel.names)])
  end

  it "exits 69 when GitHub refuses" do
    allow(review).to receive(:call).and_raise(OpenLanes::Error, "gh: no such pull request")
    _out, err, status = run("99", initial)

    expect([status, err]).to match([69, include("no such pull request")])
  end

  it "lists the labels in its help from ReviewLabel::ALL" do
    expect(described_class.arguments.find { it.name == :label }.desc)
      .to include(*OpenLanes::Plans::ReviewLabel.names)
  end
end
