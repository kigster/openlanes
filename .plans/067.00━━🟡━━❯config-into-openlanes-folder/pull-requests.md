# Pull Requests

## Checks run by backend-coder, round 3

- `bundle exec rubocop`: 1002 files inspected, no offenses detected
- `rg -n '\.openlanes\.yml' lib`: only `lib/openlanes/support/project.rb` (`LEGACY_FILE` and the comment beside it)
- `git check-ignore .openlanes/config.yml .openlanes/x`: exit 1, nothing under `.openlanes/` is ignored
- `bundle exec rspec spec/integration/config_folder_spec.rb`: 4 examples, 0 failures
- `bundle exec rspec`: 6670 examples, 0 failures, 10 pending, exit 0
