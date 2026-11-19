# frozen_string_literal: true

# Whether a handle has been asked to stop, read from its control file when
# nothing else says so.
RSpec.describe OpenLanes::Execution::Executor::Handle::Stopping do
  subject(:handle) { OpenLanes::Execution::Executor::Handle.new }

  let(:dir) { Dir.mktmpdir }
  let(:control) { OpenLanes::Execution::Control.register(dir, "001.00-backend-coder") }

  after do
    OpenLanes::Execution::Control.reset!
    FileUtils.rm_rf(dir)
  end

  it "is not stopping with no control file" do
    expect(handle.stopping?).to be(false)
  end

  it "reads STOP out of its control file" do
    handle.control = control
    OpenLanes::Execution::Control.write(control, OpenLanes::Execution::Control::STOP)
    expect(handle.stopping?).to be(true)
  end

  it "is not stopping once its control file is gone" do
    handle.control = control
    File.delete(control)
    expect(handle.stopping?).to be(false)
  end
end
