# frozen_string_literal: true

# Help screens come from dry-cli-help, which prepends itself to Dry::CLI the
# moment it loads, so it has to load before the registry's `help` block runs.
require "dry/cli"
require "dry/cli/help"

require "dry/inflector"
# Every command workflow answers a Dry::Monads::Result (see OpenLanes::Refusal).
require "dry/monads"
require "fileutils"
require "open3"
require "shellwords"
require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "openlanes"  => "OpenLanes",
  "api"        => "API",
  "cli"        => "CLI",
  "github"     => "GitHub",
  "issue"      => "Issues",
  "list_plans" => "ListPlans",
  "unit"       => "Units",
  "ui"         => "UI"
)
loader.collapse("#{__dir__}/openlanes/support")
loader.collapse("#{__dir__}/openlanes/cli/coverage")
loader.collapse("#{__dir__}/openlanes/cli/create")
loader.collapse("#{__dir__}/openlanes/cli/docs")
loader.collapse("#{__dir__}/openlanes/cli/eval")
loader.collapse("#{__dir__}/openlanes/cli/index")
loader.collapse("#{__dir__}/openlanes/cli/init")
loader.collapse("#{__dir__}/openlanes/cli/list_plans")
loader.collapse("#{__dir__}/openlanes/cli/review")
loader.collapse("#{__dir__}/openlanes/cli/run")
loader.collapse("#{__dir__}/openlanes/cli/setup")
loader.collapse("#{__dir__}/openlanes/cli/start")
loader.collapse("#{__dir__}/openlanes/cli/states")
loader.collapse("#{__dir__}/openlanes/cli/uml")
loader.collapse("#{__dir__}/openlanes/cli/unblock")
loader.collapse("#{__dir__}/openlanes/cli/version")
loader.collapse("#{__dir__}/openlanes/cli/web")
loader.collapse("#{__dir__}/openlanes/cli/worktree")
loader.collapse("#{__dir__}/openlanes/cli/agents/subcommands")
loader.collapse("#{__dir__}/openlanes/cli/linear/subcommands")
loader.collapse("#{__dir__}/openlanes/cli/mail/subcommands")
loader.collapse("#{__dir__}/openlanes/cli/state/subcommands")
loader.collapse("#{__dir__}/openlanes/cli/resync/subcommands")
loader.collapse("#{__dir__}/openlanes/cli/skills/subcommands")
loader.collapse("#{__dir__}/openlanes/cli/api/subcommands")
loader.ignore("#{__dir__}/openlanes/cli/api/api.rb")
loader.collapse("#{__dir__}/openlanes/cli/app/subcommands")
loader.ignore("#{__dir__}/openlanes/cli/linear/linear.rb")
loader.ignore("#{__dir__}/openlanes/cli/mail/mail.rb")
loader.ignore("#{__dir__}/openlanes/cli/state/state.rb")
loader.ignore("#{__dir__}/openlanes/cli/app/app.rb")
loader.ignore("#{__dir__}/openlanes/linear/mapping.rb")
# ERB templates for the CI scaffold, not Ruby constants.
loader.ignore("#{__dir__}/openlanes/setup/templates")
loader.setup

# Spec → Plan → Build.
#
# Three phases, each with a file that proves it happened, and a guarded state
# machine that refuses to let a plan folder claim a phase it has not reached.
#
#   spec   ⚪ New          spec.md
#   plan   ⭐ Ready        plan.md
#   build  🟡 → ✅         pull-requests.md
#
# The conventions are not documented anywhere else by hand: the status
# vocabulary, the numbering rules and the transition table live here and are
# emitted by `openlanes docs`. Three hand-maintained copies of that table
# have already drifted apart, which is why there is now exactly one.

# © 2026 Konstantin Gredeskoul
module OpenLanes
  # The folder every project keeps its plans in.
  PLANS_DIR = ENV.fetch("PLANS_DIR", ".plans")

  # Prefix for a pull request that deliberately implements no plan —
  # dependency bumps, CI work, hotfixes, developer tooling.
  #
  # Lower case, and not a number, so it cannot be mistaken for one. It used to
  # be `DEV.00`, which read as a plan number and sorted among them.
  NO_PLAN_PREFIX = "dev"

  # What it used to be. Titles still wearing it are rewritten rather than
  # skipped as already-prefixed.
  STALE_NO_PLAN_PREFIX = "DEV.00"

  # Prefix for a pull request that implements *something* nothing could name.
  # Unlike `dev` this asserts nothing; it marks a question left open.
  NONE_PREFIX = "none"

  # @return [Dry::Inflector] shared Inflector
  def self.inflector = @inflector ||= ::Dry::Inflector.new

  # Move a directory, preferring `git mv` so its history follows it.
  #
  # Both the state machine and `resync dirs` move plan folders, and a folder
  # that loses its history because one of them used `FileUtils` is a folder
  # nobody can `git log`.
  #
  # @param source [String] absolute
  # @param target [String] absolute
  # @return [Boolean] false when the target was already occupied
  def self.move_directory(source, target)
    return false if File.exist?(target)

    # Into archive/ and friends, which the first move there creates.
    FileUtils.mkdir_p(File.dirname(target))
    parent = File.dirname(source)
    tracked = system("git",
      "-C",
      parent,
      "ls-files",
      "--error-unmatch",
      source,
      out: File::NULL,
      err: File::NULL)
    moved = tracked && system("git",
      "-C",
      parent,
      "mv",
      source,
      target,
      out: File::NULL,
      err: File::NULL)
    FileUtils.mv(source, target) unless moved
    true
  end

  # Plan numbers visible in `.plans` on a git ref, without checking it out,
  # the inactive subfolders included: an archived plan keeps its number.
  #
  # A pull request's branch is the only place that knows how far the sequence
  # had got when the work started, and branches are not all rebased onto the
  # same main. Reading the ref directly costs one `ls-tree` and no worktree.
  #
  # @param root [String] repository root
  # @param ref [String] a branch name; `origin/` is tried first
  # @return [Array<OpenLanes::Plans::Ordinal>] possibly empty
  def self.plans_on_ref(root, ref)
    ["origin/#{ref}", ref].each do |candidate|
      found = plans_at(root, candidate)
      return found unless found.empty?
    end
    []
  end

  # Plan numbers in `.plans` on one tree-ish, the inactive subfolders
  # included. {plans_on_ref} guesses at a branch name; this reads exactly
  # what it is given, which is what allocating a number across every branch
  # needs: a full ref name tried as `origin/refs/heads/x` would cost a
  # second `ls-tree` per branch for nothing.
  #
  # @param root [String] any directory inside the repository
  # @param treeish [String] a ref, or a commit
  # @param plans [String] the `.plans` directory, relative to +root+
  # @return [Array<OpenLanes::Plans::Ordinal>] empty when the ref is unknown
  #   or carries no plans
  def self.plans_at(root, treeish, plans: PLANS_DIR)
    dirs = [plans, *Plans::Tree::SUBFOLDERS.map { "#{plans}/#{it}" }].map { "#{it}/" }
    out, status = Open3.capture2("git",
      "-C",
      root,
      "ls-tree",
      "-d",
      "--name-only",
      treeish,
      *dirs,
      err: File::NULL)
    return [] unless status.success?

    out.lines.filter_map { |line| Plans::Ordinal.from_dirname(File.basename(line.strip)) }
  end

  # The agent that writes a specification for work that already shipped.
  # Named here rather than in the CLI so the definition file stays the single
  # source of truth about who does what.
  RETROACTIVE_WRITER = "yoda-writer"

  class Error < StandardError; end
end

# plans/status.rb and plans/feature.rb define methods on OpenLanes::Plans (`status`,
# `plan_dirname`, `titleize` and friends) beside the class each is named for.
# Zeitwerk loads a file when its constant is first named, and a caller of
# `Plans.status` names no constant, so without this those methods exist
# or not depending on what happened to load first.
%w[status feature].each { |name| loader.load_file("#{__dir__}/openlanes/plans/#{name}.rb") }
