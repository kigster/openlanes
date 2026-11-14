# frozen_string_literal: true

RSpec.describe "OpenLanes::Project.config_path" do
  around do |example|
    Dir.mktmpdir("openlanes-config-path") do |dir|
      root_dir.replace(File.realpath(dir))
      OpenLanes::Project.reset_notices!
      example.run
    ensure
      OpenLanes::Project.reset_notices!
    end
  end

  let(:root_dir) { +"" }
  let(:root) { root_dir }
  let(:new_file) { File.join(root, ".openlanes", "config.yml") }
  let(:old_file) { File.join(root, OpenLanes::Project::LEGACY_FILE) }

  def write(path, text = "jobs: 2\n")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  it "reads the new file quietly" do
    write(new_file)
    expect { expect(OpenLanes::Project.config_path(root)).to eq(new_file) }.not_to output.to_stderr
  end

  it "reads the legacy file and names the new path and the move command once per process" do
    write(old_file)
    expect { 2.times { expect(OpenLanes::Project.config_path(root)).to eq(old_file) } }
      .to output(%r{\A[^\n]*\.openlanes/config\.yml[^\n]*openlanes config move[^\n]*\n\z}).to_stderr
  end

  it "refuses when both files are present, naming both" do
    write(new_file)
    write(old_file)
    expect { OpenLanes::Project.config_path(root) }
      .to raise_error(OpenLanes::Error, /#{Regexp.escape(new_file)}.*#{Regexp.escape(old_file)}/)
  end

  it "points at the new path when neither exists" do
    expect(OpenLanes::Project.config_path(root)).to eq(new_file)
  end

  it "loads settings from either file" do
    write(old_file, "jobs: 3\n")
    expect { expect(OpenLanes::Config.load(root).jobs).to eq(3) }.to output.to_stderr
  end

  it "marks a root holding only the new file" do
    write(new_file)
    nested = File.join(root, "a", "b")
    FileUtils.mkdir_p(nested)
    expect(OpenLanes::Project.root(from: nested, home: "/nonexistent")).to eq(root)
  end

  it "rereads the config after the file moves across" do
    write(old_file, "jobs: 3\n")
    Dir.chdir(root) do
      allow(OpenLanes::Config).to receive(:current).and_call_original
      OpenLanes::Config.instance_variable_set(:@current, nil)
      expect { expect(OpenLanes::Config.current.jobs).to eq(3) }.to output.to_stderr
      write(new_file, "jobs: 5\n")
      File.delete(old_file)
      expect(OpenLanes::Config.current.jobs).to eq(5)
    ensure
      OpenLanes::Config.instance_variable_set(:@current, nil)
    end
  end

  it "creates the folder when writing a flag into a new project" do
    path = OpenLanes::Config.write_flag(root, "frontend", true)
    expect(path).to eq(new_file)
    expect(File.read(new_file)).to eq("frontend: true\n")
  end
end
