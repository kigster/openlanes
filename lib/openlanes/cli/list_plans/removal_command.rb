# frozen_string_literal: true

require "tty-prompt"

module OpenLanes
  module CLI
    # `plans abandon`, `plans discard` and `plans trash`: the same command three
    # times, differing in the state it moves to and how it asks why.
    class RemovalCommand < Base
      # @param to [Symbol] one of {Plans::REMOVED}
      # @param verb [String] the participle the questions use
      # @param choices [Array<String>, nil] nil asks for free text
      # @return [void]
      def self.removes(to, verb, choices: nil)
        define_method(:target) { to }
        define_method(:verb) { verb }
        define_method(:choices) { choices }

        argument :ids, type: :array, required: true, desc: "Plan numbers: 003 or 003.00"
        option :reason, type: :string, desc: "The reason, for every plan listed; asks each plan's otherwise"
        dry_run_option "Move nothing; print what would move and be rewritten"
        example ["003 007", "003 --reason \"built outside OpenLanes\"", "-n 003"]
      end

      # @param ids [Array<String>]
      # @param options [Hash]
      # @return [void]
      def call(ids: [], **options)
        tree = tree_for(options).everything
        subjects = resolve(tree, ids)
        result = OpenLanes::Lifecycle.removal(tree:, to: target).call(reasons(subjects, options), dry_run: dry_run?(options))
        report(result, options)
        exit 1 unless result.refused.empty?
      end

      private

      # @return [Array<OpenLanes::Plans::Subject>] all of them, or a refusal before anything moved
      def resolve(tree, ids)
        found = ids.uniq.to_h { [it, tree.find(it)] }
        unknown = found.select { |_, subject| subject.nil? }.keys
        refuse("No such plan: #{unknown.join(", ")}. Nothing was moved.", 65) unless unknown.empty?
        found.values.uniq { it.feature.ordinal.to_s }
      end

      # A dry run moves nothing, so it has no use for a reason and never asks.
      #
      # @return [Hash{String => String}] canonical ordinal => reason
      def reasons(subjects, options)
        given = options[:reason]
        refuse("--reason may not be blank. Nothing was moved.", 64) if given && given.strip.empty?
        return for_all(subjects, given.to_s) if given || dry_run?(options)

        unless tty?
          refuse("No terminal to ask on, so pass --reason. Nothing was moved.", 64)
        end
        interviewed(subjects)
      end

      # @return [Hash{String => String}]
      def for_all(subjects, reason) = subjects.to_h { [it.feature.ordinal.to_s, reason] }

      # A plan already there keeps the reason it has, so it is not asked for one.
      #
      # @return [Hash{String => String}]
      def interviewed(subjects)
        to_ask = subjects.reject { it.status.key == target }
        answers = OpenLanes::Lifecycle.reason_interview(prompt:, verb:, choices:).ask(to_ask)
        for_all(subjects, "").merge(answers)
      rescue TTY::Reader::InputInterrupt
        refuse("Interrupted. Nothing was moved.", 130)
      end

      # @param result [OpenLanes::Lifecycle::Removal::Result]
      # @return [void]
      def report(result, options)
        report_changes(result)
        result.open_prs.each { |ordinal, numbers| report_open(ordinal, numbers) }
        report_unmoved(result)
        dry_run_footer(result.moved.size, "move#{"s" unless result.moved.size == 1}") if dry_run?(options)
      end

      # @return [void]
      def report_unmoved(result)
        result.skipped.each { say("#{it} is already #{Plans.status(target).label}; its reason stays as written.") }
        result.refused.each { |ordinal, why| error("#{ordinal} was not moved: #{why}") }
      end

      # @return [void]
      def report_changes(result)
        result.moved.each { puts "#{it.ordinal}\t#{it.from} → #{it.to}\t#{it.title}" }
        result.edits.each { puts "depends_on\t#{it}" }
      end

      # @return [void]
      def report_open(ordinal, numbers)
        puts "open\t#{ordinal}\t#{numbers.join(", ")}"
        warn("#{ordinal} still has open pull requests: #{numbers.join(", ")}.\n" \
             "Close them first, or expect a rename conflict or a second folder with this number when one merges.")
      end

      # @return [Boolean]
      def tty? = $stdin.tty? && $stderr.tty?

      # @return [OpenLanes::Setup::SpacedPrompt]
      def prompt = @prompt ||= OpenLanes::Setup::SpacedPrompt.new(TTY::Prompt.new(output: $stderr), out: $stderr)
    end
  end
end
