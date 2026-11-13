# frozen_string_literal: true

module OpenLanes
  # Setting the gem's version, and keeping Gemfile.lock in step with it.
  #
  # main once carried `openlanes (4.0.0)` in Gemfile.lock under a 4.0.1 gem,
  # because the version was bumped by hand and nobody relocked. {Bump} makes
  # the two edits one step, and fails when the lock still disagrees.
  #
  # Loaded two ways: by Zeitwerk inside the library, and by `bin/bump-version`
  # with plain `require_relative`, so a bump needs none of the library's
  # dependencies. Nothing here may reach for a constant outside this namespace
  # at load time.
  module Release
    # A bump that could not be carried out as asked. The message is the one
    # the user reads.
    class Failed < StandardError; end

    module_function

    # @param root [String] the checkout holding version.rb, Gemfile and the lock
    # @param version [String] the new MAJOR.MINOR.PATCH
    # @param dry_run [Boolean] report the change and write nothing
    # @param relock [#call] runs `bundle lock` in root, answers success
    # @return [Array<String>] the lines to print
    # @raise [OpenLanes::Release::Failed]
    def bump(root:, version:, dry_run: false, relock: Relock.new(root))
      Bump.new(root:, relock:).call(version, dry_run:)
    end
  end
end
