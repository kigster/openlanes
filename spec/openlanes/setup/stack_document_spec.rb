# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::StackDocument do
  let(:stack) { OpenLanes::Setup::Stack }

  it "renders every field of a full stack, one line each" do
    full = stack.new(language: "ruby",
      frameworks: %w[rails sidekiq],
      front_end: "react",
      persistence: "postgres",
      caching: "redis",
      logins: "devise",
      deployment: "fly.io",
      domain: "payroll")
    expect(described_class.new(full).render).to include(
      "- **Language:** ruby",
      "- **Frameworks:** rails, sidekiq",
      "- **Front end:** react",
      "- **Persistence:** postgres",
      "- **Caching:** redis",
      "- **Logins:** devise",
      "- **Deployment:** fly.io",
      "- **Domain:** payroll"
    )
  end

  it "omits blank fields of a sparse stack" do
    text = described_class.new(stack.new(language: "go")).render
    expect([text.include?("- **Language:** go"), text.include?("Frameworks"), text.include?("## Port")])
      .to eq([true, false, false])
  end

  it "adds a port section when from and to are set" do
    text = described_class.new(stack.new(language: "ruby", from: "sinatra", to: "rails")).render
    expect(text).to include("## Port", "from sinatra to rails")
  end

  it "writes docs/decisions/stack.md, creating the directory" do
    root = Dir.mktmpdir("openlanes-stackdoc")
    path = described_class.new(stack.new(language: "rust")).write(root)
    expect([path, File.read(path)]).to eq([File.join(root, "docs/decisions/stack.md"),
                                           described_class.new(stack.new(language: "rust")).render])
  ensure
    FileUtils.rm_rf(root)
  end
end
