# Blocked, round 1 (technical)

The spec is several plans. A plan lands as one pull request with at most eight units, but this spec asks for one pull request per seam (A11): at least 14 seams by size (Dispatcher, Executor, PlanState, RunWorkflow, then documentation, ui, config, transcript, live/commands, prompt, live/chat, resync, verification/outcome, vcs/github), and more after them, because `.rubocop_todo.yml` holds 433 `Metrics/*` entries (AbcSize 118, MethodLength 168, ParameterLists 90, ClassLength 57). On top of those come the adapters-by-name, 23 files of `Thread.new`, the `Result` conversions, the `Judgment` port and the spans pull request, which A9 keeps separate. No `plan.md` written this round.

Already checked: dependencies 049.00 to 052.00 are all ✅ in `.plans/archive`, so `depends_on` stays as written. `semantic_logger` 5.1 and `concurrent-ruby` are in the gemspec already, and `opentelemetry-api` 1.11 is installed locally. `dry-monitor` is neither installed nor in the gemspec.

## B3 dry-monitor on Ruby 4.0.6

> **Answer not accepted:** There is no question. So I have no idea how to unblock you.
>
> unblocker: Journal round 1 entry 1 said B3 was answered. That was wrong: blocked.md still has B3 and A3, and the A3 text does not answer the question. B3 is open.

> **Answer not accepted:** There is no question here.
>
> unblocker left it unfolded and said nothing

A13 builds logs and spans on dry-monitor events. The latest release found is 1.0.1 (November 2022). It is not in the gemspec and is not installed here, so it is unconfirmed whether it installs on Ruby 4.0.6.

a) The spans plan tries dry-monitor 1.0.1 first, and falls back to the existing `EventBus` port from 038.00 if it does not install or pass the suite, saying which in its pull request. (Recommended)
b) Skip dry-monitor and build the instrumentation events on the existing `EventBus` port.
c) Use a maintained fork of dry-monitor, named by a person.


