# frozen_string_literal: true

require "concurrent/atomic/atomic_boolean"
require "open3"

module OpenLanes
  module CLI
    module App
      # `openlanes app start` — run a plan's app in the foreground, as
      # `.openlanes.yml` `app:` declares it, until Ctrl-C, `openlanes app
      # stop`, or Stop in the Preview tab.
      class Start < Base
        include Registry

        desc "Run a plan's app from .openlanes.yml app:, for the Preview tab"

        argument :plan, required: false, desc: "Which plan: NNN or NNN.MM; its worktree when it has one"

        option :redis_url, desc: "Redis the control room reads (default: .openlanes.yml redis_url, else $REDIS_URL, else #{Live::DEFAULT_URL})"
        option :demo,
          type:    :boolean,
          default: false,
          desc:    "Publish where `openlanes web --demo` reads, beside its sample board"
        option :ready_timeout, default: Apps::Supervisor::READY_TIMEOUT.to_s, desc: "Seconds each process has to become ready"
        option :control_room, default: Apps::Framing::ORIGIN, desc: "The control room's origin, which the app must allow to frame it"

        example [
          "                     # this checkout's app, filed under the plan its branch names",
          "012                  # plan 012's app, in its worktree when it has one",
          "--demo --no-quiet    # beside `openlanes web --demo`"
        ]

        # @param plan [String, nil]
        # @param options [Hash]
        # @return [void]
        def call(plan: nil, **options)
          quiet?(options)
          root = checkout(ordinal_of(plan), options)
          definition = definition_in(root)
          branch = branch_of(root)
          ordinal = ordinal_of(plan) || branch[BRANCH_PLAN, 1] || NO_PLAN
          store, keys = board(options)
          runner = Apps.runner(definition:,
            root:,
            plan: ordinal,
            branch:,
            store:,
            keys:,
            say:        ->(line) { UI.line("#{ordinal} #{line}") },
            supervisor: { ready_timeout: Float(options[:ready_timeout]), origin: options[:control_room],
                          output: ->(name, line) { UI.line("#{name}: #{line}", bullet: "│") } })
          # A trap may not take a lock, and the flag takes one.
          %w[INT TERM].each { |name| Signal.trap(name) { Thread.new { runner.stopping.make_true } } }
          UI.line("Starting #{ordinal}'s app in #{root} (#{branch}); Ctrl-C stops it")
          runner.call
        rescue Apps::Supervisor::StartFailed => e
          refuse("#{ordinal}'s app did not start: #{e.message}", 70)
        ensure
          store&.close
        end

        private

        # The plan's worktree when it has one, else the project root.
        #
        # @return [String]
        def checkout(ordinal, options)
          return Dir.pwd unless ordinal

          subject = tree_for(options).find(Plans::Ordinal.parse(ordinal))
          refuse("No plan #{ordinal} in #{OpenLanes::PLANS_DIR}", 66) unless subject
          path = Vcs.worktree(root: Dir.pwd).path_for(subject.feature)
          File.directory?(path) ? path : Dir.pwd
        end

        # The checkout's own `.openlanes.yml`: on a plan's branch, luke may
        # have written `app:` there and nowhere else yet (M12).
        #
        # @return [OpenLanes::Apps::Definition]
        def definition_in(root)
          definition = Apps.definition(OpenLanes::Config.load(root))
          return definition if definition

          refuse("#{File.join(root, Project::FILE)} declares no app:, so there is nothing to start.", 65)
        rescue OpenLanes::Error => e
          refuse(e.message, 65)
        end

        # `symbolic-ref` rather than `rev-parse`, so a branch with no commit
        # yet still has its name.
        #
        # @return [String]
        def branch_of(root)
          out, status = Open3.capture2("git", "-C", root, "symbolic-ref", "--short", "HEAD", err: File::NULL)
          status.success? ? out.strip : "(no branch)"
        end

        # The store and keys the control room reads, or neither when Redis
        # is not there: the app runs either way.
        #
        # @return [Array(OpenLanes::Live::Store, OpenLanes::Live::Keys), Array(nil, nil)]
        def board(options)
          url = Live.redis_url(option: options[:redis_url], config: OpenLanes::Config.current)
          store = Live.connect(url)
          keys = Live.keys(root: Dir.pwd)
          [store, options[:demo] ? keys.with(repo: "demo/#{keys.repo}") : keys]
        rescue Live::Unavailable => e
          UI.line("#{e.message}: the app runs, but the Preview tab will not hear of it")
          [nil, nil]
        end
      end
    end
  end
end
