# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module Engine
    module Verification
      # One verification of one plan: `<plan folder>/verification/<number>/`
      # (M14), where verifier leaves its screenshots and `report.md`.
      #
      # The number is read from disk, never kept anywhere else: a round is
      # finished once its `report.md` exists, so the next run of verifier gets
      # the next number, while a run that died before reporting hands its
      # folder to the one that follows it rather than leaving a gap.
      #
      # @!attribute [r] plan_dir
      #   @return [String] the plan folder, in the main checkout
      # @!attribute [r] number
      #   @return [Integer] from 1
      Round = Data.define(:plan_dir, :number) do
        # @return [String] the round's own folder
        def dir = File.join(plan_dir, Round::FOLDER, number.to_s)

        # @return [String] what verifier writes when it is done
        def report_path = File.join(dir, Round::REPORT)

        # @return [Boolean] whether verifier, or the engine for it, reported
        def reported? = File.file?(report_path)

        # @return [Report, nil]
        def report = reported? ? Report.read(report_path) : nil

        # @return [String] the folder, relative to the plan folder
        def relative = File.join(Round::FOLDER, number.to_s)

        # @return [String] where the engine records the verification commit
        def published_path = File.join(dir, Round::PUBLISHED)

        # Whether the engine pushed this round's evidence. verifier's
        # `Verdict: verified` is only verifier's word: a run that died after
        # writing it, before its signature or the push, would otherwise be
        # taken for a round waiting on CI, and the old head labelled ready.
        #
        # @return [Boolean]
        def published? = File.file?(published_path)

        # @param sha [String, nil] the commit that carried the round
        # @return [void]
        def publish!(sha) = File.write(published_path, "#{sha}\n")

        # @return [self] with its folder made
        def make!
          FileUtils.mkdir_p(dir)
          self
        end
      end

      class Round
        # Under the plan folder.
        FOLDER = "verification"

        # verifier's own account of the round.
        REPORT = "report.md"

        # The engine's note to verifier about the app it started.
        APP_NOTE = "app.md"

        # The engine's record that the round's evidence was pushed: the SHA.
        PUBLISHED = "published.txt"

        class << self
          # @param plan_dir [String]
          # @return [Array<Round>] every round on disk, oldest first
          def all(plan_dir)
            base = File.join(plan_dir, FOLDER)
            return [] unless File.directory?(base)

            Dir.children(base).grep(/\A[1-9]\d*\z/).map(&:to_i).sort.map { new(plan_dir:, number: it) }
          end

          # @param plan_dir [String]
          # @return [Round, nil] the newest round, reported or not
          def latest(plan_dir) = all(plan_dir).last

          # The round a new run of verifier works in: the newest one when it
          # has no report yet, otherwise the one after it.
          #
          # @param plan_dir [String]
          # @return [Round]
          def next(plan_dir)
            last = latest(plan_dir)
            return last if last && !last.reported?

            new(plan_dir:, number: (last&.number || 0) + 1)
          end
        end
      end
    end
  end
end
