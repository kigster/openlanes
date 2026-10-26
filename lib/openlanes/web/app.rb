# frozen_string_literal: true

require "ipaddr"
require "json"
require "rack/utils"
require "sinatra/base"

module OpenLanes
  module Web
    # The routes of contract.md, "HTTP". One subclass per server, built by
    # {.serving}, carries that server's {Context} as a setting, so two apps in
    # one process (the suite) never share a token or a store.
    class App < Sinatra::Base
      # Host headers the server always answers: loopback, so a page on another
      # site cannot reach it through DNS rebinding. A server listening beyond
      # this machine adds its own addresses and name ({Listen#permitted_hosts}).
      LOCAL_HOSTS = ["localhost", IPAddr.new("127.0.0.0/8"), IPAddr.new("::1")].freeze

      # What `/` says when the page was never built.
      UNBUILT = <<~HTML
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>openlanes: page not built</title></head>
        <body><h1>The control room page is not built</h1>
        <p>Run <code>just web-build</code> first, then reload.</p></body></html>
      HTML

      configure do
        set :environment, :production
        set :show_exceptions, false
        set :raise_errors, false
        set :dump_errors, false
        set :logging, false
        set :static, true
        set :static_cache_control, [:public, { max_age: 3600 }]
        # Rack::Protection's defaults (frame options, origin check on writes,
        # JSON CSRF, path traversal, IP spoofing, XSS header), answering 403.
        # Sinatra's own reaction is to drop the session and carry on, which
        # with no session is no reaction at all. The token is the guard the
        # session would otherwise have been.
        set :protection, except: %i[remote_token], reaction: :deny
        set :host_authorization, { permitted_hosts: LOCAL_HOSTS }
      end

      class << self
        # @param context [OpenLanes::Web::Context]
        # @return [Class] a subclass serving that context
        def serving(context)
          Class.new(self) do
            use AdminAuth, credentials: context.credentials if context.credentials
            set :context, context
            set :host_authorization, { permitted_hosts: LOCAL_HOSTS + context.listen.permitted_hosts }
            set :public_folder, context.dist
          end
        end
      end

      helpers do
        # @return [OpenLanes::Web::Context]
        def context = settings.context

        # @return [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
        def store = context.store

        # @return [OpenLanes::Live::Copilot]
        def copilot = Live.copilot(store:, keys: context.keys, responder: context.copilot)

        # Answer +turn+ apart from this request, on a store of its own,
        # since a Redis connection is never shared between threads.
        #
        # @param turn [OpenLanes::Live::Copilot::Turn]
        # @return [void]
        def answer_later(turn)
          context.background.call do
            Live.copilot(store: context.stores.current, keys: context.keys, responder: context.copilot).answer(turn)
          ensure
            context.stores.release
          end
        end

        # @return [OpenLanes::Web::PlanFiles]
        def plan_files = PlanFiles.new(plans_dir: context.plans_dir)

        # The rule the page draws cars by: this machine's board lists the
        # plan with at least one car. No snapshot means no engine, so no car.
        #
        # @param ordinal [String] e.g. "017.00"
        # @return [Boolean]
        def live_car?(ordinal)
          plans = Live.board(store:, keys: context.keys).dig(:me, "plans") || []
          plans.any? { it["ordinal"].to_s == ordinal && Array(it["cars"]).any? }
        end

        # @return [OpenLanes::Live::Chat]
        def chat = context.chat || halt(404, json(error: "this server has no chat"))

        # The request's JSON object, or a 422.
        #
        # @return [Hash]
        def body_json
          data = JSON.parse(request.body.read)
          data.is_a?(Hash) ? data : halt(422, json(error: "the body is a JSON object"))
        rescue JSON::ParserError => e
          halt 422, json(error: "not JSON: #{e.message.lines.first.to_s.strip}")
        end

        # Another machine on the board, as `user@host`, so an invite names
        # who it went to and is only sent to a machine that is there.
        #
        # @param id [String] a node id
        # @return [String]
        def machine_label(id)
          node = Live.board(store:, keys: context.keys)[:others].map { it["node"] }.find { it["id"] == id }
          node ? "#{node["user"]}@#{node["host"]}" : halt(422, json(error: "no machine #{id} is on this Redis now"))
        end

        # @param data [Object]
        # @return [String]
        def json(data)
          content_type :json
          JSON.generate(data)
        end

        # @return [Boolean]
        def csrf? = Rack::Utils.secure_compare(request.env["HTTP_X_CSRF_TOKEN"].to_s, context.csrf)

        # The machine this server speaks for, as the engine last described
        # it, so the session and the board never disagree about who "me" is.
        #
        # @return [Hash, nil]
        def node
          snapshot = store.get(context.keys.snapshot)
          return JSON.parse(snapshot)["node"] if snapshot

          context.node&.wire(heartbeat_at: Time.now)
        end

        # @param body [String]
        # @return [String] the command's id when it has a usable one
        def id_in(body)
          id = JSON.parse(body)["id"].to_s
          id.match?(Live::Command::ID) ? id : ""
        rescue JSON::ParserError, TypeError, NoMethodError
          ""
        end
      end

      before "/api/*" do
        cache_control :no_store
      end

      error PlanFiles::NotFound do
        status 404
        json(error: env["sinatra.error"].message)
      end

      error PlanFiles::ReadOnly do
        status 403
        json(error: env["sinatra.error"].message)
      end

      error PlanFiles::Stale do
        status 412
        json(error: env["sinatra.error"].message)
      end

      error PlanFiles::FrontmatterChanged do
        status 422
        json(error: env["sinatra.error"].message)
      end

      error Live::Unavailable do
        status 503
        json(error: env["sinatra.error"].message)
      end

      get "/healthz" do
        store.ping
        content_type :text
        "ok #{Live.mask(context.url)}\n"
      end

      get "/api/session" do
        json(csrf: context.csrf, node:, repo: context.keys.repo)
      end

      get "/api/board" do
        json(Live.board(store:, keys: context.keys))
      end

      get "/api/events" do
        content_type "text/event-stream"
        headers "Cache-Control" => "no-cache, no-transform", "X-Accel-Buffering" => "no"
        events = Events.new(context:, store:, last_id: request.env["HTTP_LAST_EVENT_ID"], page: params[:page])
        stream { |out| events.run(out) }
      end

      post "/api/commands" do
        body = request.body.read
        halt 403, json(error: "X-CSRF-Token does not match; fetch /api/session again") unless csrf?

        reply = Live.enqueue(store:, keys: context.keys, input: body)
        status 202
        json(reply.wire)
      rescue Live::Command::Invalid => e
        status 422
        json(Live::Reply.new(id: id_in(body), status: "refused", reason: e.message).wire)
      end

      # The Preview tab's toolbar (plan 012): Restart backend, a named
      # restart, or Stop, for the `openlanes app start` running that plan's
      # app. Queued on the app runner's stream, not the engine's: the engine
      # never runs an app, so it would never read them.
      post "/api/apps/commands" do
        halt 403, json(error: "X-CSRF-Token does not match; fetch /api/session again") unless csrf?

        data = body_json
        plan = Plans::Ordinal.parse(data["plan"].to_s)&.to_s or halt 422, json(error: "plan must be a plan number like 012.00")
        action = data["action"].to_s
        halt 422, json(error: "action must be one of #{Apps::Runner::ACTIONS.join(", ")}") unless Apps::Runner::ACTIONS.include?(action)
        target = data["target"]
        unless target.nil? || target.to_s.match?(Apps::Definition::NAME)
          halt 422, json(error: "target must be backend or a process name")
        end

        command = { plan:, action:, target: }
        Live::EventBus.for(store).append(context.keys.app_commands, { json: JSON.generate(command) }, maxlen: Apps::Runner::COMMANDS_LENGTH)
        status 202
        json(command)
      end

      # The interview a new idea gets before its spec is written (M6). No
      # interviewer, or one that failed, is not an error: the page gets no
      # questions and a reason, and creates the plan as it always has.
      post "/api/interview" do
        halt 403, json(error: "X-CSRF-Token does not match; fetch /api/session again") unless csrf?

        idea = body_json["idea"].to_s.strip
        halt 422, json(error: "interview needs an idea") if idea.empty?

        interviewer = Live.interviewer
        next json(questions: [], reason: "no interviewer: OPENROUTER_API_KEY is not set") unless interviewer

        begin
          json(questions: interviewer.call(idea:).map(&:wire))
        rescue StandardError => e
          json(questions: [], reason: "the interviewer failed: #{e.message.lines.first.to_s.strip}")
        end
      end

      get "/api/copilot" do
        json(copilot.history)
      end

      # The person's message to the copilot (W17). It is stored and accepted
      # at once; the answer is written afterwards, apart from this request,
      # and comes on the event stream as `event: copilot`, like a command's
      # replies do. The answer is copilot's ({Context#copilot}), except
      # for a slash command (plan 020.00), which the engine answers.
      post "/api/copilot" do
        halt 403, json(error: "X-CSRF-Token does not match; fetch /api/session again") unless csrf?

        turn = copilot.say(request.body.read)
        answer_later(turn) unless turn.slash?
        status 202
        json(turn.wire)
      rescue Live::Copilot::Invalid => e
        status 422
        json(error: e.message)
      rescue Live::Copilot::Unanswered => e
        status 503
        json(error: e.message)
      end

      # The chat between machines (plan 006): this page's chat, the invites
      # open to this machine, and the ones this page waits on.
      get "/api/chat" do
        json(chat.state(page: params[:page]))
      rescue Live::Chat::Invalid => e
        status 422
        json(error: e.message)
      end

      # What a page does in a chat. Everyone hears of it as `event: chat`
      # on their own stream, this page included.
      post "/api/chat/:action" do
        halt 403, json(error: "X-CSRF-Token does not match; fetch /api/session again") unless csrf?

        data = body_json
        page = data["page"]
        machine = data["machine"].to_s
        answer = case params[:action]
                 when "start" then chat.start_chat(page:, name: data["name"], machine:, label: machine_label(machine))
                 when "invite" then chat.invite(page:, machine:, label: machine_label(machine))
                 when "accept" then chat.accept(page:, invite: data["invite"].to_s, name: data["name"])
                 when "decline" then chat.decline(page:, invite: data["invite"].to_s).then { {} }
                 when "leave" then chat.leave(page:).then { {} }
                 when "say" then chat.say(page:, id: data["id"], text: data["text"])
                 when "presence" then chat.presence(page:, idle: data["idle"]).then { {} }
                 else halt 404, json(error: "no such chat action: #{params[:action]}")
                 end
        status 202
        json(answer)
      rescue Live::Chat::Invalid => e
        status 422
        json(error: e.message)
      rescue Live::Chat::Settled => e
        status 409
        json(error: e.message)
      end

      # Demo only: the board back to the fixture, for a test that wants a
      # known start. A real engine's run has no such thing.
      post "/api/demo/reset" do
        halt 404, json(error: "no such endpoint") unless context.demo
        halt 403, json(error: "X-CSRF-Token does not match; fetch /api/session again") unless csrf?

        context.demo.reset
        status 204
      end

      # The plan files (plan 017). The page may read six names and write
      # two; {PlanFiles} holds both lists and every guard but the car, so a
      # name is never joined onto a path as typed.
      get "/api/plans/:ordinal/files" do
        json(files: plan_files.list(params[:ordinal]))
      end

      get "/api/plans/:ordinal/files/:name" do
        file = plan_files.read(params[:ordinal], params[:name])
        headers "ETag" => file.etag
        content_type "text/markdown", charset: "utf-8"
        file.body
      end

      # A whole file, saved from the popup. The car is checked here rather
      # than in {PlanFiles}, since the board is this server's to read: an
      # agent working the plan would overwrite the save, or be overwritten.
      put "/api/plans/:ordinal/files/:name" do
        halt 403, json(error: "X-CSRF-Token does not match; fetch /api/session again") unless csrf?

        ordinal, name = params.values_at(:ordinal, :name)
        plan_files.read(ordinal, name)
        halt 403, json(error: "#{name} is read only") unless PlanFiles::EDITABLE.include?(name)

        if_match = request.env["HTTP_IF_MATCH"].to_s.strip
        halt 428, json(error: "If-Match is required; send the ETag from GET") if if_match.empty?

        number = Plans::Ordinal.parse(ordinal).to_s
        halt 409, json(error: "#{number} has an agent working on it; wait until it stops") if live_car?(number)

        tag = plan_files.write(ordinal, name, body: request.body.read, if_match:)
        headers "ETag" => tag
        json(etag: tag)
      end

      get "/api/*" do
        halt 404, json(error: "no such endpoint")
      end

      # Every other path is the page's own route: the page decides what it
      # means. A path naming a file is not one, so a missing asset is a 404
      # rather than the page served as JavaScript.
      get "/*" do
        halt 404, { "Content-Type" => "text/plain" }, "not found\n" unless File.extname(request.path_info).empty?
        halt 503, { "Content-Type" => "text/html; charset=utf-8" }, UNBUILT unless context.dist?

        cache_control :no_cache
        send_file context.index
      end
    end
  end
end
