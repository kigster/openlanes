# frozen_string_literal: true

# `Config#to_yaml` writes every key the schema knows, most of them empty.
# Specs about one setting care about what was set, so this reads a written
# file back without what the writer filled in: an empty value, a value equal
# to its schema default, and a mapping left with nothing else set.
module SettingsIn
  # @param yaml [String] a written `.openlanes.yml`
  # @return [Hash{String => Object}] only what was set
  def settings_in(yaml)
    set_only(YAML.safe_load(yaml, permitted_classes: [Date]) || {}, OpenLanes::Config::Schema.defaults)
  end

  private

  # @param settings [Hash]
  # @param defaults [Hash, nil]
  # @return [Hash]
  def set_only(settings, defaults)
    settings.each_with_object({}) do |(key, value), kept|
      default = defaults.is_a?(Hash) ? defaults[key] : nil
      next if value.nil? || (!default.nil? && value == default)

      if value.is_a?(Hash) && !value.empty?
        inner = set_only(value, default)
        kept[key] = inner unless inner.empty?
      else
        kept[key] = value
      end
    end
  end
end
