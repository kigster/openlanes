# frozen_string_literal: true

require "fileutils"
require "open3"

module OpenLanes
  module Web
    # One save from the settings page (plan 058, B2, decision S1): write
    # `.openlanes.yml` in the main checkout, commit it alone and push `main`,
    # so every worktree made or rebased afterwards reads the new settings.
    #
    # Every refusal is decided before anything is written, so a refused save
    # leaves the file, HEAD and `origin/main` as they were. The push is the
    # harness's, declared through {Execution::Boundary.sanction} first, or an
    # agent running at that moment would be blamed for a moved `origin/main`.
    class SettingsSave
      # The branch a save lands on, and the remote it is pushed to.
      BRANCH = "main"
      REMOTE = "origin"

      # The commit's subject.
      MESSAGE = "Update #{Config::FILE} from the settings page".freeze

      # What the route answers: an HTTP status and its JSON body.
      Outcome = Data.define(:status, :body)

      # A guard that stopped the save.
      class Refused < StandardError
        # @return [String] e.g. "dirty_config"
        attr_reader :refusal

        # @param refusal [String]
        # @param reason [String]
        def initialize(refusal, reason)
          @refusal = refusal
          super(reason)
        end
      end

      # @param root [String] the main checkout
      # @param boundary [#sanction] {Execution::Boundary}, a seam for specs
      def initialize(root:, boundary: Execution::Boundary)
        @root = root
        @boundary = boundary
      end

      # @param values [Hash] the whole file, as the page has it
      # @param if_match [String] the etag the page read
      # @return [Outcome]
      def call(values:, if_match:)
        problems = Settings.validate(values)
        return Outcome.new(422, { errors: problems.map(&:to_json_hash) }) unless problems.empty?

        save(Settings.parse(values), if_match)
      rescue Refused => e
        Outcome.new(409, { refusal: e.refusal, reason: e.message })
      rescue Error => e
        failed(e)
      end

      private

      # @param config [Config] the parsed, valid values
      # @param if_match [String]
      # @return [Outcome]
      def save(config, if_match)
        guard!(if_match)
        return Outcome.new(200, { changed: false }) if unchanged?(config)

        fast_forward!
        Outcome.new(200, { changed: true, commit: land(config), etag: Settings.etag(@root) })
      end

      # Any other git failure: the server's log gets git's words, the
      # response a fixed sentence without the checkout's path (F102).
      #
      # @param error [OpenLanes::Error]
      # @return [Outcome]
      def failed(error)
        warn("settings save: #{error.message}")
        Outcome.new(500, { error: "git failed while saving #{Config::FILE}; see the server log" })
      end

      # The S1 guards, cheapest first. None of them writes.
      #
      # @param if_match [String]
      # @return [void]
      def guard!(if_match)
        branch = Settings.branch(@root)
        unless branch == BRANCH
          raise Refused.new("not_on_main", "the main checkout is on #{branch || "a detached HEAD"}, not #{BRANCH}")
        end
        raise Refused.new("dirty_config", "#{Config::FILE} has uncommitted edits; commit or discard them first") if dirty?
        raise Refused.new("stale_etag", "#{Config::FILE} changed since the page read it; reload") unless if_match == Settings.etag(@root)

        behind_remote!
      end

      # Fetches `origin/main` and refuses unless `main` can fast-forward to
      # it. A `main` ahead of `origin/main` is refused too: the push would
      # carry commits nobody asked the page to publish.
      #
      # @return [void]
      def behind_remote!
        _, ok = git("fetch", "-q", REMOTE, BRANCH)
        raise Refused.new("cannot_fast_forward", "could not fetch #{REMOTE}/#{BRANCH}") unless ok

        _, ancestor = git("merge-base", "--is-ancestor", "HEAD", "refs/remotes/#{REMOTE}/#{BRANCH}")
        unless ancestor
          raise Refused.new("cannot_fast_forward",
            "#{BRANCH} has commits #{REMOTE}/#{BRANCH} does not; it cannot fast-forward")
        end
        return if blob("HEAD") == blob("refs/remotes/#{REMOTE}/#{BRANCH}")

        raise Refused.new("stale_etag", "#{REMOTE}/#{BRANCH} holds a newer #{Config::FILE}; pull and reload")
      end

      # @param config [Config]
      # @return [Boolean] whether the file already says the same
      def unchanged?(config) = config.to_settings == Config.load(@root).to_settings

      # @return [void]
      def fast_forward!
        _, ok = git("merge", "-q", "--ff-only", "refs/remotes/#{REMOTE}/#{BRANCH}")
        raise Refused.new("cannot_fast_forward", "#{BRANCH} could not fast-forward to #{REMOTE}/#{BRANCH}") unless ok
      end

      # Writes, commits the file alone, declares the push and pushes it.
      #
      # @param config [Config]
      # @return [String] the commit
      def land(config)
        commit!(config)
        @boundary.sanction(@root, REMOTE, BRANCH)
        _, pushed = git("push", "-q", REMOTE, BRANCH)
        unless pushed
          undo!
          raise Refused.new("push_failed", "#{REMOTE} refused the push; nothing was changed")
        end
        git!("rev-parse", "HEAD").strip
      end

      # Writes the file and commits it alone. A commit that fails (a hook,
      # gpg signing, an `index.lock` left by a concurrent save) puts the file
      # and the index back, so the next save is not refused as dirty_config.
      # The reason is fixed text: git's output names the checkout's path and
      # whatever a hook printed, and neither belongs in a response body.
      #
      # @param config [Config]
      # @return [void]
      def commit!(config)
        before = git!("rev-parse", "HEAD").strip
        File.write(path, config.to_yaml)
        git!("add", "--", Config::FILE)
        git!("commit", "-q", "-m", MESSAGE, "--", Config::FILE)
      rescue Error
        git("reset", "-q", "--soft", before) if before
        restore!
        raise Refused.new("commit_failed", "git could not commit #{Config::FILE}; nothing was changed")
      end

      # Takes back the commit {#land} made, and the file with it.
      #
      # @return [void]
      def undo!
        git!("reset", "-q", "--soft", "HEAD~1")
        restore!
      end

      # Puts the file and its index entry back as HEAD has them.
      #
      # @return [void]
      def restore!
        git("reset", "-q", "--", Config::FILE)
        _, tracked = git("cat-file", "-e", "HEAD:#{Config::FILE}")
        tracked ? git!("checkout", "-q", "HEAD", "--", Config::FILE) : FileUtils.rm_f(path)
      end

      # @return [Boolean]
      def dirty? = !git!("status", "--porcelain", "--", Config::FILE).strip.empty?

      # @param ref [String]
      # @return [String, nil] the file's blob at +ref+
      def blob(ref)
        out, ok = git("rev-parse", "-q", "--verify", "#{ref}:#{Config::FILE}")
        ok ? out.strip : nil
      end

      # @return [String]
      def path = File.join(@root, Config::FILE)

      # @param args [Array<String>]
      # @return [Array(String, Boolean)]
      def git(*)
        out, status = Open3.capture2e("git", "-C", @root, *)
        [out, status.success?]
      end

      # @param args [Array<String>]
      # @return [String]
      # @raise [OpenLanes::Error]
      def git!(*args)
        out, ok = git(*args)
        raise Error, "git #{args.first} failed in #{@root}: #{out.strip}" unless ok

        out
      end
    end
  end
end
