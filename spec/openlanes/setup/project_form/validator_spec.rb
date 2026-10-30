# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::ProjectForm::Validator do
  subject(:validator) { described_class.new }

  def errors(id, input) = validator.validate(Struct.new(:id).new(id), input).errors

  {
    [:project, "Acme"]              => false,
    [:project, "  "]                => true,
    [:jobs, nil]                    => false,
    [:jobs, 3]                      => false,
    [:jobs, 0]                      => true,
    [:current_projects, "web, api"] => false,
    [:target_projects, "../other"]  => true,
    [:target_projects, "/etc"]      => true,
    [:target_projects, "~/x"]       => true,
    [:target_ci, %w[circleci]]      => false
  }.each do |(id, input), refused|
    it "#{refused ? "refuses" : "takes"} #{input.inspect} for #{id}" do
      expect(errors(id, input).empty?).to be(!refused)
    end
  end
end
