# frozen_string_literal: true

require "tty/command"

# The one place openlanes runs `alock`. A command double stands in for it.
RSpec.describe OpenLanes::Locking::Shell do
  subject(:shell) { described_class.new(command:) }

  let(:command) { instance_double(TTY::Command) }

  def result(status, out: "", err: "") = instance_double(TTY::Command::Result, exit_status: status, out:, err:)

  it "reads the active locks, and only those" do
    listed = [{ "agent_id" => "claude-1", "scope" => "lib/**", "tree" => "/r", "status" => "active", "intent" => "x" },
              { "agent_id" => "gone", "scope" => "a", "tree" => "/r", "status" => "interrupted" }]
    allow(command).to receive(:run).with("alock", "list", "--json", "--dir", "/r", timeout: 10).and_return(result(0, out: JSON.generate(listed)))

    expect(shell.list("/r")).to eq([OpenLanes::Locking::Lock.new(agent: "claude-1", scope: "lib/**", tree: "/r", intent: "x")])
  end

  it "says an unreadable listing is unreadable" do
    allow(command).to receive(:run).and_return(result(0, out: "not json"))

    expect { shell.list("/r") }.to raise_error(OpenLanes::Locking::Unreadable)
  end

  it "maps alock's exit codes to done, refused and failed, signing each call with its own holder" do
    allow(command).to receive(:run!).with("alock", "acquire", "a/**", "why", "--dir", "/p", env: { "AGENT_ID" => "me" }, timeout: 10).and_return(result(0))
    allow(command).to receive(:run!).with("alock", "release", "b/**", "--dir", "/p", env: { "AGENT_ID" => "you" }, timeout: 10)
                                    .and_return(result(1, out: "NOT LOCKED b/**\n"))
    allow(command).to receive(:run!).with("alock", "release", "c/**", "--dir", "/p", env: { "AGENT_ID" => "me" }, timeout: 10)
                                    .and_return(result(2, err: "alock: backend mismatch\n"))

    expect([shell.acquire("a/**", "why", dir: "/p", as: "me"),
            shell.release("b/**", dir: "/p", as: "you"),
            shell.release("c/**", dir: "/p", as: "me")])
      .to eq([OpenLanes::Locking::Outcome.new(status: :done),
              OpenLanes::Locking::Outcome.new(status: :refused, message: "NOT LOCKED b/**"),
              OpenLanes::Locking::Outcome.new(status: :failed, message: "alock: backend mismatch")])
  end

  it "says when there is no alock to run" do
    allow(command).to receive(:run!).and_raise(Errno::ENOENT, "alock")

    expect { shell.acquire("a/**", "why", dir: "/p", as: "me") }.to raise_error(OpenLanes::Locking::Unavailable, /not installed/)
  end

  it "fails one call, but keeps alock on, when a fork is refused or alock hangs" do
    allow(command).to receive(:run!).and_raise(Errno::EMFILE)
    allow(command).to receive(:run).and_raise(TTY::Command::TimeoutExceeded, "alock list timed out")

    expect([shell.acquire("a/**", "why", dir: "/p", as: "me").status, -> { shell.list("/r") }])
      .to match([:failed, raise_error(OpenLanes::Locking::Unreadable, /timed out/)])
  end

  it "never runs two alock commands at once, whatever the threads" do
    running = 0
    most = 0
    guard = Mutex.new
    allow(command).to receive(:run!) do
      guard.synchronize { most = [most, running += 1].max }
      sleep 0.01
      guard.synchronize { running -= 1 }
      result(0)
    end

    Array.new(8) { |i| Thread.new { shell.acquire("p#{i}/**", "why", dir: "/p", as: "a#{i}") } }.each(&:join)
    expect(most).to eq(1)
  end
end
