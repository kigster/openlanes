# frozen_string_literal: true

require "digest"
require "fileutils"

module OpenLanes
  module Engine
    # The dispatcher's half of D9: an open question in a blocked plan's
    # `blocked.md` that offers no choices is sent to the {Live::ChoiceConverter}
    # and, once the model has answered, rewritten in place into D3's shape, so
    # the page, lando-broker and everything else read the same options.
    #
    # The call runs on a thread of its own, like a drain, and its result is
    # applied on a later tick, where the folder is looked up afresh. Nothing is
    # written when the question changed meanwhile, was answered, or the plan
    # was taken by another machine or another job.
    #
    # Each text is sent once. A rewrite, or an answer the model gave that is
    # not a D3 question, is recorded in the plan's `state.json` under the
    # SHA256 of the text, so a restarted run does not pay for it again. A call
    # that failed (no network, a 4xx, a timeout) is remembered only for this
    # process: the next run may well get through.
    class Conversions
      # One question sent to the model.
      Job = Struct.new(:ordinal, :number, :digest, :original, :thread)

      # @param converter [#call, nil] a {Live::ChoiceConverter}; nil converts nothing
      # @param runner [OpenLanes::Engine::Runner]
      # @param find [#call] an ordinal to the plan's {Plans::Subject} as the
      #   folder is now, nil when it is gone
      def initialize(converter:, runner:, find:)
        @converter = converter
        @runner = runner
        @find = find
        @jobs = []
        @sent = []
      end

      # @return [Array<String>] plans with a question at the model right now
      def ordinals = @jobs.map(&:ordinal)

      # Apply what came back, then send what has not been sent.
      #
      # @param busy [Array<String>] plans nobody but their holder may touch
      # @param start [Boolean] false applies answers and sends nothing new
      # @return [void]
      def call(busy:, start: true)
        return if @converter.nil?

        @jobs.reject { it.thread.alive? }.each { settle(it, busy) }
        return unless start

        @runner.blocked.each do |subject|
          ordinal = subject.feature.ordinal.to_s
          next if busy.include?(ordinal)

          prose(subject).each do |question, body|
            next unless @runner.claim(subject)

            send_off(ordinal, question, body)
          end
        end
      end

      private

      # Open questions with a body and no choices in it, not yet sent.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<Array(Lifecycle::Unblocker::Question, String)>]
      def prose(subject)
        bodies = Plans::BlockedFile.bodies(subject.read("blocked.md").to_s)
        state = Plans::PlanState.for(subject.feature.path)
        Lifecycle::Unblocker.questions(subject).reject(&:answered).filter_map do |question|
          body = bodies.fetch(question.number, "").strip
          next if body.empty? || question.heading.match?(Plans::Choices::YES_NO) || Plans::Choices.parse(body)

          digest = Digest::SHA256.hexdigest(body)
          next if @sent.include?(digest) || state.converted?(digest)

          [question, body]
        end
      end

      # @return [void]
      def send_off(ordinal, question, body)
        digest = Digest::SHA256.hexdigest(body)
        @sent << digest
        job = Job.new(ordinal:, number: question.number, digest:, original: body)
        heading = question.heading
        job.thread = Thread.new do
          Thread.current.report_on_exception = false
          @converter.call(heading:, body:)
        rescue StandardError => e
          e
        end
        @jobs << job
      end

      # @param job [Job]
      # @param busy [Array<String>]
      # @return [void]
      def settle(job, busy)
        @jobs.delete(job)
        outcome = job.thread.value
        subject = @find.call(Plans::Ordinal.parse(job.ordinal))
        return couldnt(job, "the plan's folder is gone") if subject.nil?
        return couldnt(job, "the plan was taken meanwhile") if busy.include?(job.ordinal)

        case outcome
        when Live::ChoiceConverter::Result then apply(job, subject, outcome)
        when Live::ChoiceConverter::Invalid then reject(job, subject, outcome)
        else couldnt(job, outcome.message.lines.first.to_s.strip)
        end
      end

      # @return [void]
      def apply(job, subject, result)
        path = File.join(subject.feature.path, "blocked.md")
        text = subject.read("blocked.md").to_s
        open = Lifecycle::Unblocker.questions(subject).find { it.number == job.number && !it.answered }
        current = Plans::BlockedFile.bodies(text).fetch(job.number, "").strip
        return couldnt(job, "it changed or was answered while the model was writing") if !open || current != job.original

        write(path, Plans::BlockedFile.replace(text, job.number, result.body))
        Plans::PlanState.for(subject.feature.path).conversion!(question: job.number,
          digest: job.digest,
          original: job.original,
          model: result.model,
          outcome: "converted")
        UI.log("questions: converted B#{job.number} to #{result.count} choices", plan: job.ordinal)
      end

      # @return [void]
      def reject(job, subject, error)
        Plans::PlanState.for(subject.feature.path).conversion!(question: job.number,
          digest: job.digest,
          original: job.original,
          model: @converter.model,
          outcome: "rejected",
          note: error.message)
        couldnt(job, error.message)
      end

      # @return [void]
      def couldnt(job, why) = UI.log("questions: could not convert B#{job.number}: #{why}", level: :warn, plan: job.ordinal)

      # A reader never sees half a file.
      #
      # @return [void]
      def write(path, text)
        tmp = "#{path}.#{Process.pid}.tmp"
        File.write(tmp, text)
        File.rename(tmp, path)
      ensure
        FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
      end
    end
  end
end
