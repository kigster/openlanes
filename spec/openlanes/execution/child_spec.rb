# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Child do
  it "streams the child's stdout and reports its exit" do
    child = described_class.spawn(["ruby", "-e", "print 'a'; $stdout.flush; print 'b'"])
    chunks = []
    child.each_chunk { |text| chunks << text }
    status = child.wait
    aggregate_failures do
      expect(chunks.join).to eq("ab")
      expect(status).to be_success
      expect(child.pid).to be_a(Integer)
    end
  end

  it "kills a process that will not end on its own" do
    child = described_class.spawn(["ruby", "-e", "sleep 30"])
    expect(child).to be_alive
    child.kill
    status = child.wait
    aggregate_failures do
      expect(status).not_to be_success
      expect(child).not_to be_alive
    end
  end

  it "runs in the directory asked for" do
    Dir.mktmpdir do |dir|
      child = described_class.spawn(["ruby", "-e", "print Dir.pwd"], chdir: dir)
      out = +""
      child.each_chunk { |text| out << text }
      child.wait
      expect(File.realpath(out)).to eq(File.realpath(dir))
    end
  end

  # `exe/openlanes` pins BUNDLE_GEMFILE to its own Gemfile and `bundler/setup`
  # puts `-rbundler/setup` in RUBYOPT. An agent that inherits either runs its
  # `bundle exec`, `standardrb` and `alock` against the harness's checkout, not
  # the worktree it was handed, and fails with "not currently included in the
  # bundle" for anything that worktree's Gemfile adds.
  it "does not hand the child the Bundler environment the harness runs under" do
    saved = ENV.to_h.slice("BUNDLE_GEMFILE", "RUBYOPT")
    ENV["BUNDLE_GEMFILE"] = "/elsewhere/Gemfile"
    ENV["RUBYOPT"] = "-rbundler/setup"
    child = described_class.spawn(["ruby", "-e", 'puts ENV.fetch("BUNDLE_GEMFILE", "unset"), ENV.fetch("RUBYOPT", "unset")'])
    out = +""
    child.each_chunk { |text| out << text }
    child.wait
    gemfile, rubyopt = out.lines(chomp: true)
    aggregate_failures do
      expect(gemfile).to eq("unset")
      expect(rubyopt).not_to include("bundler/setup")
    end
  ensure
    %w[BUNDLE_GEMFILE RUBYOPT].each { |k| saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end
end
