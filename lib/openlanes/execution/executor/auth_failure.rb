# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What each CLI says when it will not authenticate.
      module AuthFailure
        # claude's expired OAuth session and `/login` prompt, codex and pi's
        # missing login, gemini's own wording, and a provider's rejected key.
        PATTERN = Regexp.union(/OAuth (?:session|token) (?:has )?expired/i,
          /not (?:signed|logged) in/i,
          %r{Please run .?/?login}i,
          /Error authenticating/,
          /Invalid API key/i,
          /authentication_error/,
          /401 Unauthorized/i)
      end
    end
  end
end
