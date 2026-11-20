# frozen_string_literal: true

module OpenLanes
  module Memory
    # `openlanes memory promote`, run by the engine itself once a run ends
    # (decision C1): without it a candidate seen on two plans waited in the
    # inbox until somebody remembered to type the command. A person still
    # merges the pull request; nothing here can.
    #
    # It decides only whether to publish, and leaves the publishing to
    # {Publication}, the same path the command takes, so the two cannot
    # drift: one branch shape, one secret scan, one push through
    # {Vcs::Publisher}, which declares it to {Execution::Boundary} first.
    class Autopromotion
      # What the end of the run did about memory.
      #
      # @!attribute [r] status
      #   @return [Symbol] `:published` or `:skipped`
      # @!attribute [r] url
      #   @return [String, nil] the pull request opened, or the open one that stopped this
      # @!attribute [r] lessons
      #   @return [Integer] the lessons the pull request carries
      # @!attribute [r] why
      #   @return [String, nil] why nothing was opened
      Outcome = Data.define(:status, :url, :lessons, :why)

      # A pull request is a memory one when its title says so, the way
      # {Publication} titles it, or its branch was cut by {Publication}.
      TITLE = /\AMemory:/

      # @param preview [#call] returns the {Promotion::Change}s a promotion would make, writing nothing
      # @param publication [#call] returns a {Publication::Result}
      # @param github [#pulls] asked for the open pull requests
      def initialize(preview:, publication:, github:)
        @preview = preview
        @publication = publication
        @github = github
      end

      # @return [OpenLanes::Memory::Autopromotion::Outcome]
      def call
        return skipped("no candidate in the inbox is eligible") if @preview.call.none? { Publication::LANDED.include?(it.kind) }

        # Skipped rather than updated: a second promotion cut from the
        # default branch cannot see the lessons the open one adds, so it would
        # mint the same L-NNNN ids for different lessons, and whichever pull
        # request merged second would collide with the first. The candidates
        # stay in the inbox and go out with the next run after the merge.
        open = open_memory_pull
        return skipped("memory pull request #{open[:url]} is still open; merge it first", url: open[:url]) if open

        published(@publication.call)
      end

      private

      # @return [Hash, nil] a row from {Vcs::GitHub#pulls}
      def open_memory_pull
        @github.pulls(state: "open").find { it[:branch].to_s.start_with?(Publication::BRANCH_PREFIX) || it[:title].to_s.match?(TITLE) }
      end

      # @param result [OpenLanes::Memory::Publication::Result]
      # @return [OpenLanes::Memory::Autopromotion::Outcome]
      def published(result)
        landed = result.changes.count { Publication::LANDED.include?(it.kind) }
        return Outcome.new(status: :published, url: result.url, lessons: landed, why: nil) if result.url

        skipped("nothing landed: #{result.held_back.size} held back by the secret scan")
      end

      # @return [OpenLanes::Memory::Autopromotion::Outcome]
      def skipped(why, url: nil) = Outcome.new(status: :skipped, url:, lessons: 0, why:)
    end
  end
end
