# frozen_string_literal: true

# Two API servers on two machines, sharing one in-memory Redis: each hub is
# stepped by hand, so every relay happens when the example says and the
# clock only moves when the example moves it.
RSpec.describe OpenLanes::Live::Chat do
  let(:store) { OpenLanes::Live.memory_store }
  let(:stores) { OpenLanes::Web::Stores.shared(store) }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "#{dana}:a1b2c3d4e5f6") }
  let(:dana) { "3f9a0c7be21d44a8f6031c5d" }
  let(:sam) { "77aa0c7be21d44a8f6031c99" }
  let(:now) { [100.0] }
  let(:clock) { -> { now.first } }
  let(:wall) { -> { Time.utc(2026, 10, 13, 9, 0, 0) } }
  let(:here) { described_class.new(stores:, keys:, machine: dana, label: "dana@studio", clock:, wall:) }
  let(:there) do
    described_class.new(stores:, keys: keys.with(node: "#{sam}:ffffffffffff"), machine: sam, label: "sam@ci", clock:, wall:)
  end
  let(:mine) { "page-dana-1" }
  let(:theirs) { "page-sam-1" }

  # Both hubs subscribe before anything is said, as servers do at start.
  before do
    here.step
    there.step
    here.attach(mine)
    there.attach(theirs)
  end

  def relay(times = 3) = times.times { [here, there].each(&:step) }

  def kinds(hub, page) = hub.drain(page).map { it[:kind] }

  def start
    started = here.start_chat(page: mine, name: "Dana", machine: sam, label: "sam@ci")
    relay
    started
  end

  def invite_id = there.state(page: theirs)[:invites].first[:id]

  def join_them
    start
    there.accept(page: theirs, invite: invite_id, name: "Sam")
    relay
  end

  describe "starting a chat" do
    it "joins the starter and invites the machine, whose pages see the invite" do
      started = start
      aggregate_failures do
        expect(started[:chat]).to match(described_class::UUID)
        expect(here.state(page: mine)[:chat]).to include(id: started[:chat], participants: [include(name: "Dana")])
        expect(there.drain(theirs)).to contain_exactly(include(kind: "invited", invite: include(from: include(name: "Dana"), chat: started[:chat])))
        expect(here.state(page: mine)[:outgoing]).to eq([{ id: invite_id, machine: sam, label: "sam@ci" }])
      end
    end

    it "tells the starter it joined" do
      start
      expect(kinds(here, mine)).to eq(["joined"])
    end

    it "refuses a name that is empty or too long, and a machine that is not one" do
      aggregate_failures do
        expect { here.start_chat(page: mine, name: "  ", machine: sam, label: "x") }.to raise_error(described_class::Invalid, /name is needed/)
        expect { here.start_chat(page: mine, name: "x" * 61, machine: sam, label: "x") }.to raise_error(described_class::Invalid, /at most 60/)
        expect { here.start_chat(page: mine, name: "Dana", machine: "nope", label: "x") }.to raise_error(described_class::Invalid, /machine id/)
        expect { here.start_chat(page: mine, name: "Dana", machine: dana, label: "x") }.to raise_error(described_class::Invalid, /itself/)
        expect { here.state(page: "../x") }.to raise_error(described_class::Invalid, /page must be/)
      end
    end
  end

  describe "answering an invite" do
    it "puts the accepting page in the chat, and everyone sees the join and the roster" do
      join_them
      aggregate_failures do
        expect(there.state(page: theirs)[:chat][:participants].map { it[:name] }).to contain_exactly("Dana", "Sam")
        expect(here.drain(mine).last).to include(kind: "joined", who: include(name: "Sam"))
        expect(here.state(page: mine)[:outgoing]).to eq([])
      end
    end

    it "lets the first answer win and closes the invite on every page of the machine" do
      there.attach("page-sam-2")
      start
      id = invite_id
      there.decline(page: theirs, invite: id)
      relay
      aggregate_failures do
        expect(there.drain("page-sam-2").last).to include(kind: "invite_closed", invite: id, answer: "declined")
        expect { there.accept(page: "page-sam-2", invite: id, name: "Sam") }.to raise_error(described_class::Settled)
        expect(here.drain(mine).last).to include(kind: "declined", machine: sam, label: "sam@ci")
      end
    end

    it "refuses an invite answered by another server for the same machine" do
      start
      store.set(keys.chat_answer(invite_id), "accepted", nx: true)
      expect { there.accept(page: theirs, invite: invite_id, name: "Sam") }.to raise_error(described_class::Settled, /already answered/)
    end

    it "expires after 60 seconds: the inviter hears it was not answered and the modals close" do
      start
      id = invite_id
      now[0] += described_class::INVITE_TTL
      relay
      aggregate_failures do
        expect(here.drain(mine).last).to include(kind: "unanswered", machine: sam, label: "sam@ci")
        expect(there.drain(theirs).last).to include(kind: "invite_closed", invite: id, answer: "expired")
      end
    end

    it "says at once that nobody answered when the machine has no page open" do
      there.detach(theirs)
      start
      expect(here.drain(mine).last).to include(kind: "unanswered", machine: sam)
    end

    it "says at once that nobody answered when nothing listens for the machine" do
      here.start_chat(page: mine, name: "Dana", machine: "0" * 24, label: "ghost@nowhere")
      expect(here.drain(mine).last).to include(kind: "unanswered", label: "ghost@nowhere")
    end

    it "accepting leaves the chat the page was in (D4)" do
      join_them
      first = there.state(page: theirs)[:chat][:id]
      here.attach("page-dana-2")
      here.start_chat(page: "page-dana-2", name: "Dee", machine: sam, label: "sam@ci")
      relay
      fresh = there.state(page: theirs)[:invites].find { it[:chat] != first }
      there.accept(page: theirs, invite: fresh[:id], name: "Sam")
      relay
      aggregate_failures do
        expect(here.drain(mine).map { it[:kind] }).to include("left")
        expect(here.state(page: mine)[:chat][:participants].map { it[:name] }).to eq(["Dana"])
      end
    end

    it "forgets an invite whose inviter went quiet" do
      start
      here.stop
      now[0] += described_class::INVITE_TTL + described_class::GRACE
      there.step
      expect(there.state(page: theirs)[:invites]).to eq([])
    end
  end

  describe "in a chat" do
    before do
      join_them
      here.drain(mine)
      there.drain(theirs)
    end

    it "relays a message to everyone, the sender included" do
      sent = here.say(page: mine, id: "01JMSG", text: "  see https://example.com\nthen\n")
      relay
      aggregate_failures do
        expect(sent).to include(id: "01JMSG", text: "see https://example.com\nthen", who: include(name: "Dana"))
        expect(there.drain(theirs)).to eq([{ kind: "said", chat: sent[:who] && here.state(page: mine)[:chat][:id],
                                             who: sent[:who], id: "01JMSG", text: sent[:text], at: "2026-10-13T09:00:00Z" }])
        expect(kinds(here, mine)).to eq(["said"])
      end
    end

    it "refuses an empty message, one over 4,000 characters, and a bad id" do
      aggregate_failures do
        expect { here.say(page: mine, id: "01J", text: " ") }.to raise_error(described_class::Invalid, /needs text/)
        expect { here.say(page: mine, id: "01J", text: "x" * 4001) }.to raise_error(described_class::Invalid, /4000/)
        expect { here.say(page: mine, id: "no way", text: "hi") }.to raise_error(described_class::Invalid, /id must/)
      end
    end

    it "accepts exactly 4,000 characters" do
      expect(here.say(page: mine, id: "01J", text: "x" * 4000)[:text].length).to eq(4000)
    end

    it "announces idle and back once each" do
      here.presence(page: mine, idle: true)
      here.presence(page: mine, idle: true)
      here.presence(page: mine, idle: false)
      relay
      aggregate_failures do
        expect(kinds(there, theirs)).to eq(%w[idle back])
      end
    end

    it "leaves on Stop Chat; the others carry on" do
      here.leave(page: mine)
      relay
      aggregate_failures do
        expect(there.drain(theirs)).to contain_exactly(include(kind: "left", who: include(name: "Dana"), participants: [include(name: "Sam")]))
        expect(here.state(page: mine)[:chat]).to be_nil
      end
    end

    it "counts a closed tab as leaving once the grace is over, and a reload as staying" do
      there.detach(theirs)
      now[0] += described_class::GRACE - 1
      relay
      there.attach(theirs)
      now[0] += described_class::GRACE
      relay
      expect(kinds(here, mine)).not_to include("left")
      there.detach(theirs)
      now[0] += described_class::GRACE
      relay
      expect(kinds(here, mine)).to include("left")
    end

    it "keeps the roster alive with heartbeats, and drops a participant whose server went quiet" do
      here.step
      there.step
      now[0] += described_class::HEARTBEAT
      relay
      expect(here.state(page: mine)[:chat][:participants].size).to eq(2)
      there.instance_variable_get(:@pages).clear
      now[0] += described_class::FORGET_AFTER
      here.step
      expect(here.drain(mine).last).to include(kind: "left", who: include(name: "Sam"))
    end

    it "lets any participant invite (D5), and requires being in a chat to do it" do
      aggregate_failures do
        expect(there.invite(page: theirs, machine: "1" * 24, label: "kim@x")).to include(label: "kim@x")
        expect { there.invite(page: "page-sam-9", machine: dana, label: "d") }.to raise_error(described_class::Invalid, /start a chat/)
        expect { there.say(page: "page-sam-9", id: "01J", text: "hi") }.to raise_error(described_class::Invalid, /not in a chat/)
      end
    end

    it "says goodbye for its pages when the server stops" do
      there.stop
      here.step
      expect(here.drain(mine).last).to include(kind: "left", who: include(name: "Sam"))
    end
  end

  it "ignores what is not a message, and rooms it has no page in" do
    store.publish(keys.chat_room("x", db: 0), "not json")
    store.publish(keys.chat_room("x", db: 0), JSON.generate(kind: "say", from: { id: "someone-else" }))
    store.publish(keys.chat_inbox(dana, db: 0), JSON.generate(kind: "invite", invite: { machine: "elsewhere" }))
    relay
    expect(here.drain(mine)).to eq([])
  end

  it "listens on a thread of its own" do
    hub = here.start
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    there.start_chat(page: theirs, name: "Sam", machine: dana, label: "dana@studio")
    sleep 0.01 until here.state(page: mine)[:invites].any? || Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time > 2
    expect(hub.state(page: mine)[:invites].size).to eq(1)
  ensure
    here.stop
  end
end
