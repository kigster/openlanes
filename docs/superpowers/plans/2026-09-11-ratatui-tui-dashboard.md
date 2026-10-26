# Ratatui TUI Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in `--tui ratatui` rendering backend for `agentilda run`'s live dashboard, built on the `ratatui_ruby` gem, alongside the existing `--tui spinner` (today's `Screen`) default.

**Architecture:** `Board` (pure data, built once a second by `Dispatcher`), `Console` (selection/dialog state, calls `screen.draw(board)`), and `Keyboard` (reads keys, calls methods on `Console`) are unchanged and shared by both backends. `ratatui_ruby` insists on owning a blocking render+input loop of its own, so the new `Screen::Ratatui` runs that loop on a dedicated thread, reads whatever `Board` `#draw` last stored, and forwards translated key events to a `Keyboard` instance that was built with `.new` (never `.start`, so it never spawns a second stdin reader).

**Tech Stack:** Ruby 4.0, `ratatui_ruby` 1.5.0 (native Rust extension via `rb_sys`/`magnus`), RSpec, `RatatuiRuby::TestHelper::TestDoubles` for widget-tree assertions without a real terminal.

**Spec:** `docs/superpowers/specs/2026-09-11-ratatui-tui-dashboard-design.md`

## Global Constraints

- Default backend stays `spinner` (today's `Screen`); nothing changes for a run that doesn't pass `--tui ratatui`.
- `ratatui_ruby` is a hard gemspec runtime dependency — no fallback path for a missing/broken install.
- `--tui ratatui|spinner` flag on `agentilda run`; `AGENTILDA_TUI` env var is the fallback when the flag isn't passed; flag wins when both are set.
- A `Table` widget's cells only accept text content (`String`, `Text::Span`, `Text::Line`, `Paragraph`, a single buffer `Cell`) — never another widget. Elapsed/time-left render as a hand-built colored block-bar (`▓▓▓░░░`) inside a `Text::Line` cell, not a real `LineGauge` widget (confirmed against the gem's actual RBS and Rust source; a real `LineGauge` cannot live inside a table row in ratatui at all).
- Color rules: agent name bold yellow always. Elapsed bar: green under 15 minutes, yellow at/over 15 minutes. Time-left bar: green over 15 minutes remaining, yellow under 15 minutes, red under 5 minutes, dim/empty when there is no timeout.
- `RatatuiRuby::TableState` is the single source of truth for row selection/scroll in the ratatui backend — `Console`'s own `@selected` (a row key) stays authoritative; `render` recomputes `table_state.select(index)` from it every frame rather than letting arrow keys drive `table_state` directly, so the two selection mechanisms never fight.
- **Environment gotcha, verified on this machine:** a Ruby built `--with-jemalloc` (as an rbenv/ruby-build install commonly is on macOS with Homebrew) fails to compile `ratatui_ruby`'s native extension with `fatal error: 'jemalloc/jemalloc.h' file not found`, because `rb-sys`'s bindgen step doesn't inherit `CPPFLAGS`/`CFLAGS`. The fix is `BINDGEN_EXTRA_CLANG_ARGS="-I/opt/homebrew/include" gem install ratatui_ruby` (or `bundle install`). This must be documented (Task 1) or every contributor on a jemalloc-linked Ruby hits a hard, confusing `bundle install` failure.

---

### Task 1: Gemspec dependency and the jemalloc build gotcha

**Files:**
- Modify: `agentilda.gemspec`
- Modify: `README.md` (a short "Troubleshooting" or "Requirements" note — check the file first for the right section; if none fits, add one near installation instructions)

**Interfaces:**
- Produces: `ratatui_ruby` becomes a loadable gem for every later task in this plan.

- [ ] **Step 1: Add the dependency**

In `agentilda.gemspec`, alongside the other `spec.add_dependency` lines (alphabetical order, matching the existing list):

```ruby
  spec.add_dependency "ratatui_ruby"
```

- [ ] **Step 2: Install and confirm the build, documenting the gotcha if hit**

```bash
eval "$(rbenv init -)" && bundle install
```

If this fails with `fatal error: 'jemalloc/jemalloc.h' file not found`, confirm your Ruby was built with jemalloc:

```bash
ruby -e 'puts RbConfig::CONFIG["MAINLIBS"]'   # look for -ljemalloc
```

If it is, retry with:

```bash
BINDGEN_EXTRA_CLANG_ARGS="-I/opt/homebrew/include" bundle install
```

(swap `/opt/homebrew/include` for wherever `jemalloc.h` actually resolves, e.g. `brew --prefix jemalloc` on Intel Macs is `/usr/local/opt/jemalloc`).

- [ ] **Step 3: Document it**

Add a short note to `README.md` (find the installation/requirements section and add a subsection, or add one if none exists):

```markdown
### Building on a jemalloc-linked Ruby

If `bundle install` fails compiling `ratatui_ruby` with
`fatal error: 'jemalloc/jemalloc.h' file not found`, your Ruby was built
`--with-jemalloc` and `rb-sys`'s bindgen step isn't inheriting your
compiler's include path. Fix:

    BINDGEN_EXTRA_CLANG_ARGS="-I$(brew --prefix jemalloc)/include" bundle install

Put it in `.envrc` if you hit this more than once.
```

- [ ] **Step 4: Verify the gem loads**

```bash
eval "$(rbenv init -)" && bundle exec ruby -e 'require "ratatui_ruby"; puts RatatuiRuby::VERSION'
```

Expected: prints `1.5.0` (or whatever version `bundle install` resolved), no error.

- [ ] **Step 5: Commit**

```bash
git add agentilda.gemspec Gemfile.lock README.md
git commit -m "Add ratatui_ruby as a runtime dependency"
```

---

### Task 2: Extend the live data model — `elapsed` and `subagents`

`Board::Row` (the live, per-agent snapshot `Dispatcher` hands to a screen every tick) currently carries `remaining` (seconds until timeout) but not `elapsed` (seconds since start), and carries no sub-agent count at all — both needed by the ratatui table's "elapsed" bar and "subs" column. `Dispatcher::Job` already tracks `started_at`; it needs a `subagents` slot fed the same way `up`/`down` already are, from `Transcript::Progress#subagents`.

**Files:**
- Modify: `lib/agentilda/board.rb`
- Modify: `lib/agentilda/dispatcher.rb`
- Test: `spec/agentilda/dispatcher_spec.rb`

**Interfaces:**
- Produces: `Agentilda::Engine::Board::Row#elapsed` (Integer, seconds, default `0`), `Agentilda::Engine::Board::Row#subagents` (Integer, default `0`).

- [ ] **Step 1: Write the failing test**

Find the existing `describe "the 020.00 regression"` block (or any block building a running job) in `spec/agentilda/dispatcher_spec.rb` and check how a job's `board.rows.first` is asserted on elsewhere in the file (mirror that fixture setup). Add:

```ruby
it "carries elapsed seconds and the live sub-agent count on a running row" do
  travel_to = ->(seconds) { allow(Agentilda::UI).to receive(:monotonic).and_return(seconds) }
  travel_to.call(1000.0)
  dispatcher = described_class.new(runner: runner, sleeper: ->(_) {})
  dispatcher.tick # dispatches whatever the fixture tree makes eligible

  travel_to.call(1042.0)
  row = dispatcher.board.rows.find(&:running?)
  expect(row.elapsed).to eq(42)
  expect(row.subagents).to eq(0)
end
```

This uses whatever `runner`/`:tree` fixture the surrounding spec file already defines — check the top of `spec/agentilda/dispatcher_spec.rb` for the `let(:runner)` and tree fixture in scope, and place this example inside a `describe` block that already has a dispatchable plan (do not invent a new fixture; reuse the file's existing `PlansFixture` tree).

- [ ] **Step 2: Run it to verify it fails**

```bash
eval "$(rbenv init -)" && bundle exec rspec spec/agentilda/dispatcher_spec.rb -e "carries elapsed seconds"
```

Expected: `NoMethodError: undefined method 'elapsed'` or `expected 0.0 to eq 42` — `Board::Row` has no such attribute yet.

- [ ] **Step 3: Add the fields to `Board::Row`**

In `lib/agentilda/board.rb`, the `Board::Row` definition:

```ruby
  Board::Row = Data.define(:key,
    :at,
    :ordinal,
    :file,
    :agent,
    :role,
    :round,
    :rounds,
    :model,
    :remaining,
    :phase,
    :up,
    :down,
    :message,
    :state,
    :pr,
    :frame,
    :bold,
    :elapsed,
    :subagents) do
    def initialize(pr: nil, phase: nil, remaining: nil, frame: 0, bold: false, message: nil,
      elapsed: 0, subagents: 0, **rest) = super

    # @return [Boolean]
    def running? = state == :running
  end
```

- [ ] **Step 4: Add `subagents` to `Dispatcher::Job` and populate both fields**

In `lib/agentilda/dispatcher.rb`, the `Job` struct:

```ruby
    Job = Struct.new(:key,
      :task,
      :thread,
      :handle,
      :started_at,
      :file,
      :status,
      :message,
      :up,
      :down,
      :subagents,
      :result,
      :from,
      :state,
      :frame) do
      # @return [Boolean]
      def finished? = !thread.alive?
    end
```

In `#start`, the `Job.new(...)` call and the progress callback:

```ruby
      job = Job.new(key: "#{ordinal}/#{agent.name}",
        task:,
        handle:,
        started_at: UI.monotonic,
        from:,
        state: subject.status.key,
        up: 0,
        down: 0,
        subagents: 0,
        frame: 0)
```

```ruby
          @runner.executor.call(agent, subject, root: task.root, round:, successor:, handle:, partners:) { |progress|
            job.up = progress.up
            job.down = progress.down
            job.subagents = progress.subagents
            job.message = progress.message || progress.activity
          }
```

In `#row_for`:

```ruby
    def row_for(job)
      task = job.task
      job.frame = job.frame.to_i + 1
      Board::Row.new(key: job.key,
        at: Time.now,
        ordinal: task.subject.feature.ordinal.to_s,
        file: job.file || task.agent.ledger.first.to_s,
        agent: task.agent.name,
        role: task.agent.role,
        round: task.round,
        rounds: rounds_for(task.agent),
        model: model_for(task.agent),
        remaining: job.handle.remaining,
        phase: job.handle.phase,
        up: job.up.to_i,
        down: job.down.to_i,
        message: job.message,
        state: :running,
        pr: pr_for(task),
        frame: job.frame,
        elapsed: (UI.monotonic - job.started_at).round,
        subagents: job.subagents.to_i)
    end
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
eval "$(rbenv init -)" && bundle exec rspec spec/agentilda/dispatcher_spec.rb
```

Expected: the new example passes; every pre-existing example in this file still passes (this file has known-unrelated failures from `Agentilda.plan_dirname` on this branch — confirm your change added zero *new* failures by comparing the failing-example list before and after, not just "PASS" on the one you added).

- [ ] **Step 6: Commit**

```bash
git add lib/agentilda/board.rb lib/agentilda/dispatcher.rb spec/agentilda/dispatcher_spec.rb
git commit -m "Track elapsed seconds and live sub-agent count on Board::Row"
```

---

### Task 3: `Screen::Ratatui::Bar` — the colored duration bar

A pure, terminal-free helper: given a duration in seconds and a color, builds a `Text::Line` of two colored `Text::Span`s (a block-character fill, then the clock text) — the stand-in for a `LineGauge` inside a table cell. Also owns the color-threshold rules from the spec.

**Files:**
- Create: `lib/agentilda/screen/ratatui/bar.rb`
- Test: `spec/agentilda/screen/ratatui/bar_spec.rb`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `Agentilda::Presentation::Screen::Ratatui::Bar.cell(tui, seconds, color) -> RatatuiRuby::Text::Line`, `.elapsed_color(elapsed) -> Symbol`, `.remaining_color(remaining) -> Symbol`. Task 5's `render` calls all three.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true

require "ratatui_ruby"

RSpec.describe Agentilda::Presentation::Screen::Ratatui::Bar do
  let(:tui) { RatatuiRuby::TUI.new }

  describe ".cell" do
    it "fills proportionally to the 30-minute cap and appends the clock" do
      line = described_class.cell(tui, 900, :green) # 15 of 30 minutes = half full
      bar, clock = line.spans
      expect(bar.content).to eq(("▓" * 5) + ("░" * 5))
      expect(bar.style.fg).to eq(:green)
      expect(clock.content).to eq(" 15:00")
    end

    it "draws an empty, dim bar with no clock when there is no duration" do
      line = described_class.cell(tui, nil, :green)
      bar, clock = line.spans
      expect(bar.content).to eq(" " * 10)
      expect(clock.content).to eq(" --:--")
      expect(bar.style.fg).to eq(:bright_black)
    end

    it "never exceeds a full bar past the 30-minute cap" do
      line = described_class.cell(tui, 5000, :red)
      bar, = line.spans
      expect(bar.content).to eq("▓" * 10)
    end
  end

  describe ".elapsed_color" do
    it "is green under 15 minutes" do
      expect(described_class.elapsed_color(899)).to eq(:green)
    end

    it "is yellow at 15 minutes and over" do
      expect(described_class.elapsed_color(900)).to eq(:yellow)
    end
  end

  describe ".remaining_color" do
    it "is red under 5 minutes" do
      expect(described_class.remaining_color(299)).to eq(:red)
    end

    it "is yellow under 15 minutes" do
      expect(described_class.remaining_color(899)).to eq(:yellow)
    end

    it "is green at 15 minutes and over" do
      expect(described_class.remaining_color(900)).to eq(:green)
    end

    it "is dim with no timeout" do
      expect(described_class.remaining_color(nil)).to eq(:bright_black)
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
eval "$(rbenv init -)" && bundle exec rspec spec/agentilda/screen/ratatui/bar_spec.rb
```

Expected: `NameError: uninitialized constant Agentilda::Presentation::Screen::Ratatui` — nothing exists yet.

- [ ] **Step 3: Implement**

```ruby
# frozen_string_literal: true

require "ratatui_ruby"

module Agentilda
  class Screen
    # ratatui_ruby's Table widget only accepts text content per cell —
    # never a widget — so a real LineGauge cannot live inside a table row.
    # This builds the visual equivalent by hand: a fixed-width block-character
    # fill plus the clock text, as a two-span Text::Line.
    class Ratatui
      module Bar
        # Cells the fill portion occupies.
        WIDTH = 10

        # Seconds a bar visually maxes out at. Cosmetic only — the color
        # thresholds below are independent, absolute-minute rules.
        CAP = 1800

        # @param tui [RatatuiRuby::TUI]
        # @param seconds [Integer, nil] nil draws an empty, dim bar
        # @param color [Symbol] the fill's foreground color
        # @return [RatatuiRuby::Text::Line]
        def self.cell(tui, seconds, color)
          return empty(tui) if seconds.nil?

          filled = ((seconds.to_f / CAP).clamp(0.0, 1.0) * WIDTH).round
          bar = ("▓" * filled) + ("░" * (WIDTH - filled))
          clock = format(" %2d:%02d", seconds / 60, seconds % 60)
          tui.text_line(spans: [
            tui.text_span(content: bar, style: tui.style(fg: color)),
            tui.text_span(content: clock, style: tui.style(fg: :bright_black))
          ])
        end

        # @param tui [RatatuiRuby::TUI]
        # @return [RatatuiRuby::Text::Line]
        def self.empty(tui)
          tui.text_line(spans: [
            tui.text_span(content: " " * WIDTH, style: tui.style(fg: :bright_black)),
            tui.text_span(content: " --:--", style: tui.style(fg: :bright_black))
          ])
        end

        # @param elapsed [Integer]
        # @return [Symbol]
        def self.elapsed_color(elapsed) = elapsed >= 900 ? :yellow : :green

        # @param remaining [Integer, nil]
        # @return [Symbol]
        def self.remaining_color(remaining)
          return :bright_black if remaining.nil?
          return :red if remaining < 300
          return :yellow if remaining < 900

          :green
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

```bash
eval "$(rbenv init -)" && bundle exec rspec spec/agentilda/screen/ratatui/bar_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add lib/agentilda/screen/ratatui/bar.rb spec/agentilda/screen/ratatui/bar_spec.rb
git commit -m "Add Screen::Ratatui::Bar, a colored text bar standing in for LineGauge"
```

---

### Task 4: `Screen::Ratatui.translate_key` — event to keyboard string

Maps a `RatatuiRuby::Event` to the exact string `Keyboard#handle` already expects (`"h"`, `"?"`, `"s"`, `"\e[A"`, `"\e[B"`, `"k"`, `"x"`, `"\r"`, `"\e"`, `"w"`, `"n"`, `"q"`, `"\u0003"`), verified against the gem's actual `KeyCode` string mapping (`ext/ratatui_ruby/src/events.rs`) and `Event::Key::Dwim#interrupt?` (`lib/ratatui_ruby/event/key/dwim.rb`).

**Files:**
- Create: `lib/agentilda/screen/ratatui/key_translator.rb`
- Test: `spec/agentilda/screen/ratatui/key_translator_spec.rb`

**Interfaces:**
- Produces: `Agentilda::Presentation::Screen::Ratatui::KeyTranslator.call(event) -> String, nil`. Task 6's `tick` calls this on every polled event before forwarding to `Keyboard#handle`.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true

require "ratatui_ruby"

RSpec.describe Agentilda::Presentation::Screen::Ratatui::KeyTranslator do
  def key(code, modifiers: [])
    RatatuiRuby::Event::Key.new(code:, modifiers:)
  end

  it "passes plain character keys through unchanged" do
    %w[h ? s k x w n q].each do |char|
      expect(described_class.call(key(char))).to eq(char)
    end
  end

  it "maps arrow keys to the escape sequences Keyboard#handle expects" do
    expect(described_class.call(key("up"))).to eq("\e[A")
    expect(described_class.call(key("down"))).to eq("\e[B")
  end

  it "maps enter and esc" do
    expect(described_class.call(key("enter"))).to eq("\r")
    expect(described_class.call(key("esc"))).to eq("\e")
  end

  it "maps Ctrl+C to ETX, ahead of the plain-character case" do
    expect(described_class.call(key("c", modifiers: ["ctrl"]))).to eq("\u0003")
  end

  it "ignores non-key events" do
    expect(described_class.call(RatatuiRuby::Event::Resize.new(width: 80, height: 24))).to be_nil
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
eval "$(rbenv init -)" && bundle exec rspec spec/agentilda/screen/ratatui/key_translator_spec.rb
```

Expected: `NameError: uninitialized constant Agentilda::Presentation::Screen::Ratatui::KeyTranslator`.

- [ ] **Step 3: Implement**

```ruby
# frozen_string_literal: true

require "ratatui_ruby"

module Agentilda
  class Screen
    class Ratatui
      # RatatuiRuby::Event -> the exact string Keyboard#handle already
      # expects, so every key binding (select, kill, extend, wrap-up, quit,
      # the dialog, ctrl-c) is reused verbatim rather than reimplemented.
      module KeyTranslator
        # @param event [RatatuiRuby::Event]
        # @return [String, nil] nil for anything that is not a key press
        def self.call(event)
          return nil unless event.key?
          return "\u0003" if event.interrupt?

          case event.code
          when "up" then "\e[A"
          when "down" then "\e[B"
          when "enter" then "\r"
          when "esc" then "\e"
          else event.code
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

```bash
eval "$(rbenv init -)" && bundle exec rspec spec/agentilda/screen/ratatui/key_translator_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add lib/agentilda/screen/ratatui/key_translator.rb spec/agentilda/screen/ratatui/key_translator_spec.rb
git commit -m "Add Screen::Ratatui::KeyTranslator"
```

---

### Task 5: `Screen::Ratatui#render` — the widget tree

Builds the whole frame from a `Board`: top bar, the agent table (via `TableState`), a bottom bar with a running-agent sparkline, and the dialog/help/about overlay. Tested with `RatatuiRuby::TestHelper::TestDoubles::MockFrame`/`StubRect` and a **real** `RatatuiRuby::TUI.new` (its widget-building methods are plain Ruby object construction — no terminal or raw mode involved, so nothing needs stubbing here).

**Files:**
- Create: `lib/agentilda/screen/ratatui.rb` (the `render` method and its private helpers only — lifecycle methods land in Task 6)
- Test: `spec/agentilda/screen/ratatui_spec.rb`

**Interfaces:**
- Consumes: `Agentilda::Presentation::Screen::Ratatui::Bar.cell/.elapsed_color/.remaining_color` (Task 3).
- Produces: `Agentilda::Presentation::Screen::Ratatui#render(tui, frame, area, board, table_state) -> void`. Task 6's `#tick` calls this once per frame.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true

require "ratatui_ruby"
require "ratatui_ruby/test_helper"

RSpec.describe Agentilda::Presentation::Screen::Ratatui do
  subject(:screen) { described_class.new }

  let(:tui) { RatatuiRuby::TUI.new }
  let(:frame) { RatatuiRuby::TestHelper::TestDoubles::MockFrame.new }
  let(:area) { RatatuiRuby::TestHelper::TestDoubles::StubRect.new(width: 140, height: 30) }
  let(:table_state) { tui.table_state }

  let(:row) do
    Agentilda::Engine::Board::Row.new(key: "001.00/researcher",
      at: Time.new(2026, 9, 4, 11, 29, 20),
      ordinal: "001.00",
      file: "spec.md",
      agent: "researcher",
      role: "researcher",
      round: 1,
      rounds: 2,
      model: "haiku",
      remaining: 761,
      phase: :calm,
      up: 1_500_000,
      down: 11_000,
      message: "reading plan.md",
      state: :running,
      frame: 3,
      elapsed: 200,
      subagents: 2)
  end

  let(:board) do
    Agentilda::Engine::Board.new(started_at: 0.0,
      status: :running,
      plans: %w[001.00],
      up: 2_700_000,
      down: 22_000,
      rows: [row],
      root: "/repo/qualified-at",
      running: 1,
      live_up: 1_500_000,
      live_down: 11_000)
  end

  def widgets_of(klass)
    frame.rendered_widgets.map { |w| w[:widget] }.select { |w| w.is_a?(klass) }
  end

  it "renders exactly one table with the agent name bold yellow" do
    screen.render(tui, frame, area, board, table_state)

    table = widgets_of(RatatuiRuby::Widgets::Table).first
    expect(table).not_to be_nil
    agent_cell = table.rows.first.cells[3]
    expect(agent_cell.content).to eq("researcher")
    expect(agent_cell.style.fg).to eq(:yellow)
    expect(agent_cell.style.modifiers).to include(:bold)
  end

  it "carries the sub-agent count and token totals in the row" do
    screen.render(tui, frame, area, board, table_state)

    cells = widgets_of(RatatuiRuby::Widgets::Table).first.rows.first.cells
    expect(cells[6]).to eq("2")
    expect(cells[7]).to include("1.5M", "11.0k")
  end

  it "renders the elapsed and time-left bars with the spec's color rules" do
    screen.render(tui, frame, area, board, table_state)

    cells = widgets_of(RatatuiRuby::Widgets::Table).first.rows.first.cells
    elapsed_bar, elapsed_clock = cells[8].spans
    left_bar, left_clock = cells[9].spans
    expect(elapsed_bar.style.fg).to eq(:green)   # 200s < 15min
    expect(elapsed_clock.content).to eq(" 3:20")
    expect(left_bar.style.fg).to eq(:yellow)     # 761s < 15min, >= 5min
    expect(left_clock.content).to eq(" 12:41")
  end

  it "syncs TableState selection from Board#selected by row key" do
    screen.render(tui, frame, area, board.with(selected: row.key), table_state)
    expect(table_state.selected).to eq(0)

    screen.render(tui, frame, area, board.with(selected: nil), table_state)
    expect(table_state.selected).to be_nil
  end

  it "renders the dialog, help, or about overlay as a centered block, exclusively" do
    screen.render(tui, frame, area, board.with(dialog: "kill: yes"), table_state)
    expect(widgets_of(RatatuiRuby::Widgets::Paragraph).map(&:text)).to include(a_string_including("kill: yes"))
  end

  it "renders the running-agent sparkline in the bottom strip" do
    screen.render(tui, frame, area, board, table_state)
    expect(widgets_of(RatatuiRuby::Widgets::Sparkline)).not_to be_empty
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
eval "$(rbenv init -)" && bundle exec rspec spec/agentilda/screen/ratatui_spec.rb
```

Expected: `NameError: uninitialized constant Agentilda::Presentation::Screen::Ratatui` (this file doesn't exist yet — Task 3/4 only created `Ratatui::Bar`/`Ratatui::KeyTranslator` as nested constants, autoloaded independently; the `Ratatui` class body itself is created here).

- [ ] **Step 3: Implement**

```ruby
# frozen_string_literal: true

require "ratatui_ruby"

module Agentilda
  class Screen
    # A ratatui_ruby-backed alternative to {Screen}, selected with `--tui
    # ratatui`. Unlike {Screen}, whose #draw renders synchronously from the
    # dispatcher's own tick, ratatui_ruby owns a blocking render+input loop
    # of its own — see the lifecycle methods added in the next task. This
    # class carries the parts of that loop with no terminal dependency: the
    # widget tree built from a {Board}.
    class Ratatui
      # Cells each fixed-width column takes; the last column is not listed
      # here because it is built with `tui.constraint_fill(1)` — see
      # {#table}.
      COLUMNS = [9, 7, 16, 18, 8, 8, 5, 13, 13, 13].freeze

      HEADER = %w[time plan feature agent round model subs tokens elapsed left activity].freeze

      def initialize
        @history = []
      end

      # @param tui [RatatuiRuby::TUI]
      # @param frame [RatatuiRuby::Frame]
      # @param area [RatatuiRuby::Layout::Rect]
      # @param board [Agentilda::Engine::Board]
      # @param table_state [RatatuiRuby::TableState]
      # @return [void]
      def render(tui, frame, area, board, table_state)
        sync_selection(board, table_state)
        top, table_area, bottom = tui.layout_split(area, direction: :vertical,
          constraints: [tui.constraint_length(1), tui.constraint_fill(1), tui.constraint_length(1)])
        bottom_text, bottom_spark = tui.layout_split(bottom, direction: :horizontal,
          constraints: [tui.constraint_fill(3), tui.constraint_fill(1)])

        frame.render_widget(top_bar(tui, board), top)
        frame.render_stateful_widget(table(tui, board), table_area, table_state)
        frame.render_widget(bottom_bar(tui, board), bottom_text)
        frame.render_widget(tui.sparkline(data: @history, style: tui.style(fg: :cyan)), bottom_spark)
        render_overlay(tui, frame, area, board)
      end

      # @param board [Agentilda::Engine::Board]
      # @return [void]
      def sample(board)
        @history << board.running
        @history.shift while @history.size > 60
      end

      private

      # @param board [Agentilda::Engine::Board]
      # @param table_state [RatatuiRuby::TableState]
      # @return [void]
      def sync_selection(board, table_state)
        index = board.selected && board.rows.index { |r| r.key == board.selected }
        table_state.select(index)
      end

      # @return [RatatuiRuby::Widgets::Paragraph]
      def top_bar(tui, board)
        tui.paragraph(
          text: "#{board.status} · plans: #{board.plans.join(", ")} " \
                "· tokens ↑#{UI.abbreviate(board.up)} ↓#{UI.abbreviate(board.down)}",
          style: tui.style(fg: :black, bg: :white)
        )
      end

      # @return [RatatuiRuby::Widgets::Paragraph]
      def bottom_bar(tui, board)
        tui.paragraph(
          text: "working in #{board.root} · agents running: #{board.running} " \
                "· live ↑#{UI.abbreviate(board.live_up)} ↓#{UI.abbreviate(board.live_down)}",
          style: tui.style(fg: :black, bg: :white)
        )
      end

      # @return [RatatuiRuby::Widgets::Table]
      def table(tui, board)
        widths = COLUMNS.map { |w| tui.constraint_length(w) } + [tui.constraint_fill(1)]
        tui.table(header: HEADER,
          rows: board.rows.map { |row| table_row(tui, row) },
          widths:,
          row_highlight_style: tui.style(modifiers: [:reversed]))
      end

      # @return [RatatuiRuby::Widgets::Row]
      def table_row(tui, row)
        tui.row(cells: [
          row.at.strftime("%H:%M:%S"),
          row.ordinal,
          row.file,
          tui.text_span(content: row.agent, style: tui.style(fg: :yellow, modifiers: [:bold])),
          "R:#{row.round}/#{row.rounds}",
          row.model.to_s,
          row.subagents.to_s,
          "↑#{UI.abbreviate(row.up)} ↓#{UI.abbreviate(row.down)}",
          Bar.cell(tui, row.elapsed, Bar.elapsed_color(row.elapsed)),
          Bar.cell(tui, row.remaining, Bar.remaining_color(row.remaining)),
          row.message.to_s
        ])
      end

      # @return [void]
      def render_overlay(tui, frame, area, board)
        text = board.dialog || board.help || board.about or return
        title = board.dialog ? "Agent" : (board.help ? "Keys" : "About")
        lines = text.lines.size + 4
        width = [text.lines.map { |l| l.chomp.length }.max.to_i + 6, area.width].min
        overlay_area = tui.rect(x: [(area.width - width) / 2, 0].max,
          y: [(area.height - lines) / 2, 0].max,
          width:,
          height: lines)
        frame.render_widget(tui.paragraph(text:, block: tui.block(title:, borders: [:all])), overlay_area)
      end
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

```bash
eval "$(rbenv init -)" && bundle exec rspec spec/agentilda/screen/ratatui_spec.rb
```

Expected: all examples pass. If a cell-content assertion fails because the gem returns a `Style::Style` with `modifiers` as strings rather than symbols, adjust the assertion to match — do not change the implementation to chase a wrong guess; re-inspect `RatatuiRuby::Style::Style#modifiers` on a real instance first (`tui.style(modifiers: [:bold]).modifiers`) to see what comes back.

- [ ] **Step 5: Commit**

```bash
git add lib/agentilda/screen/ratatui.rb spec/agentilda/screen/ratatui_spec.rb
git commit -m "Add Screen::Ratatui#render: top bar, agent table, sparkline, overlay"
```

---

### Task 6: `Screen::Ratatui` lifecycle — open, draw, close, the render loop

Adds the thread that owns `RatatuiRuby.run`, the mutex-protected `Board` handoff, the 10-second sparkline sampling, and key forwarding to `Keyboard`. The loop itself (`RatatuiRuby.run`/`poll_event`) is injected so the spec never needs a real terminal; `#tick` — the one real per-frame unit — is tested against a **real** `RatatuiRuby::TUI.new` with only `#draw`/`#poll_event` stubbed (everything else on it, `layout_split`, `table`, `style`, and so on, runs for real, exactly as in Task 5).

**Files:**
- Modify: `lib/agentilda/screen/ratatui.rb`
- Modify: `spec/agentilda/screen/ratatui_spec.rb`

**Interfaces:**
- Consumes: `Screen::Ratatui::KeyTranslator.call` (Task 4), `Agentilda::Presentation::Keyboard#handle` (existing), `Agentilda::UI.monotonic` (existing).
- Produces: `Agentilda::Presentation::Screen::Ratatui#attach_keyboard(keyboard)`, `#open`, `#draw(board)`, `#close`, `#tick(tui, table_state)`. Task 7's CLI wiring calls `#attach_keyboard`, `#open`, `#draw` (indirectly, via `Console#paint`), `#close`.

- [ ] **Step 1: Write the failing tests**

Append to `spec/agentilda/screen/ratatui_spec.rb`:

```ruby
describe "lifecycle" do
  let(:keyboard) { instance_double(Agentilda::Presentation::Keyboard, handle: nil) }

  before { screen.attach_keyboard(keyboard) }

  describe "#tick" do
    it "does nothing when no board has been drawn yet" do
      allow(tui).to receive(:poll_event)
      screen.tick(tui, table_state)
      expect(tui).not_to have_received(:poll_event)
    end

    it "draws the latest board and forwards the translated key to the keyboard" do
      screen.draw(board)
      allow(tui).to receive(:draw) { |&blk| blk.call(frame) }
      allow(tui).to receive(:poll_event).and_return(RatatuiRuby::Event::Key.new(code: "k"))

      screen.tick(tui, table_state)

      expect(tui).to have_received(:draw)
      expect(keyboard).to have_received(:handle).with("k")
    end

    it "ignores a non-key event without calling the keyboard" do
      screen.draw(board)
      allow(tui).to receive(:draw) { |&blk| blk.call(frame) }
      allow(tui).to receive(:poll_event).and_return(RatatuiRuby::Event::None.new)

      screen.tick(tui, table_state)

      expect(keyboard).not_to have_received(:handle)
    end

    it "samples the running-agent count once every 10 seconds, not every tick" do
      allow(tui).to receive(:draw)
      allow(tui).to receive(:poll_event).and_return(RatatuiRuby::Event::None.new)
      allow(Agentilda::UI).to receive(:monotonic).and_return(0.0, 1.0, 11.0)

      screen.draw(board.with(running: 3))
      screen.tick(tui, table_state) # t=0: first sample always taken
      screen.draw(board.with(running: 5))
      screen.tick(tui, table_state) # t=1: too soon, no sample
      screen.draw(board.with(running: 7))
      screen.tick(tui, table_state) # t=11: 10s elapsed, sample taken

      expect(screen.history).to eq([3, 7])
    end
  end

  describe "#open and #close" do
    it "runs the loop on its own thread via the injected runner, until closed" do
      ticked = Queue.new
      fake_tui = Object.new
      runner = ->(&block) { block.call(fake_tui) }
      screen = described_class.new(runner:)
      screen.attach_keyboard(keyboard)
      allow(screen).to receive(:tick) { ticked << true }

      screen.open
      sleep 0.05 until ticked.size >= 2
      screen.close

      expect(ticked.size).to be >= 2
    end
  end
end
```

Add an `attr_reader :history` to `Ratatui` (used by the sampling test above) — see Step 2.

- [ ] **Step 2: Run to verify it fails**

```bash
eval "$(rbenv init -)" && bundle exec rspec spec/agentilda/screen/ratatui_spec.rb -e "lifecycle"
```

Expected: `NoMethodError: undefined method 'attach_keyboard'` — none of these methods exist yet.

- [ ] **Step 3: Implement**

Add to `lib/agentilda/screen/ratatui.rb`, inside the `Ratatui` class. This **replaces** Task 5's `def initialize` (which only set `@history = []`) with the expanded version below — every other method here (`attach_keyboard`, `open`, `draw`, `close`, `run_loop`, `tick`, `forward`) is new:

```ruby
      # Seconds between samples for the running-agent-count sparkline.
      SAMPLE_INTERVAL = 10

      # Points the sparkline keeps before the oldest scrolls off the left.
      HISTORY = 60

      # @return [Array<Integer>] running-agent-count samples, oldest first
      attr_reader :history

      # @param runner [#call] `RatatuiRuby.method(:run)` by default; a fake
      #   in tests, so this class never needs a real terminal to exercise
      #   its own orchestration
      def initialize(runner: RatatuiRuby.method(:run))
        @runner = runner
        @board = nil
        @keyboard = nil
        @history = []
        @last_sample = nil
        @closing = false
        @mutex = Mutex.new
      end

      # @param keyboard [Agentilda::Presentation::Keyboard] built with `.new`, never
      #   `.start`'d — this is what feeds it keys, from the thread
      #   ratatui_ruby's own loop runs on.
      # @return [void]
      def attach_keyboard(keyboard) = @keyboard = keyboard

      # @return [void]
      def open
        @closing = false
        @thread = Thread.new do
          Thread.current.report_on_exception = false
          @runner.call { |tui| run_loop(tui) }
        end
      end

      # Called by {Console#paint} from the dispatcher's own thread, exactly
      # as {Screen#draw} is. Stores the board; the ratatui thread picks it
      # up on its own next tick, a fraction of a frame later.
      #
      # @param board [Agentilda::Engine::Board]
      # @return [void]
      def draw(board) = @mutex.synchronize { @board = board }

      # @return [void]
      def close
        @closing = true
        @thread&.join
        @thread = nil
      end

      # @param tui [RatatuiRuby::TUI]
      # @return [void]
      def run_loop(tui)
        table_state = tui.table_state
        tick(tui, table_state) until @closing
      end

      # One frame: draw the latest board, sample the sparkline, forward the
      # next key. Public so the lifecycle spec can drive it without needing
      # to manage the `until @closing` loop.
      #
      # @param tui [RatatuiRuby::TUI]
      # @param table_state [RatatuiRuby::TableState]
      # @return [void]
      def tick(tui, table_state)
        board = @mutex.synchronize { @board }
        return unless board

        sample(board)
        tui.draw { |frame| render(tui, frame, frame.area, board, table_state) }
        forward(tui.poll_event)
      end
```

Replace the earlier `#sample` (which only appended unconditionally) with the throttled version, and add `#forward`:

```ruby
      # @param board [Agentilda::Engine::Board]
      # @return [void]
      def sample(board)
        now = UI.monotonic
        return if @last_sample && now - @last_sample < SAMPLE_INTERVAL

        @last_sample = now
        @history << board.running
        @history.shift while @history.size > HISTORY
      end
```

```ruby
      # @param event [RatatuiRuby::Event]
      # @return [void]
      def forward(event)
        key = KeyTranslator.call(event) or return
        @keyboard&.handle(key)
      end
```

`render`'s own `data: @history` reference (Task 5) already reads the same instance variable this section maintains — no change needed there.

- [ ] **Step 4: Run to verify it passes**

```bash
eval "$(rbenv init -)" && bundle exec rspec spec/agentilda/screen/ratatui_spec.rb
```

Expected: all examples pass, Task 5's examples included (they call `render` directly and are unaffected by this task).

- [ ] **Step 5: Commit**

```bash
git add lib/agentilda/screen/ratatui.rb spec/agentilda/screen/ratatui_spec.rb
git commit -m "Add Screen::Ratatui's render loop: open, draw, close, key forwarding"
```

---

### Task 7: CLI wiring — `--tui` flag and backend selection

Wires `--tui ratatui|spinner` (default `spinner`) and `AGENTILDA_TUI` into `agentilda run`, builds whichever `Screen` the choice names, and — only for `ratatui` — builds a non-started `Keyboard.new` (instead of `Keyboard.listen`, which would spawn a second stdin reader fighting ratatui's own raw-mode input) and hands it to the screen.

**Files:**
- Modify: `lib/agentilda/cli/run/run.rb`
- Test: `spec/agentilda/cli/run_spec.rb`

**Interfaces:**
- Consumes: `Agentilda::Presentation::Screen::Ratatui.new`, `#attach_keyboard`, `#open`, `#close` (Task 6); `Agentilda::Presentation::Keyboard.new` (existing).

- [ ] **Step 1: Write the failing tests**

Add to `spec/agentilda/cli/run_spec.rb` (find a `describe` block near the other screen/keyboard-adjacent examples, or add a new top-level one):

```ruby
describe "--tui" do
  before { allow(Agentilda::UI).to receive(:animate?).and_return(true) }

  it "builds the spinner Screen by default" do
    allow(Agentilda::Presentation::Screen).to receive(:new).and_call_original
    allow(Agentilda::Presentation::Screen::Ratatui).to receive(:new)
    run(commit: true)
    expect(Agentilda::Presentation::Screen).to have_received(:new)
    expect(Agentilda::Presentation::Screen::Ratatui).not_to have_received(:new)
  end

  it "builds Screen::Ratatui and a non-started Keyboard when --tui ratatui is passed" do
    fake_screen = instance_double(Agentilda::Presentation::Screen::Ratatui, attach_keyboard: nil, open: nil, close: nil)
    allow(Agentilda::Presentation::Screen::Ratatui).to receive(:new).and_return(fake_screen)
    allow(Agentilda::Presentation::Keyboard).to receive(:new).and_call_original

    run(commit: true, tui: "ratatui")

    expect(Agentilda::Presentation::Screen::Ratatui).to have_received(:new)
    expect(Agentilda::Presentation::Keyboard).to have_received(:new)
    expect(fake_screen).to have_received(:attach_keyboard)
  end

  it "falls back to AGENTILDA_TUI when the flag is not passed" do
    allow(Agentilda::Presentation::Screen::Ratatui).to receive(:new).and_return(
      instance_double(Agentilda::Presentation::Screen::Ratatui, attach_keyboard: nil, open: nil, close: nil)
    )
    begin
      ENV["AGENTILDA_TUI"] = "ratatui"
      run(commit: true)
    ensure
      ENV.delete("AGENTILDA_TUI")
    end

    expect(Agentilda::Presentation::Screen::Ratatui).to have_received(:new)
  end

  it "prefers the flag over AGENTILDA_TUI when both are set" do
    allow(Agentilda::Presentation::Screen).to receive(:new).and_call_original
    allow(Agentilda::Presentation::Screen::Ratatui).to receive(:new)
    begin
      ENV["AGENTILDA_TUI"] = "ratatui"
      run(commit: true, tui: "spinner")
    ensure
      ENV.delete("AGENTILDA_TUI")
    end

    expect(Agentilda::Presentation::Screen).to have_received(:new)
    expect(Agentilda::Presentation::Screen::Ratatui).not_to have_received(:new)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
eval "$(rbenv init -)" && bundle exec rspec spec/agentilda/cli/run_spec.rb -e "--tui"
```

Expected: `NoMethodError` or `ArgumentError: unknown keyword: :tui` — the option doesn't exist yet.

- [ ] **Step 3: Add the option**

In `lib/agentilda/cli/run/run.rb`, alongside the other `option` declarations:

```ruby
      option :tui,
        values: %w[spinner ratatui],
        desc:   "spinner (default): the built-in ANSI dashboard. ratatui: an alternate renderer built " \
                "on ratatui_ruby. AGENTILDA_TUI is a fallback when this flag is not passed."
```

(No `default:` — a `nil` `options[:tui]` is how `#call` tells "not passed" apart from "passed as spinner", which is what lets the env var fallback actually run.)

- [ ] **Step 4: Wire selection into `#call`**

Replace:

```ruby
        Control.reset!
        screen   = (Screen.new if UI.animate? && commit?(options))
        console  = (Console.new(screen:) if screen)
        keyboard = Keyboard.listen(sink: console)
        UI.line("keys: h for help - s select, k kill, x extend, w wrap up, n stop, q quit") if keyboard && console.nil? && !quiet?(options)
```

with:

```ruby
        Control.reset!
        tui_backend = (options[:tui] || ENV["AGENTILDA_TUI"] || "spinner").to_sym
        screen = if UI.animate? && commit?(options)
                   tui_backend == :ratatui ? Screen::Ratatui.new : Screen.new
                 end
        console  = (Console.new(screen:) if screen)
        keyboard = if screen && tui_backend == :ratatui
                     Keyboard.new(sink: console).tap { |kb| screen.attach_keyboard(kb) }
                   else
                     Keyboard.listen(sink: console)
                   end
        UI.line("keys: h for help - s select, k kill, x extend, w wrap up, n stop, q quit") if keyboard && console.nil? && !quiet?(options)
```

Then, a few lines down, where `screen&.open` / `screen&.close` already bracket `runner.call`:

```ruby
        started  = UI.monotonic
        attempts = begin
          screen&.open
          runner.call { |dispatcher| console&.attach(dispatcher) }
        ensure
          screen&.close
          keyboard&.stop
        end
```

No change needed here — `Screen::Ratatui#open`/`#close` (Task 6) and `Screen#open`/`#close` (existing) share the same two-method interface, and `Keyboard#stop` is a no-op on a `Keyboard.new` that was never `.start`'d (its `@thread` is `nil`), so this block already does the right thing for both backends unmodified.

- [ ] **Step 5: Run to verify it passes**

```bash
eval "$(rbenv init -)" && bundle exec rspec spec/agentilda/cli/run_spec.rb
```

Expected: all examples pass, the whole file included (not just the new ones — this touches shared setup in `#call`).

- [ ] **Step 6: Manual smoke test**

This is the one thing no unit test here covers: that `agentilda run --commit --tui ratatui` actually looks right in a real terminal and that spawned `claude` subprocesses are unaffected by the parent's raw/alt-screen mode. In a project with a `.plans` tree and at least one dispatchable plan:

```bash
eval "$(rbenv init -)" && bundle exec exe/agentilda run --commit --tui ratatui --isolation shared
```

Watch for: the table renders and updates, `h`/`?`/arrow keys/`k`/`x`/`w`/`n`/`q` all behave exactly as they do under the default `--tui spinner`, and the terminal is left in a normal (non-raw, non-alt-screen) state after the run ends or is `q`-cancelled. If anything about spawned agent subprocesses looks wrong (hung `claude` process, garbled output), that is the "threads inherit the parent's raw terminal state" risk the gem's own docs warn about — stop and report the specific symptom rather than guessing at a fix.

- [ ] **Step 7: Commit**

```bash
git add lib/agentilda/cli/run/run.rb spec/agentilda/cli/run_spec.rb
git commit -m "Wire --tui ratatui|spinner into agentilda run"
```
