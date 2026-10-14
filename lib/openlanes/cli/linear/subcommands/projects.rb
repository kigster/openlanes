# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes linear …`
    module Linear
      # `linear projects` — what the team already has.
      class Projects < Team
        desc "List the Linear projects a team owns, and which plans they already cover"

        example [
          "TAX        # every project the team owns, matched against .plans"
        ]

        # @param team [String]
        # @param options [Hash]
        # @return [void]
        def call(team:, **options)
          tree = tree_for(options).everything
          _api, survey = survey_for(team, tree)

          survey.projects.each { |project| puts row(project) }
          return if quiet?(options)

          survey.projects.each do |project|
            say("#{paint(project["name"], :cyan)}\n    #{paint(project["url"].to_s, :bright_black)}")
          end
          report_descriptions(survey)
        rescue OpenLanes::Error => e
          refuse(e.message, 69)
        end

        private

        # @param project [Hash]
        # @return [String]
        def row(project)
          [project["name"], project.dig("status", "name") || "-", project["url"]].join("\t")
        end

        # @param survey [OpenLanes::Linear::Survey]
        # @return [void]
        def report_descriptions(survey)
          return if survey.undescribed.empty?

          warn("#{survey.undescribed.size} of these say nothing about themselves:\n\n" \
               "#{survey.undescribed.map { |p| "  #{p["name"]}" }.join("\n")}\n\n" \
               "A name is three or four words and half of them are the company's. If you " \
               "want anything here to reason about which project a plan belongs to, that " \
               "reasoning has to have a sentence to read.")
        end
      end
    end
  end
end
