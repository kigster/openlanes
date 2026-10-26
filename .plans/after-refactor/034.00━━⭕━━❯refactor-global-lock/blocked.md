# Blocked — 034.00, backend-coder round 1 (technical)

## B1 The suite cannot go green while gems are being reinstalled

> **Answer not accepted:** Add debug_inspector gem to the Gemfile. And why are dependent on agentilda at all?
>
> unblocker: blocked.md B1 heading lacks the ' - ' separator used in the spec; numbering is already B1/A1, so no renumbering needed

The implementation requirement says `bundle exec rspec` must exit 0. Every in-process spec passes, the new ones included (733 examples across the touched areas), and `bundle exec rubocop` reports no offenses. The full suite still ends with 6 failures. All of them are specs that spawn `exe/openlanes` as a subprocess (`spec/integration/mail_round_trip_spec.rb:133,145`, `spec/integration/review_labels_spec.rb:121,189`, `spec/openlanes/integration/plan_dependencies_spec.rb:34,43,60`), and each one dies before any openlanes code runs, with `Bundler::GemNotFound: debug_inspector-1.2.0`, `LoadError: pastel/alias_importer`, or `LoadError: dry/cli/usage`. The cause is a concurrent `gem install agentilda -N` (pid 75308) rewriting `~/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0`. The set of failing examples changes from run to run.

a) Stop whatever keeps reinstalling gems, run `bundle pristine && bundle exec rspec` once, and send the plan on if it is green. (Recommended)
b) Accept the six subprocess failures as environmental and send the plan to review as it is.
c) Hold the plan until the machine is idle, then run backend-coder again.
