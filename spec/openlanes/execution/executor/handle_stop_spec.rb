# frozen_string_literal: true

# Stop All can reach a job the moment it is started, before its executor has
# registered the control file. The request is kept on the handle and written
# as soon as the file exists, so that agent is not left running.
RSpec.describe OpenLanes::Execution::Executor::Handle do
  subject(:handle) { described_class.new }

  let(:dir) { Dir.mktmpdir }
  let(:control) { OpenLanes::Execution::Control.register(dir, "001.00-backend-coder") }

  after do
    OpenLanes::Execution::Control.reset!
    FileUtils.rm_rf(dir)
  end

  context "when the stop comes before the control file" do
    before do
      handle.request_stop!
      handle.control = control
    end

    it "writes STOP the moment the file is registered" do
      expect(File.read(control).strip).to eq("STOP")
    end
  end

  context "when the control file is already there" do
    before do
      handle.control = control
      handle.request_stop!
    end

    it "writes STOP at once" do
      expect(File.read(control).strip).to eq("STOP")
    end
  end

  context "without a stop" do
    before { handle.control = control }

    it "leaves the control file as registered" do
      expect(File.read(control).strip).to eq("")
    end
  end
end
