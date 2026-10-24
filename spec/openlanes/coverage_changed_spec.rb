# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

# bin/coverage-changed gates the files a branch touched, not the library.
# Each example runs the real script over a fixture resultset and file list.
RSpec.describe "bin/coverage-changed" do
  let(:script) { File.expand_path("../../bin/coverage-changed", __dir__) }
  let(:dir) { Dir.mktmpdir }
  let(:resultset) { File.join(dir, ".resultset.json") }

  # full.rb 100%, half.rb 50%, legacy.rb in SimpleCov's older array-only shape.
  let(:coverage) do
    {
      "/checkout/lib/full.rb"   => { "lines" => [nil, 1, 1, 3, nil] },
      "/checkout/lib/half.rb"   => { "lines" => [1, 0, nil, 0, 1] },
      "/checkout/lib/legacy.rb" => [1, 1, nil]
    }
  end

  before { File.write(resultset, JSON.generate("RSpec" => { "coverage" => coverage, "timestamp" => 0 })) }

  after { FileUtils.rm_rf(dir) }

  def run(*files)
    Open3.capture3(RbConfig.ruby, script, "--resultset", resultset, "--files", files.join(","), chdir: dir)
  end

  it "exits 1 and names a changed file below 95%" do
    out, err, status = run("lib/full.rb", "lib/half.rb")

    expect(status.exitstatus).to eq(1)
    expect(out).to include("100.00%  lib/full.rb").and include("50.00%  lib/half.rb")
    expect(err).to include("below 95%: lib/half.rb")
    expect(err).not_to include("lib/full.rb")
  end

  it "exits 0 when every changed file is at or above 95%, in either resultset shape" do
    out, _err, status = run("lib/full.rb", "lib/legacy.rb")

    expect(status).to be_success
    expect(out).to include("2 file(s), all at or above 95%")
  end

  it "exits 0 when nothing under lib/ changed" do
    out, _err, status = run("README.md", "spec/x_spec.rb")

    expect(status).to be_success
    expect(out).to include("no changed files under lib/")
  end

  it "skips version.rb, which the gemspec loads before SimpleCov starts" do
    out, _err, status = run("lib/openlanes/version.rb")

    expect(status).to be_success
    expect(out).to include("no changed files under lib/")
  end

  it "counts a changed file SimpleCov never loaded as 0%" do
    out, err, status = run("lib/untested.rb")

    expect(status.exitstatus).to eq(1)
    expect(out).to include("0.00%  lib/untested.rb")
    expect(err).to include("lib/untested.rb")
  end
end
