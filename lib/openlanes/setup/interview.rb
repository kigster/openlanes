# frozen_string_literal: true

module OpenLanes
  module Setup
    # What `openlanes init` settles about a project: on a terminal through the
    # form, and with no terminal (`-y`, or no TTY) from the flags, the
    # current file and the scan. One path for both modes, so `-y` touches no
    # prompt and no extractor, and makes no network call even with a key set.
    class Interview
      # The answer offered first when `desired_codebase_quality` is asked and the
      # current file has none. Unasked (`-y`), it stays unset, so the first review
      # that is ok but not perfect asks it instead (R4).
      DEFAULT_QUALITY = :high

      # @param root [String]
      # @param defaults [OpenLanes::Config] the current file under `--reconfigure`, else empty
      # @param given [Hash{Symbol => Object}] flag values; a question with one is not asked
      # @param terminal [OpenLanes::Setup::ProjectForm::Terminal, nil] nil when nothing is asked
      def initialize(root:, defaults: Config.new, given: {}, terminal: nil)
        @root = root
        @defaults = defaults
        @given = given
        @terminal = terminal
      end

      # Starts from the current file, so every key the form does not ask about
      # (coverage:, review:, questions:, merge.max_rejections, plans.aging_since)
      # survives --reconfigure. Building a fresh Config here once dropped them,
      # and losing coverage: turns the gate off.
      #
      # @return [OpenLanes::Config] not yet validated; the caller parses it back
      def call
        answers = @terminal ? form : {}
        decisions = ProjectForm::Answers.new(answers:, scan:, file:, wanted_ci: @given[:ci]).decisions
        @defaults.with(**basics(answers),
          frontend:               frontend(decisions),
          ci:                     nil,
          stack:                  nil,
          architecture_decisions: decisions.empty? ? nil : decisions)
      end

      private

      # @return [OpenLanes::Setup::Architecture]
      def scan = @scan ||= ArchitectureScan.new(@root).call

      # The current file's decisions; an older file's `ci:` and `stack:` read as
      # those, so `--reconfigure` moves them over rather than losing them.
      #
      # @return [OpenLanes::Setup::ArchitectureDecisions]
      def file
        @file ||= @defaults.architecture_decisions ||
                  ArchitectureDecisions.from_legacy(legacy_ci: @defaults.ci, stack: @defaults.stack)
      end

      # @return [Hash{Symbol => Object}]
      def form
        preselection = ProjectForm::Preselection.new(scan:, file:, config: known)
        engine = ProjectForm.engine
        renderer = ProjectForm::Renderer.new(prompt: @terminal.prompt,
          out: @terminal.out,
          preselect: ->(id) { preselection.for(id, engine.answers) })
        ProjectForm::Driver.new(renderer:, preselection:, terminal: @terminal, prefilled:).call(engine)
      end

      # @return [Hash{Symbol => Object}] flags typed, plus the flag that spares an
      #   empty folder from being asked what it holds
      def prefilled
        typed = @given.slice(*ProjectForm.flags).transform_values { it.is_a?(Symbol) ? it.to_s : it }
        scan.blank? && file.current.blank? ? typed.merge(greenfield: true) : typed
      end

      # @return [Hash{Symbol => Object}] what the form shows for its other questions
      def known
        { project: @defaults.project || File.basename(@root), starts: @defaults.starts&.to_s,
          jobs: @defaults.jobs, merge_by: @defaults.merger.to_s, detail: file.detail&.to_s,
          desired_codebase_quality: (@defaults.desired_codebase_quality || DEFAULT_QUALITY).to_s }.compact
      end

      # Each from its flag, else its answer, else the current file, else its default.
      #
      # @return [Hash{Symbol => Object}]
      def basics(answers)
        { project:                  value(:project, answers, known[:project]),
          starts:                   value(:starts, answers, @defaults.starts || :research).to_sym,
          jobs:                     count(value(:jobs, answers, @defaults.jobs)),
          merge_by:                 value(:merge_by, answers, @defaults.merger).to_sym,
          desired_codebase_quality: value(:desired_codebase_quality, answers, @defaults.desired_codebase_quality)&.to_sym }
      end

      # @return [Object, nil]
      def value(key, answers, fallback)
        return @given[key] if @given.key?(key)

        answers.fetch(key, fallback)
      end

      # @return [Integer, nil]
      # @raise [OpenLanes::Error] for an answer that is not a count
      def count(jobs)
        return nil if jobs.nil? || jobs.to_s.strip.empty?
        return jobs.to_s.to_i if jobs.to_s.match?(/\A[1-9]\d*\z/)

        raise Error, "jobs must be a whole number above zero, not #{jobs.inspect}"
      end

      # A flag, else what the wanted front end says, else the current file. Left
      # unset when nobody said, so each plan decides.
      #
      # @return [Boolean, nil]
      def frontend(decisions)
        return @given[:frontend] if @given.key?(:frontend)

        wanted = decisions.target.front_end
        wanted.empty? ? @defaults.frontend : wanted != [:none]
      end
    end
  end
end
