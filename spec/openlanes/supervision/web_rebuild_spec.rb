# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::WebRebuild do
  subject(:rebuild) { described_class.new(root:, host:, npm: -> { npm }, timeout: 300) }

  let(:root) { Dir.mktmpdir("web-rebuild") }
  let(:web) { File.join(root, "web") }
  let(:npm) { true }
  let(:spawner) { OpenLanes::Spawner::Fake.new(pids: [501]) }
  let(:clock) { OpenLanes::Clock::Fake.new }
  let(:status) { nil }
  let(:signals) { [] }
  let(:host) do
    OpenLanes::Supervision::Host.new(spawner:, waiter: ->(_) { status }, signaller: ->(*args) { signals << args }, clock:)
  end

  def exited(code) = instance_double(Process::Status, exitstatus: code, signaled?: false)

  before do
    FileUtils.mkdir_p(File.join(web, "dist"))
    File.write(File.join(web, "package.json"), "{}")
    File.write(File.join(web, "dist", "index.html"), "old page")
  end

  after { FileUtils.rm_rf(root) }

  it "runs npm run build in the gem's web/, in a group of its own, and never blocks" do
    rebuild.start
    aggregate_failures do
      expect(spawner.calls.map(&:argv)).to eq([%w[npm run build]])
      expect(spawner.calls.first.options).to include(chdir: web, pgroup: true)
      expect(rebuild.poll).to be_nil
    end
  end

  it "spawns once however often it is started" do
    rebuild.start.start
    expect(spawner.calls.size).to eq(1)
  end

  context "when the build succeeds" do
    let(:status) { exited(0) }

    it("says the page was rebuilt") { expect(rebuild.start.poll).to have_attributes(status: "ok", ok?: true) }
  end

  context "when the build fails" do
    let(:status) { exited(2) }

    it "says so and puts the old page back" do
      rebuild.start
      File.write(File.join(web, "dist", "index.html"), "half a page")
      outcome = rebuild.poll
      aggregate_failures do
        expect(outcome).to have_attributes(status: "failed", ok?: false)
        expect(outcome.message).to include("exit 2", "old page stays")
        expect(File.read(File.join(web, "dist", "index.html"))).to eq("old page")
      end
    end
  end

  context "when npm is not on PATH" do
    let(:npm) { false }

    it "starts nothing and says why" do
      outcome = rebuild.start.poll
      aggregate_failures do
        expect(outcome).to have_attributes(status: "no_npm")
        expect(spawner.calls).to be_empty
      end
    end
  end

  context "when the gem ships no page sources" do
    before { FileUtils.rm_f(File.join(web, "package.json")) }

    it "starts nothing and says why" do
      expect(rebuild.start.poll).to have_attributes(status: "no_sources", message: include("package.json is missing"))
    end
  end

  context "when the build runs past its time" do
    let(:reaped) { [] }
    let(:host) do
      OpenLanes::Supervision::Host.new(spawner:, waiter: ->(_) { reaped.shift }, signaller: ->(*args) { signals << args }, clock:)
    end

    before do
      rebuild.start
      File.write(File.join(web, "dist", "index.html"), "half a page")
      clock.advance(301)
    end

    it "kills its group once, and waits for it to end before settling (F2)" do
      aggregate_failures do
        expect([rebuild.poll, rebuild.poll]).to eq([nil, nil])
        expect(signals).to eq([["KILL", -501]])
      end
    end

    it "counts it a failure once the killed build is reaped, and puts the old page back" do
      rebuild.poll
      reaped << :gone
      aggregate_failures do
        expect(rebuild.poll).to have_attributes(status: "timeout", message: include("ran past 300 seconds"))
        expect(File.read(File.join(web, "dist", "index.html"))).to eq("old page")
      end
    end
  end

  # F1: nothing between Supervisor#tick and here rescues, so an error from
  # the file system has to come back as an outcome.
  describe "a web/ that cannot be used (F1)" do
    let(:dist) { File.join(web, "dist") }

    context "when the build cannot be spawned" do
      let(:spawner) do
        Class.new { def spawn(*, **) = raise(Errno::EACCES, "web") }.new
      end

      it "settles as failed, with the reason, and leaves the page alone" do
        outcome = rebuild.start.poll
        aggregate_failures do
          expect(outcome).to have_attributes(status: "failed", message: include("could not start", "Permission denied"))
          expect(File.read(File.join(dist, "index.html"))).to eq("old page")
        end
      end
    end

    context "when the old page cannot be copied aside" do
      before do
        File.write(File.join(dist, "secret.js"), "x")
        File.chmod(0o000, File.join(dist, "secret.js"))
      end

      after { File.chmod(0o644, File.join(dist, "secret.js")) }

      it "starts no build and settles as failed" do
        skip "root reads any file" if Process.uid.zero?
        outcome = rebuild.start.poll
        aggregate_failures do
          expect(outcome).to have_attributes(status: "failed", message: include("could not start"))
          expect(spawner.calls).to be_empty
        end
      end
    end

    context "when the old page cannot be put back after a failed build" do
      let(:status) { exited(1) }

      before do
        rebuild.start
        # An installed gem's web/ that this user may not write.
        FileUtils.rm_rf(dist)
        File.chmod(0o555, web)
      end

      after { File.chmod(0o755, web) }

      it "settles as failed and says the page could not be put back" do
        skip "root writes anywhere" if Process.uid.zero?
        expect(rebuild.poll).to have_attributes(status: "failed", message: include("exit 1", "could not be put back"))
      end
    end

    # An installed gem's web/, read-only to this user, after a build that
    # never got to write: restoring is not needed, and trying said the
    # page "could not be put back" while it sat there whole (issue 253).
    context "when web/ cannot be written but the build left the page alone" do
      let(:status) { exited(1) }
      let(:made) { [] }

      before do
        allow(Dir).to(receive(:mktmpdir).and_wrap_original { |original, *args| original.call(*args).tap { made << it } })
        rebuild.start
        FileUtils.chmod_R("a-w", web)
      end

      after { FileUtils.chmod_R("u+w", web) }

      it "says the old page stays, not that it was lost" do
        skip "root writes anywhere" if Process.uid.zero?
        outcome = rebuild.poll
        aggregate_failures do
          expect(outcome.message).to eq("the build failed (exit 1), so the old page stays")
          expect(File.read(File.join(dist, "index.html"))).to eq("old page")
        end
      end

      it "leaves neither the backup nor the log's directory in tmp" do
        rebuild.poll
        expect(made.size).to eq(2).and(satisfy { made.none? { File.exist?(it) } })
      end
    end

    context "when the build's log cannot be read" do
      let(:status) { exited(1) }

      before do
        rebuild.start
        FileUtils.mkdir_p(spawner.calls.first.options.fetch(:out))
      end

      it "settles as failed instead of raising" do
        expect(rebuild.poll).to have_attributes(status: "failed", message: include("could not be read"))
      end
    end
  end

  # Issue 253: an error that is not the file system's left the tick the
  # same way, and ended `openlanes start` with the engine in it.
  describe "an error that is no SystemCallError" do
    let(:dist) { File.join(web, "dist") }

    context "when the spawn raises one, its message in bytes" do
      let(:spawner) do
        Class.new { def spawn(*, **) = raise(ArgumentError, "bad \xE2\x9C\x97 \xFF option".b) }.new
      end

      it "settles as failed with a reason that is valid UTF-8" do
        outcome = rebuild.start.poll
        aggregate_failures do
          expect(outcome).to have_attributes(status: "failed", message: include("could not start (bad ✗ ", " option)"))
          expect(outcome.message).to be_valid_encoding
          expect(File.read(File.join(dist, "index.html"))).to eq("old page")
        end
      end
    end

    context "when asking after the build raises one" do
      let(:host) do
        OpenLanes::Supervision::Host.new(spawner:, waiter: ->(_) { raise "no such process table" }, signaller: ->(*args) { signals << args }, clock:)
      end

      before do
        rebuild.start
        File.write(File.join(dist, "index.html"), "half a page")
      end

      it "settles as failed, puts the old page back and removes the log" do
        outcome = rebuild.poll
        aggregate_failures do
          expect(outcome).to have_attributes(status: "failed", message: include("could not be read (no such process table)"))
          expect(File.read(File.join(dist, "index.html"))).to eq("old page")
          expect(File.exist?(File.dirname(spawner.calls.first.options.fetch(:out)))).to be(false)
        end
      end
    end
  end

  describe "a build the factory stops under (issue 253)" do
    let(:reaped) { [] }
    let(:host) do
      OpenLanes::Supervision::Host.new(spawner:, waiter: ->(_) { reaped.shift }, signaller: ->(*args) { signals << args }, clock:)
    end
    let(:page) { File.join(web, "dist", "index.html") }

    context "when it is running" do
      before do
        rebuild.start
        File.write(page, "half a page")
        reaped.push(nil, :gone)
      end

      it "kills its group, waits for it to be reaped, and puts the old page back" do
        outcome = rebuild.cancel
        aggregate_failures do
          expect(outcome).to have_attributes(status: "failed", message: include("stopped with the factory"))
          expect([signals, reaped]).to eq([[["KILL", -501]], []])
          expect(File.read(page)).to eq("old page")
          expect(File.exist?(File.dirname(spawner.calls.first.options.fetch(:out)))).to be(false)
        end
      end

      it("is the outcome from then on") { expect(rebuild.cancel).to equal(rebuild.poll) }
    end

    context "when it is never reaped" do
      before { rebuild.start }

      it "gives up waiting, so the factory can still end" do
        rebuild.cancel
        expect(clock.monotonic).to be_between(described_class::REAPED_WITHIN, described_class::REAPED_WITHIN + 1)
      end
    end

    context "when it cannot be signalled" do
      let(:host) do
        OpenLanes::Supervision::Host.new(spawner:, waiter: ->(_) {}, signaller: ->(*) { raise "no permission" }, clock:)
      end

      before do
        rebuild.start
        File.write(page, "half a page")
      end

      it "says so and still puts the old page back" do
        aggregate_failures do
          expect(rebuild.cancel.message).to include("could not be stopped (no permission)")
          expect(File.read(page)).to eq("old page")
        end
      end
    end

    it "signals nothing when the build had not started" do
      aggregate_failures do
        expect(rebuild.cancel).to have_attributes(status: "failed")
        expect(signals).to be_empty
      end
    end

    context "when it had already ended" do
      let(:reaped) { [exited(0)] }

      it "keeps the outcome it had" do
        done = rebuild.start.poll
        expect(rebuild.cancel).to equal(done).and have_attributes(status: "ok")
      end
    end
  end

  describe "the build's log (F101)" do
    let(:status) { exited(2) }
    let(:log) { spawner.calls.first.options.fetch(:out) }

    it "is written in a directory only this user can use, not under a predictable name in tmp" do
      rebuild.start
      aggregate_failures do
        expect(File.dirname(log)).not_to eq(Dir.tmpdir)
        expect(File.stat(File.dirname(log)).mode & 0o777).to eq(0o700)
      end
    end

    # Issue 253: cron, systemd and Docker run under LC_ALL=C, where the
    # `✓` vite prints made String#strip raise on the supervisor's tick.
    context "when the locale cannot read what the build printed" do
      around do |example|
        external = Encoding.default_external
        verbose = $VERBOSE
        $VERBOSE = nil
        Encoding.default_external = Encoding::US_ASCII
        example.run
      ensure
        Encoding.default_external = external
        $VERBOSE = verbose
      end

      it "reads it as UTF-8 and scrubs what is not" do
        rebuild.start
        File.binwrite(log, "\xE2\x9C\x93 12 modules transformed.\n\xFF\xE2\x9C\x97 Build failed in 80ms\n")
        message = rebuild.poll.message
        aggregate_failures do
          expect(message).to include("exit 2", "✓ 12 modules transformed.", "\uFFFD✗ Build failed in 80ms")
          expect([message.encoding, message.valid_encoding?]).to eq([Encoding::UTF_8, true])
        end
      end
    end

    it "is told in the reply and removed once the build has settled" do
      rebuild.start
      File.write(log, "error TS2304: Cannot find name 'x'\n")
      outcome = rebuild.poll
      aggregate_failures do
        expect(outcome.message).to include("Cannot find name 'x'")
        expect(File.exist?(File.dirname(log))).to be(false)
      end
    end
  end
end
