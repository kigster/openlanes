# frozen_string_literal: true

require "digest"

RSpec.describe OpenLanes::Live::Node do
  subject(:node) { described_class.current(root:, user: "dana", host: "studio-mini", home:, ip: "10.0.4.12") }

  let(:home) { File.realpath(Dir.mktmpdir("openlanes-node")) }
  let(:root) { File.join(home, "src", "clone").tap { FileUtils.mkdir_p(it) } }

  after { FileUtils.rm_rf(home) }

  it "is named by digests of user@host and of the checkout" do
    aggregate_failures do
      expect(node.id).to eq(Digest::SHA256.hexdigest("dana@studio-mini")[0, 24])
      expect(node.checkout_id).to eq(Digest::SHA256.hexdigest(root)[0, 12])
      expect(node.name).to eq("#{node.id}:#{node.checkout_id}")
      expect(node.label).to eq("dana@studio-mini")
    end
  end

  it "shows the checkout under ~" do
    expect(node.checkout).to eq("~/src/clone")
  end

  it "leaves a path outside home as it is" do
    expect(described_class.tilde("/srv/clone", home)).to eq("/srv/clone")
  end

  it "goes on the wire as the page's Node" do
    expect(node.wire(heartbeat_at: Time.utc(2026, 10, 13, 9), me: false))
      .to eq(id: node.id,
        user: "dana",
        host: "studio-mini",
        ip: "10.0.4.12",
        checkout: "~/src/clone",
        heartbeat_at: "2026-10-13T09:00:00Z",
        me: false)
  end

  it "finds this machine's names when not told them" do
    expect(described_class.current(root:)).to have_attributes(user: described_class.login, host: Socket.gethostname)
  end

  it "reads an address that is not loopback, if the machine has one" do
    expect(described_class.address).to be_nil.or(match(/\A\d+\.\d+\.\d+\.\d+\z/))
  end
end
