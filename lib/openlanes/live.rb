# frozen_string_literal: true

require "json"

module OpenLanes
  # The live run in Redis (plan 004): the engine publishes its board there
  # and reads the page's commands from there, and machines sharing one Redis
  # see each other's boards and never take each other's plans (W6, W13, W26).
  #
  # The engine builds a {Session}. The API server reads boards with {.board},
  # queues commands with {.enqueue} and follows answers with {.replies}, all
  # over the same {Keys}, so neither side spells a key.
  module Live
    # Where Redis is when nothing says otherwise (W16).
    DEFAULT_URL = "redis://localhost:6379/0"

    # Redis could not be reached, or stopped answering.
    class Unavailable < Error; end

    module_function

    # W16's order: `--redis-url`, then `.openlanes.yml`'s `redis_url:`, then
    # `$REDIS_URL`, then {DEFAULT_URL}.
    #
    # @param option [String, nil] what `--redis-url` typed
    # @param config [OpenLanes::Config]
    # @param env [Hash]
    # @return [String]
    def redis_url(option: nil, config: Config.current, env: ENV)
      [option, config.redis_url, env["REDIS_URL"]].map { it.to_s.strip }.find { !it.empty? } || DEFAULT_URL
    end

    # The address with any password replaced, for logs and the page.
    #
    # @param url [String]
    # @return [String]
    def mask(url) = url.to_s.sub(%r{\A([a-z][a-z0-9+.-]*://)([^:@/]*):[^@/]+@}i, '\1\2:***@')

    # The address with all of its userinfo replaced, user name included, for
    # a page anyone on the network can open. {.mask} keeps the user name
    # because a log read by the person who ran the engine is better for it; a
    # page shown on a shared screen is not.
    #
    # @param url [String]
    # @return [String] `redis://:***@host:6379/0`, or the URL as it was when
    #   it carries no userinfo
    def redact(url) = url.to_s.sub(%r{\A([a-z][a-z0-9+.-]*://)[^@/]*@}i, '\1:***@')

    # @param url [String]
    # @return [OpenLanes::Live::Store]
    def store(url) = Store.new(url:)

    # @return [OpenLanes::Live::MemoryStore]
    def memory_store(**) = MemoryStore.new(**)

    # A store that has answered, or the reason there is none.
    #
    # @param url [String]
    # @return [OpenLanes::Live::Store]
    # @raise [OpenLanes::Live::Unavailable]
    def connect(url)
      store = Store.new(url:)
      store.ping or raise Unavailable, "Redis at #{mask(url)} did not answer PING"
      store
    end

    # The process's {ChoiceJudge}: one, so its answers are shared by every
    # snapshot built here; nil without TYPESAFE_API_KEY, and nil in the suite.
    #
    # @return [OpenLanes::Live::ChoiceJudge, nil]
    def choice_judge
      return @choice_judge if defined?(@choice_judge)

      @choice_judge = ChoiceJudge.from_env
    end

    # @param judge [#call, nil] answers `call(text)` with true, false or nil
    # @return [void]
    def choice_judge=(judge)
      @choice_judge = judge
    end

    # The process's {ChoiceConverter}: nil without OPENROUTER_API_KEY, and
    # nil in the suite.
    #
    # @return [OpenLanes::Live::ChoiceConverter, nil]
    def choice_converter
      return @choice_converter if defined?(@choice_converter)

      @choice_converter = ChoiceConverter.from_env
    end

    # @param converter [#call, nil] answers `call(heading:, body:)` with a
    #   {ChoiceConverter::Result}
    # @return [void]
    def choice_converter=(converter)
      @choice_converter = converter
    end

    # The process's {Interviewer} (M6): nil without OPENROUTER_API_KEY, and
    # nil in the suite.
    #
    # @return [OpenLanes::Live::Interviewer, nil]
    def interviewer
      return @interviewer if defined?(@interviewer)

      @interviewer = Interviewer.from_env
    end

    # @param interviewer [#call, nil] answers `call(idea:)` with
    #   {Interviewer::Question}s
    # @return [void]
    def interviewer=(interviewer)
      @interviewer = interviewer
    end

    # @return [OpenLanes::Live::Session]
    def session(**) = Session.new(**)

    # The conversation with the run's copilot (W17), on +store+ under +keys+.
    #
    # @return [OpenLanes::Live::Copilot]
    def copilot(**) = Copilot.new(**)

    # This checkout's keys, for the API server beside its engine.
    #
    # @param root [String]
    # @return [OpenLanes::Live::Keys]
    def keys(root:, node: Node.current(root:)) = Keys.new(repo: Repo.for(root), node: node.name)

    # `Board` in `web/src/api/types.ts`: this node's snapshot and every other
    # live node's on the same repository. A node is live while its snapshot
    # key exists; one whose key has expired is left out.
    #
    # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
    # @param keys [OpenLanes::Live::Keys]
    # @return [Hash] `{me: Hash or nil, others: Array<Hash>}`, parsed JSON
    def board(store:, keys:)
      registered = store.hgetall(keys.nodes).keys
      snapshots = (registered | [keys.node]).to_h { |name| [name, store.get(keys.snapshot(name))] }.compact
      # A node is in the registry for as long as it heartbeats; one that died
      # without closing never takes itself out, so whoever reads prunes it.
      store.hdel(keys.nodes, *(registered - snapshots.keys))
      others = snapshots.except(keys.node).values.map { JSON.parse(it) }
      others.each { |snapshot| snapshot["node"]["me"] = false }
      { me: snapshots[keys.node]&.then { JSON.parse(it) }, others: others.sort_by { it.dig("node", "host").to_s } }
    end

    # Queue one command for this node's engine.
    #
    # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
    # @param keys [OpenLanes::Live::Keys]
    # @param input [Hash, String] a `Command`
    # @return [OpenLanes::Live::Reply] accepted
    # @raise [OpenLanes::Live::Command::Invalid] for the API server's 422
    def enqueue(store:, keys:, input:)
      command = Command.parse(input)
      store.xadd(keys.commands, { json: JSON.generate(command.wire) })
      Reply.new(id: command.id, status: "accepted")
    end

    # Replies after +after+, oldest first, with the stream id of each so the
    # caller can carry on from the last.
    #
    # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
    # @param keys [OpenLanes::Live::Keys]
    # @param after [String] a stream id, "0" for all kept, "$" for new only
    # @param block [Integer, nil] milliseconds to wait for one
    # @return [Array<Array(String, Hash)>] stream id and the `Reply`
    def replies(store:, keys:, after: "$", block: nil)
      store.xread(keys.replies, id: after, block:).map { |entry| [entry.id, JSON.parse(entry.fields["json"])] }
    end
  end
end
