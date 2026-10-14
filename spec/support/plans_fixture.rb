# frozen_string_literal: true

# Builds real `.plans` trees on disk for examples to read.
#
# Everything in this tool reads from the filesystem — folder names carry the
# state, and the files inside them are what the invariants test. Faking that
# with doubles would test the doubles, so the fixtures are real directories in
# a temp dir that the `:tree` hook throws away afterwards.
#
# @example
#   let!(:tree) do
#     plans do |t|
#       t.plan "001.00", :new,  "initial-spec", files: {"spec.md" => "# Spec"}
#       t.plan "002.00", :approved, "dev-foundation", prs: [t.merged(2, "Ship it")]
#     end
#   end
module PlansFixture
  # A single plan folder, described declaratively.
  class Builder
    # @param root [String] the `.plans` directory
    def initialize(root)
      @root = root
    end

    # @return [String] the `.plans` directory
    attr_reader :root

    # Create one plan folder.
    #
    # @param ordinal [String] e.g. "002.00"
    # @param status [Symbol, String] a status key, alias or emoji
    # @param slug [String] the kebab tail
    # @param files [Hash{String => String}] extra files to write
    # @param prs [Array<Hash>] rows for `pull-requests.md`
    # @param under [String, nil] an inactive subfolder, e.g. "archive"
    # @param archived_on [Date, nil] the date its name carries
    # @return [String] absolute path to the folder
    def plan(ordinal, status, slug, files: {}, prs: nil, under: nil, archived_on: nil)
      resolved = OpenLanes::Plans.status(status) or raise ArgumentError, "unknown status: #{status}"
      path = File.join(root, *under, OpenLanes::Plans.plan_dirname(ordinal, resolved, slug, archived_on:))
      FileUtils.mkdir_p(path)

      files.each { |name, body| File.write(File.join(path, name), body) }
      File.write(File.join(path, "pull-requests.md"), pull_requests_table(prs)) if prs

      path
    end

    # A folder written exactly as given, so an example can build a name this
    # tool would never produce itself: an unpadded number, a hand-typed
    # separator, a number-and-emoji pair that disagree.
    #
    # @param dirname [String] verbatim
    # @param files [Hash{String => String}]
    # @return [String] absolute path to the folder
    def raw(dirname, files: {})
      path = File.join(root, dirname)
      FileUtils.mkdir_p(path)
      files.each { |name, body| File.write(File.join(path, name), body) }
      path
    end

    # A folder whose name carries no number at all — should be skipped.
    #
    # @param name [String]
    # @return [String]
    def stray(name)
      path = File.join(root, name)
      FileUtils.mkdir_p(path)
      path
    end

    # @param number [Integer]
    # @param title [String]
    # @return [Hash] a merged pull request row
    def merged(number, title) = pr(number, title, "Merged 🟣")

    # @param number [Integer]
    # @param title [String]
    # @return [Hash] an open pull request row
    def open(number, title) = pr(number, title, "Open 🟡")

    # @param number [Integer]
    # @param title [String]
    # @param state [String]
    # @return [Hash]
    def pr(number, title, state)
      { number:, title:, state:, url: "https://github.com/example/repo/pull/#{number}" }
    end

    private

    # The exact shape `PullRequests` parses, so the fixture exercises the real
    # parser rather than a convenient approximation of it.
    #
    # @param rows [Array<Hash>]
    # @return [String]
    def pull_requests_table(rows)
      body = rows.map { |r|
        "| #{r[:number]} | [#{OpenLanes::Plans::PullRequests.escape(r[:title])}](#{r[:url]}) | #{r[:state]} |"
      }
      <<~MARKDOWN
        # Pull Requests

        | Pull Request Number | Pull Request Name | Status |
        | ------------------: | :---------------- | -----: |
        #{body.join("\n")}
      MARKDOWN
    end
  end

  # @return [String] the temp `.plans` directory for this example
  def plans_root = @plans_root

  # Drop ANSI escape sequences so an assertion tests content, not presentation.
  #
  # @param text [String]
  # @return [String]
  def strip_ansi(text) = text.gsub(/\e\[[0-9;]*[a-zA-Z]/, "")

  # Populate the example's `.plans` tree.
  #
  # @yieldparam builder [PlansFixture::Builder]
  # @return [String] the `.plans` directory
  def plans
    yield Builder.new(plans_root) if block_given?
    plans_root
  end

  # A minimal spec body that satisfies the description extractor.
  #
  # @param title [String]
  # @param goal [String]
  # @return [String]
  def spec_body(title: "A Feature", goal: "Make the thing work, end to end.")
    <<~MARKDOWN
      # #{title}

      ## Goal

      #{goal}
    MARKDOWN
  end
end
