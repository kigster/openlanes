# frozen_string_literal: true

module OpenLanes
  # A project's declared test coverage (decision M15), the `coverage:`
  # section of its `.openlanes.yml`: which command runs the suite, where the
  # line figure comes from, and the lowest one that may merge.
  #
  # Pure, like {Plans}: it reads files and does arithmetic, and starts no
  # process. Running either command belongs to {Engine::CoverageGate}, which
  # is the only caller that turns a figure into a verdict.
  module Coverage
    # A `coverage:` section, or the `.openlanes.yml` around it, that cannot be
    # honoured as written.
    class Invalid < OpenLanes::Error; end

    # A report present on disk that a parser cannot read.
    class Malformed < OpenLanes::Error; end

    module_function

    # @param root [String] the checkout whose declaration is read
    # @return [OpenLanes::Coverage::Config, nil] nil when its `.openlanes.yml`
    #   has no `coverage:` section
    # @raise [OpenLanes::Coverage::Invalid]
    def config(root) = Config.load(root)

    # @param format [Symbol] one of {Config::FORMATS}
    # @param path [String] the report
    # @return [OpenLanes::Coverage::Report] never raises; a report that cannot
    #   be read is a {Report} at 0% with its problem named
    def read(format:, path:) = Report.read(format:, path:)
  end
end
