# frozen_string_literal: true

module OpenLanes
  module Setup
    class ArchitectureScan
      # What gives each attribute's value away. Tables rather than logic, so
      # adding a tool is one line. Every value is a member of
      # {Architecture::ATTRIBUTES}, which a spec holds to.
      module Markers
        # Folders that are never a monorepo's project.
        NOT_PROJECTS = %w[node_modules vendor tmp log coverage dist build public].freeze

        # Attribute → value → globs, relative to the root.
        FILES = {
          task_runners: { just: %w[justfile Justfile .justfile], rake: %w[Rakefile], make: %w[Makefile],
                          taskfile: %w[Taskfile.yml Taskfile.yaml], mise: %w[mise.toml .mise.toml] },
          dev_start:    { mprocs: %w[mprocs.yaml mprocs.yml], overmind: %w[.overmind.env], foreman: %w[Procfile.dev],
                          bin_dev: %w[bin/dev], docker_compose: %w[compose.y*ml docker-compose.y*ml] },
          secrets:      { sopsy:             %w[.env.encrypted .env.*.encrypted],
                          rails_credentials: %w[config/credentials.yml.enc config/credentials/*.yml.enc],
                          dotenv:            %w[.env .env.example .env.sample] },
          env_loading:  { direnv: %w[.envrc], mise: %w[mise.toml .mise.toml] },
          deployment:   { kubernetes: %w[k8s helm charts], fly: %w[fly.toml], render: %w[render.yaml],
                          heroku: %w[app.json Procfile], vercel: %w[vercel.json .vercel], gem: %w[*.gemspec] },
          testing:      { rspec: %w[.rspec], minitest: %w[test/test_helper.rb], vitest: %w[vitest.config.*],
                          jest: %w[jest.config.*], cypress: %w[cypress.config.*], playwright: %w[playwright.config.*],
                          pytest: %w[pytest.ini conftest.py] }
        }.freeze

        # Attribute → value → package names, in any manifest.
        DEPENDENCIES = {
          frameworks:      { rails: %w[rails], sinatra: %w[sinatra], hanami: %w[hanami], next: %w[next], astro: %w[astro],
                             vite: %w[vite], fastapi: %w[fastapi], django: %w[django] },
          front_end:       { react: %w[react], vue: %w[vue], svelte: %w[svelte],
                             hotwire: %w[turbo-rails @hotwired/turbo] },
          persistence:     { postgresql: %w[pg psycopg psycopg2 psycopg2-binary], mysql: %w[mysql2 mysql],
                             sqlite: %w[sqlite3], mongodb: %w[mongoid mongodb mongoose] },
          caching:         { redis: %w[redis], memcached: %w[dalli memcached] },
          logins:          { password: %w[devise bcrypt], oauth: %w[omniauth doorkeeper next-auth],
                             saml: %w[ruby-saml omniauth-saml] },
          testing:         { rspec: %w[rspec rspec-core], vitest: %w[vitest], jest: %w[jest], cypress: %w[cypress],
                             playwright: %w[playwright @playwright/test], pytest: %w[pytest] },
          background_jobs: { sidekiq: %w[sidekiq], solid_queue: %w[solid_queue], resque: %w[resque], celery: %w[celery],
                             temporal: %w[temporalio @temporalio/client] },
          messaging:       { kafka: %w[karafka ruby-kafka kafkajs], rabbitmq: %w[bunny amqplib], sqs: %w[aws-sdk-sqs shoryuken] },
          search:          { elasticsearch: %w[elasticsearch], opensearch: %w[opensearch-ruby], meilisearch: %w[meilisearch],
                             pgvector: %w[pgvector neighbor] },
          observability:   { opentelemetry: %w[opentelemetry-sdk @opentelemetry/sdk-node], datadog: %w[ddtrace datadog dd-trace],
                             new_relic: %w[newrelic_rpm newrelic], sentry: %w[sentry-ruby @sentry/node sentry-sdk],
                             honeycomb: %w[honeycomb-beeline] },
          api_styles:      { graphql: %w[graphql graphql-ruby apollo-server], grpc: %w[grpc @grpc/grpc-js grpcio] }
        }.freeze
      end
    end
  end
end
