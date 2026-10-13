# frozen_string_literal: true

require "openlanes/linear/mapping"

module OpenLanes
  # `.plans` as Linear projects and issues.
  #
  # The folders already are a tracker: a number, a state, a set of pull
  # requests and a document saying why. What they are not is visible to anyone
  # who does not have the repository checked out, which is most of the people
  # who want to know how a piece of work is going. This exports to Linear so
  # that audience can see it, and it exports *one way* — the folder is the
  # truth, Linear is the window.
  #
  # Four pieces, in the order a run uses them:
  #
  #   {Units}   reads `plan.md` and finds the work units inside a plan
  #   {Import}  decides, from disk alone, what would be created or updated
  #   {Push}    applies that through {API} and records what it did
  #   {Issues}  is the record, `linear.md`, that makes the next run idempotent
  #
  # {Import} touches nothing but the filesystem, which is what makes the dry
  # run trustworthy: it is not a description of what a push would do, it is
  # the object the push consumes.
  module Linear
    # Team keys are what Linear puts in front of every issue number.
    KEY = /\A[A-Z][A-Z0-9]{1,9}\z/

    # @param prefix [String, nil]
    # @return [String] the normalised team key
    # @raise [OpenLanes::Error] when it could never be one
    def self.key!(prefix)
      key = prefix.to_s.strip.upcase
      return key if key.match?(KEY)

      raise Error,
        "#{prefix.inspect} is not a Linear team key. A key is 2–10 characters, " \
        "letters and digits, as in TAX or ENG — the part before the dash in TAX-41."
    end
  end
end
