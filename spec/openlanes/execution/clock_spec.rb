# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Clock do
  subject(:clock) do
    described_class.new(seconds: 1200, control:, on_expire: -> { expired << :yes }, now: -> { now[:t] })
  end

  let(:control) { File.join(Dir.mktmpdir, "control") }
  let(:expired) { [] }
  let(:now) { { t: 0.0 } }

  # The subject is built here rather than lazily so that every clock is armed
  # at t=0; examples move now[:t] before their first reference to it.
  before do
    File.write(control, "")
    clock
  end

  def at(seconds)
    now[:t] = seconds.to_f
    clock.tick
    File.read(control).strip
  end

  it "says nothing while there is plenty of time" do
    expect(at(0)).to eq("")
    expect(clock.phase).to eq(:calm)
  end

  it "warns ten and five minutes out, then asks for a wrap-up at one" do
    aggregate_failures do
      expect(at(600)).to eq("WARN: 10 minutes left")
      expect(at(900)).to eq("WARN: 5 minutes left")
      expect(clock.phase).to eq(:warned)
      expect(at(1140)).to eq("WRAP_UP: 1 minute left, write to disk now")
      expect(clock.phase).to eq(:wrap_up)
    end
  end

  it "writes STOP at zero and expires sixty seconds later, once" do
    at(1200)
    expect(File.read(control).strip).to eq("STOP")
    expect(clock.phase).to eq(:stopped)
    at(1259)
    expect(expired).to be_empty
    at(1260)
    at(1300)
    aggregate_failures do
      expect(expired).to eq([:yes])
      expect(clock.phase).to eq(:expired)
    end
  end

  # A five minute agent must not be told "10 minutes left" at t=0.
  it "skips warnings whose moment passed before the clock started" do
    short = described_class.new(seconds: 300, control:, on_expire: -> {}, now: -> { now[:t] })
    now[:t] = 0.0
    short.tick
    expect(File.read(control).strip).to eq("")
    now[:t] = 240.0
    short.tick
    expect(File.read(control).strip).to eq("WRAP_UP: 1 minute left, write to disk now")
  end

  it "counts down, never below zero" do
    now[:t] = 1000.0
    expect(clock.remaining).to eq(200)
    now[:t] = 5000.0
    expect(clock.remaining).to eq(0)
  end

  # `x` after the warnings: the file is cleared so the agent's next poll
  # sees a reprieve, and every moment fires again against the new deadline.
  it "extends the deadline, clears the file, and re-arms the warnings" do
    at(1140)
    clock.extend!(600)
    aggregate_failures do
      expect(File.read(control).strip).to eq("")
      expect(clock.phase).to eq(:calm)
      expect(clock.remaining).to eq(660)
      expect(at(1200)).to eq("WARN: 10 minutes left")
      expect(at(1740)).to eq("WRAP_UP: 1 minute left, write to disk now")
    end
  end
end
