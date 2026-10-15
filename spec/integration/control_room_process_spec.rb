# frozen_string_literal: true

require_relative "../support/control_room_process"

# The harness's own guards, which need neither Redis nor web/dist.
RSpec.describe ControlRoomProcess do
  describe ".dedicated?" do
    it "allows only databases the harness may flush" do
      expect(%w[redis://localhost:6379/0 redis://localhost:6379/9 redis://localhost:6379
                redis://localhost:6379/10 redis://localhost:6379/15].map { described_class.dedicated?(it) })
        .to eq([false, false, false, true, true])
    end
  end

  describe ".new" do
    it "refuses a database below the test range, before it starts anything" do
      expect { described_class.new(root: Dir.tmpdir, redis_url: "redis://localhost:6379/0") }
        .to raise_error(ArgumentError, %r{refusing redis://localhost:6379/0})
    end
  end

  describe ".unmet" do
    it "names a missing lsof without dialing Redis" do
      Dir.mktmpdir("openlanes-no-lsof") do |bin|
        allow(described_class).to receive(:redis?)
        expect(described_class.unmet("redis://localhost:6379/10", path: bin)).to include("lsof is not on PATH")
        expect(described_class).not_to have_received(:redis?)
      end
    end

    it "finds lsof on the PATH it is given" do
      Dir.mktmpdir("openlanes-lsof") do |bin|
        File.write(File.join(bin, "lsof"), "#!/bin/sh\n")
        File.chmod(0o755, File.join(bin, "lsof"))
        expect(described_class.lsof?(bin)).to be(true)
      end
    end
  end
end
