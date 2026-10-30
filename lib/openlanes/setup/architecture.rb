# frozen_string_literal: true

require "dry-struct"
require "dry-types"

module OpenLanes
  module Setup
    # What one codebase is built from, as closed lists of symbols. The scan,
    # the extraction and the form all fill this one structure, so the form's
    # options, the LLM's schema and the file's validation cannot disagree.
    #
    # A value outside a list is `:other`, and its name goes in `notes`.
    class Architecture < Dry::Struct
      # The dry-types module these attributes are typed from.
      module Types
        include Dry.Types(default: :strict)
      end

      # What most questions ask: the repository today, and what is wanted.
      DEFAULT_WORDING = ["what does this repository use today?", "what should it use?"].freeze

      # The attributes a general question would read badly for.
      WORDING = {
        layout:       ["is this repository one application or library at its top level, like a Rails or Django app, " \
                       "or a monorepo holding several projects?",
                       "should it be one application or library at its top level, or a monorepo holding several projects?"],
        projects:     ["which folders hold its projects? Separate them with commas.",
                       "which folders should hold its projects? Separate them with commas."],
        task_runners: ["how are tasks such as lint, test and build run around this repository today?",
                       "how should people and agents run tasks such as lint, test and build?"],
        dev_start:    ["how is the application started in development today?",
                       "how should the application start in development?"],
        secrets:      ["how are development secrets kept today?",
                       "how should development secrets be kept?"],
        env_loading:  ["how do those secrets reach the environment today?",
                       "how should those secrets reach the environment when someone enters the project?"]
      }.freeze

      # What the WANTED questions preselect when neither the description nor
      # the scan says anything. Only a person's answer records one, so `-y`
      # never writes a recommendation down as a decision.
      RECOMMENDED = { task_runners: %i[just], dev_start: %i[mprocs], secrets: %i[sopsy], env_loading: %i[direnv] }.freeze

      # A Rails application has its own encrypted secrets, so it keeps them.
      RAILS_RECOMMENDED = { secrets: %i[rails_credentials] }.freeze

      # How much a person chose to say; each attribute belongs to the lowest
      # detail that asks it.
      DETAILS = %i[low medium high].freeze

      # One attribute: its name, the detail that first asks it, its choices.
      #
      # `kind` is :many (a multi-select, the usual case), :one (a single
      # select) or :paths (free text naming folders, so `values` is empty).
      Attribute = Data.define(:name, :detail, :values, :kind) do
        def initialize(name:, detail:, values:, kind: :many) = super

        # @return [String] the words a question uses for it
        def label = { ci: "CI", dev_start: "Development start", env_loading: "Environment loading" }.fetch(name) { name.to_s.tr("_", " ").capitalize }

        # @return [String] what a question asks about the repository today
        def prompt_now = WORDING.fetch(name, DEFAULT_WORDING).first

        # @return [String] what a question asks about the repository wanted
        def prompt_wanted = WORDING.fetch(name, DEFAULT_WORDING).last
      end

      # Every attribute, in the order the form asks them.
      ATTRIBUTES = [
        Attribute.new(:layout, :low, %i[single_application library monorepo other], :one),
        Attribute.new(:projects, :low, [], :paths),
        Attribute.new(:languages, :low, %i[ruby node go rust elixir python other]),
        Attribute.new(:frameworks, :low, %i[rails sinatra hanami next astro vite fastapi django other none]),
        Attribute.new(:task_runners, :low, %i[just rake make npm_scripts taskfile mise other none]),
        Attribute.new(:dev_start, :low, %i[mprocs overmind foreman bin_dev docker_compose just_recipe npm_scripts other none]),
        Attribute.new(:secrets, :low, %i[sopsy rails_credentials dotenv one_password vault cloud_secrets_manager other none]),
        Attribute.new(:env_loading, :low, %i[direnv mise dotenv_library shell_profile other none]),
        Attribute.new(:ci, :low, %i[github_actions circleci jenkins gitlab buildkite external none]),
        Attribute.new(:deployment, :low, %i[kubernetes fly render heroku vercel aws gcp azure gem other none]),
        Attribute.new(:front_end, :medium, %i[react vue svelte hotwire native other none]),
        Attribute.new(:persistence, :medium, %i[postgresql mysql sqlite mongodb files other none]),
        Attribute.new(:caching, :medium, %i[redis memcached cdn other none]),
        Attribute.new(:logins, :medium, %i[password oauth saml magic_link api_key other none]),
        Attribute.new(:testing, :medium, %i[rspec minitest vitest jest cypress playwright pytest other none]),
        Attribute.new(:background_jobs, :high, %i[sidekiq solid_queue resque celery temporal other none]),
        Attribute.new(:messaging, :high, %i[kafka rabbitmq sqs redis_streams other none]),
        Attribute.new(:search, :high, %i[postgresql_fts elasticsearch opensearch meilisearch pgvector other none]),
        Attribute.new(:observability, :high, %i[opentelemetry datadog new_relic sentry honeycomb other none]),
        Attribute.new(:api_styles, :high, %i[rest graphql grpc sse websockets other none]),
        Attribute.new(:data_classes, :high, %i[money pii health_records other none])
      ].freeze

      transform_keys(&:to_sym)

      ATTRIBUTES.each do |item|
        member = item.kind == :paths ? Types::String : Types::Coercible::Symbol.enum(*item.values)
        attribute item.name, item.kind == :one ? member.optional.default(nil) : Types::Array.of(member).default([].freeze)
      end

      attribute :notes, Types::Strict::String.default("")

      # A key outside the lists is a typo in a file, not something to ignore.
      schema schema.strict

      # What a WANTED question preselects when nothing better is known.
      #
      # @param frameworks [Array<Symbol>] the frameworks answered so far
      # @return [Hash{Symbol => Array<Symbol>}]
      def self.recommended(frameworks) = frameworks.include?(:rails) ? RECOMMENDED.merge(RAILS_RECOMMENDED) : RECOMMENDED

      # @param name [Symbol] an attribute's name
      # @return [Array<Symbol>] what it may hold
      def self.values(name) = ATTRIBUTES.find { it.name == name }.values

      # @param detail [Symbol] one of {DETAILS}
      # @return [Array<OpenLanes::Setup::Architecture::Attribute>] what that detail asks
      def self.asked_at(detail)
        reach = DETAILS.index(detail)
        ATTRIBUTES.select { DETAILS.index(it.detail) <= reach }
      end

      # @return [Boolean] whether nothing is known
      def blank? = to_file.empty?

      # @return [Hash{String => Object}] answered attributes only, in the file's shape
      def to_file
        to_h.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }.to_h do |key, value|
          [key.to_s, if value.is_a?(Array)
                       value.map(&:to_s)
                     else
                       (value.is_a?(Symbol) ? value.to_s : value)
                     end]
        end
      end
    end
  end
end
