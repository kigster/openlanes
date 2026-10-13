# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yaml"

module OpenLanes
  module Evals
    # Runs the real agent on a case's fixture, in a repository nobody else
    # uses, under a token cap, and scores what it leaves behind.
    #
    # The steps mirror what the runner does around one agent, and reuse its
    # pieces rather than imitating them: {Execution.executor} runs the agent
    # with the same autonomy boundary, and `resync dirs` renames the folder to
    # the state its contents justify, as the runner does after every round.
    # What it cannot reproduce is publishing. A build agent's 🟢 needs a pull
    # request on GitHub, so build cases check signatures and diffs, not state.
    class Live
      # The default ceiling for one live case. Cheap enough to run by hand,
      # high enough that a deep research case is not killed for doing its job.
      DEFAULT_MAX_TOKENS = 300_000

      # The one plan in the fixture repository.
      ORDINAL = "001.00"

      # Who the fixture commit is from: a made-up identity, so a commit in a
      # temp repository can never be mistaken for a person's.
      AUTHOR = ["-c", "user.name=OpenLanes Eval", "-c", "user.email=eval@example.com",
                "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"].freeze

      # @!attribute [r] score
      #   @return [OpenLanes::Evals::Score]
      # @!attribute [r] result
      #   @return [OpenLanes::Execution::Executor::Result]
      # @!attribute [r] root
      #   @return [String, nil] the repository, when it was kept
      Outcome = Data.define(:score, :result, :root)

      # @param kase [OpenLanes::Evals::Case] at the depth to run it
      # @param registry [OpenLanes::Agents::Registry]
      # @param max_tokens [Integer] enforced by the executor's meter
      # @param timeout [Integer, nil] seconds; nil leaves the agent's own clock
      # @param spawn [#call, nil] the executor's seam; nil starts the real CLI
      # @param trace_dir [String, nil] where the NDJSON trace goes
      # @param keep [Boolean] leave the repository on disk for inspection
      def initialize(kase, registry: Agents.registry, max_tokens: DEFAULT_MAX_TOKENS, timeout: nil, spawn: nil,
        trace_dir: nil, keep: false)
        @kase = kase
        @registry = registry
        @agent = registry.find(kase.agent) or raise Invalid, "#{kase.path}: names no agent called #{kase.agent}"
        @max_tokens = max_tokens
        @timeout = timeout
        @spawn = spawn
        @trace_dir = trace_dir
        @keep = keep
      end

      # @return [OpenLanes::Evals::Live::Outcome]
      def call
        root = Dir.mktmpdir("openlanes-eval-")
        begin
          plans = build(root)
          result = executor(root).call(@agent, start(plans), root:)
          Lifecycle.resync_dirs(tree: Plans.tree(plans)).call(commit: true)
          found = Plans.tree(plans).find(ORDINAL)
          run = Run.new(seconds: result.seconds, tokens: result.fresh)
          score = Scorer.new(@kase, registry: @registry)
                        .call(folder: found&.feature&.path || File.join(plans, "missing"), run:, repo: root)
          Outcome.new(score:, result:, root: @keep ? root : nil)
        ensure
          FileUtils.rm_rf(root) unless @keep
        end
      end

      private

      # A repository holding the fixture, committed, so the executor's
      # after-check has a HEAD to hold the agent to.
      #
      # @return [String] the `.plans` directory
      def build(root)
        git(root, "init", "-q")
        @kase.fixture.repo.each { |name, body| write(File.join(root, name), body) }
        plans = File.join(root, OpenLanes::PLANS_DIR)
        status = Plans.status(@kase.fixture.state)
        folder = File.join(plans, Plans.plan_dirname(ORDINAL, status, @kase.fixture.slug))
        @kase.fixture.files.each { |name, body| write(File.join(folder, name), body) }
        stamp_depth(File.join(folder, Plans::Spec::FILENAME))
        git(root, "add", "-A")
        git(root, *AUTHOR, "commit", "-q", "-m", "Eval fixture #{@kase}")
        plans
      end

      # The depth reaches the agent the way it would in a real plan: as
      # `depth:` in spec.md's frontmatter, which the profile turns into effort.
      #
      # @return [void]
      def stamp_depth(path)
        meta, body = Frontmatter.split(File.read(path, encoding: "UTF-8"))
        meta = meta.merge("depth" => @kase.depth.to_s)
        File.write(path, "#{YAML.dump(meta)}---\n#{body}")
      end

      # The runner moves a folder to the agent's `starts_as` the moment it is
      # dispatched, so r2d2 works a 🟡 plan and hansolo a 👀 one. Same here.
      #
      # @return [OpenLanes::Plans::Subject]
      def start(plans)
        subject = Plans.tree(plans).find(ORDINAL)
        target = @agent.starts_as
        return subject unless target && subject.machine.may?(target)

        subject.machine.promote!(target)
        Plans.tree(plans).find(ORDINAL)
      end

      # @return [OpenLanes::Execution::Executor]
      def executor(root)
        options = { root:, max_tokens: @max_tokens, fresh_budget: true, timeout: @timeout }
        options[:spawn] = @spawn if @spawn
        options[:trace_dir] = @trace_dir if @trace_dir
        Execution.executor(**options)
      end

      # @return [void]
      def write(path, body)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end

      # @return [void]
      # @raise [OpenLanes::Error] when git refuses
      def git(root, *args)
        return if system("git", "-C", root, *args, out: File::NULL, err: File::NULL)

        raise Error, "git #{args.last(2).join(" ")} failed in #{root}"
      end
    end
  end
end
