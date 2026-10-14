# frozen_string_literal: true

module OpenLanes
  module Lifecycle
    # Reconciling what is recorded with what is true.
    #
    # Both resyncs are dry-run by default and both refuse to act where they are
    # not certain, because both write to things other people join on: folder
    # names, and pull request titles.
    module Resync
      # `resync dirs` — makes every folder's name say what the folder is.
      #
      # Two things can be wrong with a name, and both are repaired here:
      #
      # - **The emoji is wrong** — the contents justify a different state. A
      #   folder whose status already holds is left alone, which is what stops
      #   ⭕️ Blocked and 🅱️ Product Blocked — deliberately identical invariants,
      #   distinguished only by the name — from collapsing into one.
      # - **The spelling is not canonical** — a folder written `018-⚪️--foo`
      #   before the `NNN.MM` padding rule or the ` → ` separator, or
      #   `18.1-⚪️--foo` by hand. Unpadded numbers read fine and sort wrong —
      #   `018.09` < `018.1` < `018.10` puts a single mixed-width folder in the
      #   middle of the range. Both are renamed, to `018.00-⚪️ → foo` and
      #   `018.01-⚪️ → foo`.
      #
      # - **The folder is in the wrong place** — a plan in an inactive state
      #   (✅ 😎 💤 ❌) belongs in the subfolder {Plans::Tree::INACTIVE_DIRS}
      #   names, under a name dated by {Vcs::RenameDate}; a plan in any other
      #   state belongs at the top level, undated. Moving a plan back out is
      #   how one is revived: the state machine renames it in place, and the
      #   next resync brings it home (decision N3).
      #
      # The repairs are applied as **up to three renames per folder**: first
      # the spelling, under the status the folder already claims — which is
      # how an older folder migrates to the `NNN.MM━━<emoji>━━❯<slug>` form —
      # then the status its contents justify, then the move. All of them aim
      # at {Feature.plan_dirname}, so they cannot disagree about the final
      # name; splitting them keeps each auditable on its own, instead of one
      # report line where a spelling migration also appears to have opinions
      # about the state of the work.
      #
      # A folder an agent holds a lock on ({Plans::Lock}) keeps its name, the
      # same as one passed in +except+. A lock left by a process that is gone
      # from this machine is removed by a committing run; one from another
      # machine is reported and never touched, since its pid means nothing here.
      class Dirs
        # A proposed rename.
        #
        # @!attribute [r] dirname
        #   @return [String] the folder as it stands
        # @!attribute [r] from
        #   @return [Symbol] the state it claims
        # @!attribute [r] to
        #   @return [Symbol] the state its contents justify
        # @!attribute [r] source
        #   @return [String] absolute path now
        # @!attribute [r] target
        #   @return [String] absolute path after
        # @!attribute [r] reason
        #   @return [String] why the current name is wrong
        Change = Data.define(:dirname, :from, :to, :source, :target, :reason) do
          # @return [String] a single auditable line — `⇒` rather than `→`,
          #   which the folder names themselves now contain
          def to_s = "#{dirname} ⇒ #{target_name}  (#{reason})"

          # @return [String] the new name, with its subfolder when it is in one
          def target_name
            parent = File.basename(File.dirname(target))
            Plans::Tree::SUBFOLDERS.include?(parent) ? "#{parent}/#{File.basename(target)}" : File.basename(target)
          end
        end

        # A lock file found on the way.
        #
        # @!attribute [r] dirname
        #   @return [String] the plan folder it is in
        # @!attribute [r] path
        #   @return [String] the plan folder, absolute
        # @!attribute [r] lock
        #   @return [OpenLanes::Plans::Lock]
        HeldLock = Data.define(:dirname, :path, :lock) do
          # @return [Boolean] written on this machine by a process that is gone
          def stale? = lock.local? && !lock.alive?

          # @return [Boolean] written on another machine, so never cleared here
          def foreign? = !lock.local?

          # @return [String]
          def to_s = "#{dirname}: locked by pid #{lock.pid} on #{lock.host} since #{lock.started_at.utc.iso8601}"
        end

        # The state a folder's contents justify, or the one it claims when
        # nothing fits. What a rename moves toward, and what the dispatcher
        # reads on a dry run, which renames nothing, so the preview still
        # names the agents a real run would start.
        #
        # @param subject [OpenLanes::Plans::Subject]
        # @return [OpenLanes::Plans::Status]
        def self.target(subject) = subject.best_fit || subject.status

        # @param tree [OpenLanes::Plans::Tree]
        # @param except [Array<String>] ordinals to leave alone however wrong
        #   their names are: the dispatcher passes the plans an agent is
        #   working in right now
        def initialize(tree:, except: [])
          @tree = tree
          @except = except.map(&:to_s)
        end

        # @return [OpenLanes::Plans::Tree]
        attr_reader :tree

        # What would change, without changing anything. A folder can appear
        # twice: its spelling migration first, then its status correction.
        #
        # @return [Array<OpenLanes::Lifecycle::Resync::Dirs::Change>]
        def plan
          held = locks.reject(&:stale?).map(&:path)
          tree.everything.subjects.flat_map do |subject|
            next [] if @except.include?(subject.feature.ordinal.to_s) || held.include?(subject.feature.path)

            changes_for(subject)
          end
        end

        # Every lock file in the tree, inactive subfolders included.
        #
        # @return [Array<OpenLanes::Lifecycle::Resync::Dirs::HeldLock>]
        def locks
          tree.everything.subjects.filter_map do |subject|
            lock = Plans::Lock.read(subject.feature.path) or next
            HeldLock.new(dirname: subject.feature.dirname, path: subject.feature.path, lock:)
          end
        end

        # @param commit [Boolean] actually rename, and clear stale local locks
        # @return [Array<OpenLanes::Lifecycle::Resync::Dirs::Change>] what was proposed
        def call(commit: false)
          changes = plan
          return changes unless commit

          locks.select(&:stale?).each { |held| Plans::Lock.remove(held.path) }
          UI.stepping(changes, "Renaming") { |change| rename(change) }
          tree.reload
          changes
        end

        private

        # A folder moves when the name it has is not the name it should have.
        # {target} says what that name is; this says how to get there, as up
        # to two renames applied in order. The status rename starts from where
        # the spelling rename left the folder, not from where it stands now,
        # so committing the steps sequentially never renames a path that has
        # already moved out from under it.
        #
        # @param subject [OpenLanes::Plans::Subject]
        # @return [Array<OpenLanes::Lifecycle::Resync::Dirs::Change>] empty when the name
        #   is already right
        def changes_for(subject)
          feature = subject.feature
          fit = self.class.target(subject)
          steps = []

          spelled = feature.dirname_as(subject.status)
          if spelled != feature.dirname
            steps << step(from:   subject.status,
              to:     subject.status,
              source: feature.path,
              target: beside(feature.path, spelled),
              reason: spelling_reason(feature))
          end

          if fit.key != subject.status.key
            source = steps.empty? ? feature.path : steps.last.target
            steps << step(from:   subject.status,
              to:     fit,
              source:,
              target: beside(source, feature.dirname_as(fit)),
              reason: subject.violation || "contents now justify #{fit.label}")
          end

          source = steps.empty? ? feature.path : steps.last.target
          home = home_for(feature, fit)
          steps << step(from: fit, to: fit, source:, target: home, reason: placement_reason(feature, fit)) if home != source

          steps
        end

        # @param from [OpenLanes::Plans::Status]
        # @param to [OpenLanes::Plans::Status]
        # @param source [String] absolute path the rename starts from
        # @param target [String] absolute path it ends at
        # @param reason [String]
        # @return [OpenLanes::Lifecycle::Resync::Dirs::Change]
        def step(from:, to:, source:, target:, reason:)
          Change.new(dirname: File.basename(source), from: from.key, to: to.key, source:, target:, reason:)
        end

        # @param path [String]
        # @param name [String]
        # @return [String] +name+ in the same directory as +path+
        def beside(path, name) = File.join(File.dirname(path), name)

        # Where a plan in this state lives, and under which name: an inactive
        # plan in its subfolder, dated, keeping a date it already carries
        # there; any other plan at the top level, undated.
        #
        # @param feature [OpenLanes::Plans::Feature]
        # @param status [OpenLanes::Plans::Status]
        # @return [String] absolute
        def home_for(feature, status)
          subfolder = Plans::Tree.subfolder_for(status)
          return File.join(tree.dir, feature.dirname_as(status, archived_on: nil)) unless subfolder

          parent = File.join(tree.dir, subfolder)
          date = (feature.archived_on if File.dirname(feature.path) == parent) || Vcs::RenameDate.for(feature.path)
          File.join(parent, feature.dirname_as(status, archived_on: date))
        end

        # @param feature [OpenLanes::Plans::Feature]
        # @param status [OpenLanes::Plans::Status]
        # @return [String]
        def placement_reason(feature, status)
          subfolder = Plans::Tree.subfolder_for(status)
          here = File.dirname(feature.path)
          return "#{status.label} lives in #{subfolder}/" if subfolder && here != File.join(tree.dir, subfolder)
          return "a plan moved aside carries the date it was moved" if subfolder
          return "#{status.label} is not inactive; back to #{File.basename(tree.dir)}/" if here != tree.dir

          "an open plan's name carries no date"
        end

        # @param feature [OpenLanes::Plans::Feature]
        # @return [String] why the spelling is wrong, status aside
        def spelling_reason(feature)
          return "#{feature.dirname_ordinal} is not padded to #{feature.ordinal}" unless feature.padded?

          "name is not in canonical NNN.MM━━<emoji>━━❯<slug> form"
        end

        # A rename that finds its target occupied has not happened, and saying
        # nothing about it would leave the folder misnamed with a report
        # claiming otherwise. Two folders can want the same canonical name —
        # `018-⚪️--foo` and `018.00-⚪️ → foo` are the same plan written twice.
        #
        # @param change [OpenLanes::Lifecycle::Resync::Dirs::Change]
        # @return [void]
        # @raise [OpenLanes::Error] when the target name is already taken
        def rename(change)
          return if OpenLanes.move_directory(change.source, change.target)

          raise Error, "cannot rename #{change.dirname} — #{File.basename(change.target)} already exists"
        end
      end

      # `resync prs` — puts an `[NNN.MM]` prefix on every pull request title that
      # lacks one, and `[DEV.00]` on the ones that implement no plan.
      #
      # The resolution order is the branch name first, then the diff, and only
      # when the diff touches exactly one plan. Anything else is reported for a
      # human and never edited: `pull-requests.md` is generated from these
      # titles, and a wrong number files work under a plan that did not do it,
      # leaving the plan that did looking untouched.
      class Prs
        # The marker this tool used to write, now replaced. A title wearing it is
        # rewritten in place: the assertion it makes — "this belongs to no
        # specification" — is still true and still somebody's deliberate call,
        # so it is restamped rather than re-resolved.
        STALE = /\A\[#{Regexp.escape(OpenLanes::STALE_NO_PLAN_PREFIX)}\]\s*/

        # Titles that already carry a prefix — a plan number, the no-plan marker,
        # or the legacy `[XXX]`.
        PREFIXED = /\A\[(?:\d{3}(?:\.\d{2})?|#{OpenLanes::NO_PLAN_PREFIX}|XXX)\](?:\([A-Z]\))?\s/

        # Finds a plan number in a branch name: `kig/018.01-verify`, `002-slug`.
        BRANCH_PATTERN = %r{(?:\A|[/\-_])(\d{3}(?:\.\d{2})?)(?:\z|[-_])}

        # A proposed retitle.
        #
        # @!attribute [r] number
        #   @return [Integer] the pull request
        # @!attribute [r] title
        #   @return [String] as it stands
        # @!attribute [r] new_title
        #   @return [String, nil] nil when nothing may safely be done
        # @!attribute [r] ordinal
        #   @return [OpenLanes::Plans::Ordinal, nil]
        # @!attribute [r] reason
        #   @return [String] how it was resolved, or why it was not
        # @!attribute [r] ambiguous
        #   @return [Boolean] a human must decide; never edited
        # @!attribute [r] assumed
        #   @return [Boolean] "no plan" was inferred, not asserted by the author
        Change = Data.define(:number, :title, :new_title, :ordinal, :reason, :ambiguous, :assumed, :adopted) do
          # @return [Boolean]
          def ambiguous? = ambiguous

          # @return [Boolean]
          def assumed? = assumed

          # @return [Boolean] whether a plan folder was minted for this one
          def adopted? = adopted

          # @return [Boolean] safe to apply without a human looking
          def applicable? = !ambiguous && !new_title.nil?
        end

        # @param tree [OpenLanes::Plans::Tree]
        # @param github [OpenLanes::Vcs::GitHub]
        # @param adopt [Boolean] give a plan folder to every pull request that
        #   resolves to none, rather than flagging it and moving on
        # @param root [String, nil] repository root, for reading branches
        def initialize(tree:, github: Vcs::GitHub.new, adopt: true, root: nil)
          @tree = tree
          @github = github
          @adopt = adopt
          @root = root
        end

        # @return [Boolean]
        def adopt? = @adopt

        # @return [OpenLanes::Plans::Tree]
        attr_reader :tree

        # @return [OpenLanes::Vcs::GitHub]
        attr_reader :github

        # What would change, without changing anything.
        #
        # @return [Array<OpenLanes::Lifecycle::Resync::Prs::Change>]
        def plan
          restamps + resolve(candidates).then { |changes| adopt? ? with_adoptions(changes) : changes }
        end

        # @return [Array<OpenLanes::Lifecycle::Resync::Prs::Change>]
        def restamps = stale.map { |pull| restamped(pull) }

        # @param commit [Boolean] actually retitle, and mint the folders
        # @return [Array<OpenLanes::Lifecycle::Resync::Prs::Change>] what was proposed
        def call(commit: false)
          changes = resolve(candidates)
          return restamps + (adopt? ? with_adoptions(changes) : changes) unless commit

          changes = with_adoptions(changes, create: true) if adopt?
          changes = restamps + changes
          applicable = changes.select(&:applicable?)
          UI.stepping(applicable, "Retitling") { |c| github.retitle(number: c.number, title: c.new_title) }
          changes
        end

        # @return [Array<OpenLanes::Lifecycle::Adoption>] the adopter, memoized
        def adoption = @adoption ||= Adoption.new(tree:, github:, root: @root)

        private

        # @return [Array<Hash>] pull requests with no prefix yet
        def candidates
          github.pulls.reject { |pr| pr[:title].to_s.match?(PREFIXED) || pr[:title].to_s.match?(STALE) }
        end

        # @return [Array<Hash>] pull requests still wearing the old marker
        def stale = github.pulls.select { |pr| pr[:title].to_s.match?(STALE) }

        # @param pull [Hash]
        # @return [OpenLanes::Lifecycle::Resync::Prs::Change]
        def restamped(pull)
          Change.new(number: pull[:number],
            title: pull[:title],
            ordinal: nil,
            ambiguous: false,
            new_title: pull[:title].sub(STALE, "[#{OpenLanes::NO_PLAN_PREFIX}] "),
            reason: "the no-plan marker is now [#{OpenLanes::NO_PLAN_PREFIX}]",
            assumed: false,
            adopted: false)
        end

        # @param pulls [Array<Hash>]
        # @return [Array<OpenLanes::Lifecycle::Resync::Prs::Change>]
        def resolve(pulls) = pulls.map { |pr| change_for(pr) }

        # Replace every flagged change with one that points at a plan folder the
        # pull request now owns. The unresolvable ones were unresolvable because
        # no plan described them — so the answer is a plan, not a shrug.
        #
        # @param changes [Array<OpenLanes::Lifecycle::Resync::Prs::Change>]
        # @param create [Boolean] mint the folders, rather than only saying so
        # @return [Array<OpenLanes::Lifecycle::Resync::Prs::Change>]
        def with_adoptions(changes, create: false)
          orphans = changes.select(&:ambiguous?)
          return changes if orphans.empty?

          pulls = orphans.map { |c| pull_by_number.fetch(c.number) }
          adoptees = create ? adoption.call(pulls) : adoption.plan(pulls)
          by_number = adoptees.to_h { |a| [a.pull[:number], a] }

          changes.map { |c| c.ambiguous? && by_number[c.number] ? adopted(c, by_number[c.number]) : c }
        end

        # @return [Hash{Integer => Hash}]
        def pull_by_number = @pull_by_number ||= candidates.to_h { |pr| [pr[:number], pr] }

        # @param change [OpenLanes::Lifecycle::Resync::Prs::Change]
        # @param adoptee [OpenLanes::Lifecycle::Adoption::Adoptee]
        # @return [OpenLanes::Lifecycle::Resync::Prs::Change]
        def adopted(change, adoptee)
          change.with(
            ordinal:   adoptee.ordinal,
            new_title: "#{adoptee.ordinal.to_prefix} #{change.title}",
            reason:    "#{change.reason} — adopted into #{adoptee.dirname}",
            ambiguous: false,
            adopted:   true
          )
        end

        # @param pull [Hash]
        # @return [OpenLanes::Lifecycle::Resync::Prs::Change]
        def change_for(pull)
          from_branch(pull) || from_files(pull) || no_plan(pull)
        end

        # 1. The branch name — the one moment the author certainly knew.
        #
        # @param pull [Hash]
        # @return [OpenLanes::Lifecycle::Resync::Prs::Change, nil]
        def from_branch(pull)
          match = BRANCH_PATTERN.match(pull[:branch].to_s) or return nil
          ordinal = Plans::Ordinal.parse(match[1])

          unless tree.everything.include?(ordinal)
            return flag(pull, "branch names #{ordinal}, which has no folder in #{File.basename(tree.dir)}")
          end

          resolved(pull, ordinal, "branch #{pull[:branch]}")
        end

        # 2. The diff, and only when it touches exactly one plan.
        #
        # @param pull [Hash]
        # @return [OpenLanes::Lifecycle::Resync::Prs::Change, nil]
        def from_files(pull)
          touched = Array(pull[:files]).filter_map { |path| ordinal_for_path(path) }.uniq
          case touched.size
          when 1 then resolved(pull, touched.first, "diff touches only #{touched.first}")
          when 0 then nil
          else flag(pull, "diff touches #{touched.join(", ")} and none is obviously primary")
          end
        end

        # @param path [String] a path from the diff
        # @return [OpenLanes::Plans::Ordinal, nil]
        def ordinal_for_path(path)
          folder = Plans::Tree.plan_folder(path) or return nil
          ordinal = Plans::Ordinal.from_dirname(folder)
          ordinal if ordinal && tree.everything.include?(ordinal)
        end

        # @param pull [Hash]
        # @param ordinal [OpenLanes::Plans::Ordinal]
        # @param why [String]
        # @return [OpenLanes::Lifecycle::Resync::Prs::Change]
        def resolved(pull, ordinal, why)
          Change.new(number: pull[:number],
            title: pull[:title],
            ordinal:,
            reason: why,
            new_title: "#{ordinal.to_prefix} #{pull[:title]}",
            ambiguous: false,
            assumed: false,
            adopted: false)
        end

        # Nothing resolved, so this is developer work — but that is an assertion
        # about intent, so it is marked as assumed rather than stated as fact.
        #
        # @param pull [Hash]
        # @return [OpenLanes::Lifecycle::Resync::Prs::Change]
        def no_plan(pull)
          Change.new(number: pull[:number],
            title: pull[:title],
            ordinal: nil,
            new_title: "[#{OpenLanes::NO_PLAN_PREFIX}] #{pull[:title]}",
            reason: "no plan resolved from the branch or the diff",
            ambiguous: false,
            assumed: true,
            adopted: false)
        end

        # @param pull [Hash]
        # @param why [String]
        # @return [OpenLanes::Lifecycle::Resync::Prs::Change]
        def flag(pull, why)
          Change.new(number: pull[:number],
            title: pull[:title],
            new_title: nil,
            ordinal: nil,
            reason: why,
            ambiguous: true,
            assumed: false,
            adopted: false)
        end
      end
    end
  end
end
