# frozen_string_literal: true

# Slack, as far as a poll goes: one workspace, messages by timestamp, the
# reactions on each and the replies under it. It is the transport
# {OpenLanes::Slack::API} takes, so every example drives the real API class
# and nothing reaches the network.
class FakeSlack
  BOT = "UBOT"

  # Slack's methods, and the private method here that plays each.
  ROUTES = {
    "auth.test"             => :identity,
    "chat.postMessage"      => :post,
    "chat.update"           => :update,
    "reactions.add"         => :react,
    "reactions.get"         => :reacted,
    "conversations.replies" => :thread,
    "users.info"            => :user
  }.freeze

  def initialize(team: "Acme", team_id: "T0ACME", url: "https://acme.slack.com/")
    @identity = { "ok" => true, "team" => team, "team_id" => team_id, "url" => url, "user" => "openlanes", "user_id" => BOT }
    @messages = {}
    @calls = []
    @refusals = {}
    @refused_at = {}
    @clock = 1_700_000_000
    @bare = false
  end

  # @return [Array<Array(String, Hash)>] every call made, in order
  attr_reader :calls

  # @return [Hash{String => Hash}] messages by timestamp
  attr_reader :messages

  # @return [OpenLanes::Slack::API]
  def api = OpenLanes::Slack::API.new(transport: method(:call))

  # Make +method+ fail with Slack's +code+ until {#allow} is called.
  def refuse(method, code) = @refusals[method] = code

  def allow(method) = @refusals.delete(method)

  # Make every call about the message at +stamp+ fail with +code+, as
  # Slack refuses one message (`cant_update_message`, `msg_too_long`).
  def refuse_at(stamp, code) = @refused_at[stamp] = code

  # A person deletes the message: every call about it is then
  # `message_not_found`, as Slack answers.
  def delete(stamp) = @messages.delete(stamp)

  # conversations.replies leaves the reactions off, as an app without the
  # history scope's full view would see.
  def bare! = @bare = true

  # A person clicks a reaction.
  def click(stamp, name, user: "UDANA") = (@messages.fetch(stamp)["reactions"][name] ||= []) << user

  # A person replies in the thread.
  def say(parent, text, user: "UDANA") = @messages.fetch(parent)["replies"] << { "user" => user, "text" => text, "ts" => stamp }

  def called(method) = @calls.select { |name, _| name == method }.map(&:last)

  # @return [Array<String>] timestamps of the top-level messages, oldest first
  def posts = @messages.select { |_, m| m["thread_ts"].nil? }.keys

  # @return [String] everything a message's blocks say
  def text_of(stamp) = JSON.parse(@messages.fetch(stamp)["blocks"]).map { |b| b.dig("text", "text") || b["elements"].map { it["text"] }.join }.join("\n")

  def call(method, params)
    params = params.transform_keys(&:to_s)
    @calls << [method, params]
    return { "ok" => false, "error" => @refusals[method] } if @refusals.key?(method)

    about = params["ts"] || params["timestamp"] unless params["thread_ts"]
    return { "ok" => false, "error" => @refused_at[about] } if about && @refused_at.key?(about)
    return { "ok" => false, "error" => "message_not_found" } if about && !@messages.key?(about)

    route = ROUTES[method] or return { "ok" => false, "error" => "unknown_method" }
    send(route, params)
  end

  private

  def identity(_params) = @identity

  def reacted(params) = { "ok" => true, "message" => { "reactions" => reactions(params["timestamp"]) } }

  def user(params) = { "ok" => true, "user" => { "id" => params["user"], "real_name" => "Dana Okafor" } }

  def stamp = "#{@clock += 1}.000100"

  def post(params)
    if params["thread_ts"]
      @messages.fetch(params["thread_ts"])["replies"] << { "bot_id" => "B1", "user" => BOT, "text" => params["text"], "ts" => stamp }
      return { "ok" => true, "channel" => "C0QUESTIONS", "ts" => stamp }
    end
    ts = stamp
    @messages[ts] = { "text" => params["text"], "blocks" => params["blocks"], "reactions" => {}, "replies" => [] }
    { "ok" => true, "channel" => "C0QUESTIONS", "ts" => ts }
  end

  def update(params)
    @messages.fetch(params["ts"]).merge!("text" => params["text"], "blocks" => params["blocks"])
    { "ok" => true }
  end

  def react(params)
    users = (@messages.fetch(params["timestamp"])["reactions"][params["name"]] ||= [])
    return { "ok" => false, "error" => "already_reacted" } if users.include?(BOT)

    users << BOT
    { "ok" => true }
  end

  def reactions(stamp) = @messages.fetch(stamp)["reactions"].map { |name, users| { "name" => name, "users" => users.dup, "count" => users.size } }

  def thread(params)
    message = @messages.fetch(params["ts"])
    parent = { "ts" => params["ts"], "user" => BOT, "bot_id" => "B1", "text" => message["text"] }
    parent["reactions"] = reactions(params["ts"]) unless @bare || message["reactions"].empty?
    { "ok" => true, "messages" => [parent, *message["replies"]] }
  end
end
