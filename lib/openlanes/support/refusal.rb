# frozen_string_literal: true

module OpenLanes
  # Why a workflow would not do what it was asked, and the exit status that
  # says so. Every command workflow fails with one of these inside a
  # `Dry::Monads::Failure`, so the command that called it refuses the same
  # way whichever workflow said no. The statuses follow sysexits, as
  # {CLI::Base#refuse} documents.
  #
  # @!attribute [r] message
  #   @return [String] what the person reads in the error box
  # @!attribute [r] status
  #   @return [Integer] the exit status
  Refusal = Data.define(:message, :status)
end
