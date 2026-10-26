# frozen_string_literal: true

# `openlanes agents list` is a read-only report. The one property worth
# pinning is the stream split: the roster is the deliverable, so it goes to
# STDOUT whole and STDERR stays empty — a roster half on each stream is a
# roster no pipe can use.
RSpec.describe OpenLanes::CLI::Agents::List do
  subject(:command) { described_class.new }

  it "writes the whole roster to STDOUT and nothing to STDERR" do
    out = CapturedStream.new
    err = CapturedStream.new

    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call
    ensure
      $stdout, $stderr = original_out, original_err
    end

    expect(strip_ansi(out.string)).to include("unblocker", "spec-writer")
    expect(err.string).to eq("")
  end
end
