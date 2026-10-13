# frozen_string_literal: true

require "tmpdir"

# The parser's tolerant half. `pull_requests_render_spec.rb` proves the round
# trip through the table this tool writes; these examples are about the files
# it did not write — hand-edited tables, prose with bare links, GitLab URLs —
# because a folder that plainly has pull requests must never report none.
RSpec.describe OpenLanes::Plans::PullRequests do
  def parse(body:, filename: described_class::FILENAME)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, filename), body)
      described_class.new(dir:).all
    end
  end

  describe "a folder with no pull request file at all" do
    it "reports none rather than raising" do
      Dir.mktmpdir { |dir| expect(described_class.new(dir:).all).to eq([]) }
    end
  end

  describe "a table whose header never says 'pull request'" do
    # The header-based pick fails, so the fallback finds the table by its
    # /pull/ links instead — a hand-written roll-up is still a roll-up.
    let(:body) do
      <<~MARKDOWN
        # Work shipped

        | Id | Change | Where |
        | -- | ------ | ----- |
        | 7 | Add the ledger | [link](https://github.com/o/r/pull/7) |
      MARKDOWN
    end

    it "still finds the table by its links" do
      expect(parse(body:).map(&:number)).to eq(["7"])
    end

    it "takes the title from the title-ish column even though it is not a link" do
      expect(parse(body:).first.title).to eq("Add the ledger")
    end
  end

  describe "a file with prose and bare links but no table" do
    let(:body) do
      <<~MARKDOWN
        The work landed in https://github.com/o/r/pull/12 and the follow-up
        in https://gitlab.com/o/r/-/merge_requests/34. See also
        https://github.com/o/r/pull/12 again.
      MARKDOWN
    end

    it "scrapes each link once, GitLab merge requests included" do
      expect(parse(body:).map(&:number)).to eq(%w[12 34])
    end

    it "keeps the URL and admits it does not know the state" do
      expect(parse(body:).first).to have_attributes(
        url: "https://github.com/o/r/pull/12", state: "Unknown", title: "Pull request #12"
      )
    end
  end

  describe "a table whose rows carry no recognisable pull request" do
    # An empty or link-less table must fall through to the scrape, not report
    # an empty roll-up while a bare link sits in the prose below it.
    let(:body) do
      <<~MARKDOWN
        | Pull Request Number | Pull Request Name | Status |
        | ------------------: | :---------------- | -----: |

        Opened later: https://github.com/o/r/pull/9
      MARKDOWN
    end

    it "falls back to scraping the rest of the file" do
      expect(parse(body:).map(&:number)).to eq(["9"])
    end
  end

  describe "markdown wrapped around a hand-written title" do
    def row(title_cell, state: "Merged 🟣")
      <<~MARKDOWN
        | Pull Request Number | Pull Request Name | Status |
        | ------------------: | :---------------- | -----: |
        | 5 | #{title_cell} | #{state} |
        | 6 | [linked](https://github.com/o/r/pull/6) | Merged 🟣 |
      MARKDOWN
    end

    it "strips emphasis and backticks without eating the words" do
      expect(parse(body: row("**Ship `it` now**")).first.title).to eq("Ship it now")
    end

    # An underscore between letters is an identifier, not emphasis. Removing
    # every underscore turned "Split verified into signed_off" into
    # "signedoff" on the way to Linear.
    it "keeps an identifier's inner underscores while trimming emphasis ones" do
      expect(parse(body: row("_Split verified into signed_off_")).first.title).to eq("Split verified into signed_off")
    end
  end

  describe "a state written in words the vocabulary does not know" do
    def state_of(cell)
      body = <<~MARKDOWN
        | Pull Request Number | Pull Request Name | Status |
        | ------------------: | :---------------- | -----: |
        | 5 | [x](https://github.com/o/r/pull/5) | #{cell} |
      MARKDOWN
      parse(body:).first.state
    end

    it "keeps the words as written rather than guessing a canonical state" do
      expect(state_of("**In Review**")).to eq("In Review")
    end

    it "says Unknown when the cell is empty, so nothing downstream parses blank" do
      expect(state_of("")).to eq("Unknown")
    end
  end
end
