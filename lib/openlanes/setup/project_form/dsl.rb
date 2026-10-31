# frozen_string_literal: true

# The questions `openlanes init` asks. This file is the form: the terminal runs
# it through inquirex-tty, and `Definition#to_json` hands the same steps to the
# inquirex-webui and inquirex-widget front ends.
#
# Its answers fill two Setup::Architecture snapshots, serialized under
# `architecture_decisions:` in `.openlanes.yml`: what the repository holds now,
# and what the person wants.
#
# It holds no per-run data, so it stays one valid graph. The scan and the
# extraction preselect answers as renderer defaults, so a person can change any
# of them. Only a flag typed on the command line is prefilled, which skips its
# step. `greenfield` is prefilled when the scan found nothing, so an empty
# folder is not asked what it holds now.
#
# Question text is not wrapped here: each front end wraps it to its own width.
architecture = OpenLanes::Setup::Architecture
attributes = architecture::ATTRIBUTES
quality = OpenLanes::Engine::QualityQuestion

Inquirex.define id: "openlanes-init", version: "2.0.0" do
  # A step's own label for a choice is the choice's words.
  choices = ->(values) { values.to_h { [it.to_s, it.to_s.tr("_", " ")] } }

  # Skipped when the person chose less detail than the attribute needs.
  too_detailed = lambda do |attribute|
    below = architecture::DETAILS.take(architecture::DETAILS.index(attribute.detail))
    below.map { equals(:detail, it.to_s) }
  end

  # Sub-project paths only mean something in a monorepo.
  not_a_monorepo = lambda do |attribute, section|
    next [] unless attribute.kind == :paths

    (architecture::ATTRIBUTES.first.values - %i[monorepo]).map { equals(:"#{section}_layout", it.to_s) }
  end

  # The step type and the wording each kind of attribute asks with.
  step_type = { one: :enum, many: :multi_enum, paths: :string }

  meta title: "OpenLanes project setup",
    subtitle: "What this repository holds now, and what you want it to become"

  start :detail

  ask :detail do
    type :enum
    question "How much detail do you want to give about what you are building?"
    options "low"    => "Low: #{architecture.asked_at(:low).size} topics",
      "medium" => "Medium: #{architecture.asked_at(:medium).size} topics",
      "high"   => "High: #{architecture.asked_at(:high).size} topics"
    default "medium"
    transition to: :description
  end

  ask :description do
    type :text
    question "Describe what you are building, in your own words. Anything you mention is preselected " \
             "in the questions that follow, and you can change it. Leave it blank to skip."
    required false
    skip_if equals(:no_extraction, true)
    transition to: :understanding
  end

  extract :understanding do
    from :description
    prompt OpenLanes::Setup::Extractor::PROMPT
    schema(*attributes.map { :"target_#{it.name}" }, :merge_by, :desired_codebase_quality)
    transition to: :"current_#{attributes.first.name}"
  end

  # -- NOW: what the scan found, preselected --------------------------------------

  attributes.each_with_index do |attribute, index|
    following = attributes[index + 1]
    ask :"current_#{attribute.name}" do
      type step_type.fetch(attribute.kind)
      question "NOW, #{attribute.label}: #{attribute.prompt_now}"
      options choices.call(attribute.values) unless attribute.kind == :paths
      required false
      skip_if any(equals(:greenfield, true), *too_detailed.call(attribute), *not_a_monorepo.call(attribute, :current))
      transition to: following ? :"current_#{following.name}" : :keep_current
    end
  end

  confirm :keep_current do
    question "Is what this repository uses today also what you want?"
    default true
    skip_if equals(:greenfield, true)
    transition to: :merge_by, if_rule: equals(:keep_current, true)
    transition to: :"target_#{attributes.first.name}"
  end

  # -- WANTED: preselected from the description, else from NOW --------------------

  attributes.each_with_index do |attribute, index|
    following = attributes[index + 1]
    ask :"target_#{attribute.name}" do
      type step_type.fetch(attribute.kind)
      question "WANTED, #{attribute.label}: #{attribute.prompt_wanted}"
      options choices.call(attribute.values) unless attribute.kind == :paths
      required false
      skip_if any(*too_detailed.call(attribute), equals(:keep_current, true), *not_a_monorepo.call(attribute, :target))
      transition to: following ? :"target_#{following.name}" : :migration
    end
  end

  ask :migration do
    type :enum
    question "How should the existing code reach what you want?"
    options "port"  => "Port the existing code",
      "fresh" => "Start fresh beside it"
    skip_if equals(:greenfield, true)
    transition to: :merge_by
  end

  # -- How the project runs -------------------------------------------------------

  ask :merge_by do
    type :enum
    question "Who merges a reviewed pull request?"
    options OpenLanes::Config::MERGERS.map(&:to_s)
    default OpenLanes::Config::MERGERS.first.to_s
    transition to: :desired_codebase_quality
  end

  ask :desired_codebase_quality do
    type :enum
    question "#{quality::HEADING}. #{quality::BODY}"
    options(quality::CHOICES.to_h { [it.quality.to_s, it.label] })
    default OpenLanes::Setup::Interview::DEFAULT_QUALITY.to_s
    required false
    transition to: :project
  end

  ask :project do
    type :string
    question "Project name:"
    transition to: :starts
  end

  ask :starts do
    type :enum
    question "Where a new plan starts:"
    options OpenLanes::Plans::Spec::STARTS.map(&:to_s)
    default OpenLanes::Plans::Spec::STARTS.first.to_s
    transition to: :jobs
  end

  ask :jobs do
    type :integer
    question "Plans to run at once (blank: cores - 2):"
    required false
  end
end
