# frozen_string_literal: true

require "fileutils"
require "parallel"

module OpenLanes
  module Lifecycle
    # Gives a plan folder to every pull request that has no plan to point at.
    #
    # `resync prs` can resolve most pull requests from their branch or their
    # diff. What it cannot resolve it used to flag for a human — "diff touches
    # 021.00, 022.00, 024.00 and none is obviously primary" — and stop. That is
    # honest but not useful: the work exists, it is unspecified, and leaving it
    # unnumbered means it never appears in the index at all.
    #
    # So an orphan is adopted instead. It gets a retroactive plan of its own,
    # numbered in the gap after the furthest plan it can see, holding the pull
    # request that produced it.
    #
    # == Why the numbering is allocated serially
    #
    # The obvious parallel design — every worker reads the highest number and
    # adds `.01` — is deterministic but not unique, and the collision is the
    # common case rather than the rare one. Fifteen open pull requests branched
    # off the same main all see the same highest number and all compute the same
    # slot. Determinism is not the property that matters here; distinctness is.
    #
    # So the pipeline is **gather in parallel, allocate serially, apply in
    # parallel**. The allocation is pure arithmetic over an array that is
    # already in memory, so the serial section costs microseconds; the two
    # expensive phases — reading each branch and writing each folder — keep the
    # whole fan-out. And because the slots are handed out before any worker
    # starts, no worker can want a number another worker holds: no locks, no
    # retries, and the same input produces the same numbers every run.
    class Adoption
      # One pull request and the plan it is being given.
      #
      # @!attribute [r] pull
      #   @return [Hash] as returned by {GitHub#pulls}
      # @!attribute [r] ordinal
      #   @return [OpenLanes::Plans::Ordinal] the slot it was allocated
      # @!attribute [r] major
      #   @return [Integer] the furthest plan its branch or diff could see
      # @!attribute [r] path
      #   @return [String, nil] the folder, once created
      Adoptee = Data.define(:pull, :ordinal, :major, :path) do
        # @return [String] the folder name this pull request earns
        def dirname = OpenLanes::Plans.plan_dirname(ordinal, Plans::STATUS_BY_KEY.fetch(:retroactive), slug)

        # The PR title, stripped of any prefix, as the folder's tail.
        #
        # @return [String]
        def slug = Creator.slugify(pull[:title].to_s.sub(/\A\[[^\]]+\](?:\([A-Z]\))?\s*/, ""))

        # @return [String] a single auditable line
        def to_s = "##{pull[:number]} → #{dirname}"
      end

      # @param tree [OpenLanes::Plans::Tree]
      # @param github [OpenLanes::Vcs::GitHub]
      # @param root [String] repository root, for reading branches
      # @param jobs [Integer] workers for the two parallel phases
      def initialize(tree:, github: Vcs::GitHub.new, root: nil, jobs: UI.default_jobs)
        @tree = tree
        @github = github
        @root = root || File.dirname(tree.dir)
        @jobs = jobs
      end

      # @return [OpenLanes::Plans::Tree]
      attr_reader :tree

      # @return [OpenLanes::Vcs::GitHub]
      attr_reader :github

      # @return [String]
      attr_reader :root

      # @return [Integer]
      attr_reader :jobs

      # Work out what each orphan would be given, without creating anything.
      #
      # @param pulls [Array<Hash>] the orphans, from {Resync::Prs}
      # @return [Array<OpenLanes::Lifecycle::Adoption::Adoptee>] in pull request order
      # @raise [Allocator::Refused] in a linked worktree, where no plan is
      #   minted, so a preview there says so rather than promising folders
      def plan(pulls)
        allocator.refuse!
        @taken = nil
        allocate(gather(pulls))
      end

      # Adopt every orphan: create its folder and record its pull request.
      #
      # The slots are read and the folders made under the allocation lock, or
      # a `create` running beside this one can take a slot this just handed out.
      #
      # @param pulls [Array<Hash>]
      # @return [Array<OpenLanes::Lifecycle::Adoption::Adoptee>] with `path` filled in
      # @raise [Allocator::Refused] in a linked worktree
      def call(pulls)
        allocator.hold { adopt_all(pulls) }
      end

      # @return [OpenLanes::Lifecycle::Allocator]
      def allocator = @allocator ||= Allocator.new(dir: tree.dir)

      private

      # @param pulls [Array<Hash>]
      # @return [Array<OpenLanes::Lifecycle::Adoption::Adoptee>]
      def adopt_all(pulls)
        adoptees = plan(pulls)
        return adoptees if adoptees.empty?

        created = Parallel.map(adoptees, in_threads: jobs) { |adoptee| adopt(adoptee) }
        tree.reload
        created
      end

      # Phase one, in parallel: ask each pull request's branch how far the
      # sequence had got when the work started. Branches are not all rebased
      # onto the same main, so this is per-branch rather than tree-wide, and it
      # is a network-free `ls-tree` per pull request.
      #
      # @param pulls [Array<Hash>]
      # @return [Array<Array(Hash, Integer)>] each pull with its major
      def gather(pulls)
        ordered = pulls.sort_by { |pull| pull[:number].to_i }

        Parallel.map(ordered, in_threads: jobs) { |pull| [pull, major_for(pull)] }
      end

      # The furthest whole plan this pull request can see: on its own branch
      # first, then whatever it touched, then the tree we are standing in. A
      # pull request whose branch is long gone still has a diff.
      #
      # @param pull [Hash]
      # @return [Integer]
      def major_for(pull)
        candidates = OpenLanes.plans_on_ref(root, pull[:branch].to_s)
        candidates = touched(pull) if candidates.empty?
        candidates = tree.taken if candidates.empty?

        candidates.map(&:major).max.to_i
      end

      # @param pull [Hash]
      # @return [Array<OpenLanes::Plans::Ordinal>]
      def touched(pull)
        Array(pull[:files]).filter_map { |path|
          folder = Plans::Tree.plan_folder(path)
          folder && Plans::Ordinal.from_dirname(folder)
        }.uniq
      end

      # Phase two, serial and deliberately so. Minors are handed out per major,
      # continuing past every slot the tree already holds, in ascending pull
      # request order — so the numbers follow the order the work was opened in,
      # and two pull requests cannot be given the same one.
      #
      # @param gathered [Array<Array(Hash, Integer)>]
      # @return [Array<OpenLanes::Lifecycle::Adoption::Adoptee>]
      def allocate(gathered)
        taken = Hash.new { |h, major| h[major] = minors_taken(major) }

        gathered.filter_map do |pull, major|
          minor = ((taken[major].max || 0) + 1)
          next if minor > Plans::Ordinal::MAX_MINOR

          taken[major] << minor
          Adoptee.new(pull:, major:, ordinal: Plans::Ordinal.new(major:, minor:), path: nil)
        end
      end

      # @param major [Integer]
      # @return [Array<Integer>] minors already used under this major, on
      #   this tree or on any branch: a slot taken anywhere is taken
      def minors_taken(major)
        (@taken ||= allocator.taken).select { |o| o.major == major }.map(&:minor)
      end

      # Phase three, in parallel: each worker owns a number nobody else can
      # want, so it can create its folder without coordinating with anyone.
      #
      # @param adoptee [OpenLanes::Lifecycle::Adoption::Adoptee]
      # @return [OpenLanes::Lifecycle::Adoption::Adoptee]
      def adopt(adoptee)
        path = File.join(tree.dir, adoptee.dirname)
        return adoptee if File.exist?(path)

        FileUtils.mkdir_p(path)
        File.write(File.join(path, Plans::PullRequests::FILENAME),
          Plans::PullRequests.render([pull_request_for(adoptee)]))

        adoptee.with(path:)
      end

      # The body is what a specification would be written from, so it is worth
      # a second request. A failure here costs the description, not the folder.
      #
      # @param adoptee [OpenLanes::Lifecycle::Adoption::Adoptee]
      # @return [Hash]
      def pull_request_for(adoptee)
        pull = adoptee.pull
        github.pull_request(pull[:number].to_s)
      rescue OpenLanes::Error
        { number: pull[:number], title: pull[:title], url: pull[:url],
         state: pull[:state] || "Unknown", body: "" }
      end
    end
  end
end
