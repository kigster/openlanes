# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Slack::EnvFile do
  subject(:file) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, ".env") }

  after { FileUtils.remove_entry(dir) }

  it "reads what a shell would: export, quotes, comments and all" do
    File.write(path, "# a comment\nexport ONE=1\nTWO=\"two words\"\nTHREE='3'\n\nEMPTY=\n")

    expect([file["ONE"], file["TWO"], file["THREE"], file["EMPTY"], file["FOUR"]]).to eq(["1", "two words", "3", nil, nil])
  end

  it "reads a value up to the comment after it, as a shell does, and a # inside quotes or with no space before it as the value" do
    File.write(path, "A=1 # one\nB='x # y' # z\nC=#questions\n")

    expect([file["A"], file["B"], file["C"]]).to eq(["1", "x # y", "#questions"])
  end

  it "keeps a line's comment when it changes the value" do
    File.write(path, "CHANNEL=old # where questions go\n")
    file.write("CHANNEL" => "C1")

    expect(File.read(path)).to eq("CHANNEL=C1 # where questions go\n")
  end

  it "is empty when there is no file" do
    expect(file["ONE"]).to be_nil
  end

  it "changes the lines it is given, export kept, adds the ones that are missing, and keeps every other" do
    File.write(path, "# keep me\nSLACK_BOT_TOKEN=xoxb\nexport CHANNEL=old")
    file.write("CHANNEL" => "C1", "OPERATORS" => "U1,U2")

    expect(File.read(path)).to eq("# keep me\nSLACK_BOT_TOKEN=xoxb\nexport CHANNEL=C1\nOPERATORS=U1,U2\n")
  end

  it "reads a value with a single quote back as it wrote it" do
    file.write("NOTE" => "it's")

    expect([File.read(path), file["NOTE"], file.changes("NOTE" => "it's")]).to eq(["NOTE='it'\\''s'\n", "it's", {}])
  end

  it "quotes a value the shell would take as a comment" do
    file.write("CHANNEL" => "#questions")

    expect(File.read(path)).to eq("CHANNEL='#questions'\n")
    expect(file["CHANNEL"]).to eq("#questions")
  end

  it "is for its owner's eyes only" do
    File.write(path, "A=1\n")
    File.chmod(0o644, path)
    file.write("A" => "2")

    expect(File.stat(path).mode & 0o777).to eq(0o600)
  end

  it "knows which values a write would change" do
    File.write(path, "A=1\nB=2\n")

    expect(file.changes("A" => "1", "B" => "3", "C" => "4")).to eq("B" => "3", "C" => "4")
  end

  context "when it is a link to a file not made yet" do
    let(:shared) { File.join(dir, "shared.env") }

    before do
      File.symlink("shared.env", path)
      file.write("ONE" => "1")
    end

    it "makes the file the link points at, and leaves the link" do
      expect([File.symlink?(path), File.read(shared)]).to eq([true, "ONE=1\n"])
    end
  end

  context "when it is a link" do
    let(:shared) { File.join(dir, "shared.env") }

    before do
      File.write(shared, "ONE=1\n")
      File.symlink(shared, path)
      file.write("TWO" => "2")
    end

    it "writes through it, as worktrees that share one .env need" do
      expect([File.symlink?(path), File.read(shared)]).to eq([true, "ONE=1\nTWO=2\n"])
    end
  end
end
