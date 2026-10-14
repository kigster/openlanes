# frozen_string_literal: true

module OpenLanes
  module Presentation
    # Generates the conventions document from the state machine itself.
    #
    # The tables and the diagram are DERIVED — from {STATUSES}, {StateMachine.inbound}
    # and {Ordinal} — so they cannot drift from the tool the way three
    # hand-maintained copies of the status table already did.
    #
    # The prose is not derived, because a machine cannot invent the reasoning: why
    # the tool refuses rather than guesses, why a retroactive plan gets its own
    # number shape, what happens to this scheme if a real issue tracker arrives.
    # That lives in the heredocs below, in one place, and is emitted alongside the
    # generated parts.
    class Documentation
      # @return [String] the whole document
      def render
        [
          header,
          numbering,
          places,
          starting,
          status_table,
          blocking,
          transitions,
          diagram,
          files_section,
          pull_requests,
          footer
        ].join("\n")
      end

      private

      # @return [String]
      def header
        <<~MARKDOWN
          # Spec → Plan → Build

          > [!IMPORTANT]
          > **This file is auto generated.**
          >
          > To regenerate it, run `openlanes docs -o <file>`; without `-o`
          > it prints to STDOUT.
          >
          > After changing the state machine. Editing it by hand puts it back into the
          > condition it was written to end: three copies of the same table, quietly
          > disagreeing.

          Every project keeps its plans in a `#{OpenLanes::PLANS_DIR}/` directory at its root.
          Each medium-to-large feature gets one folder, and the folder's **name is its
          state**: the number identifies it forever, the emoji says what phase it is in,
          and the slug says what it is.

          There are three phases, and each one has a file that proves it happened:

          | Phase | State | The file that proves it |
          | :---- | :---- | :---------------------- |
          | **spec** | #{status(:new).emoji} #{status(:new).label} | `spec.md` |
          | **plan** | #{status(:planned).emoji} #{status(:planned).label} | `plan.md` |
          | **build** | #{status(:building).emoji} → #{status(:ready_for_review).emoji} → #{status(:in_review).emoji} → #{status(:approved).emoji} | `pull-requests.md` |

          Those files are not paperwork. They are what the tool checks: a folder may not
          claim a phase whose file is missing, and `openlanes resync dirs` renames
          any folder whose emoji its contents do not support.

        MARKDOWN
      end

      # @return [String]
      def numbering
        <<~MARKDOWN
          ## The number

          A plan's number is its identity. It is set once, when the folder is created,
          and never changes: branch names, pull request titles and every
          `pull-requests.md` join on it, and renumbering breaks all of them silently.

          The shape is always `NNN.MM`:

          ```
          #{OpenLanes::PLANS_DIR}/#{name("000.00", :new, "initial-spec")}
          #{OpenLanes::PLANS_DIR}/#{name("001.00", :building, "dev-foundation")}
          #{OpenLanes::PLANS_DIR}/#{name("001.01", :retroactive, "schedule-k1-backfill")}   <- shipped between 001 and 002,
          #{OpenLanes::PLANS_DIR}/#{name("002.00", :planned, "tenancy-households")}        specified afterwards
          ```

          A folder name holds no space, so it needs no quoting in a shell, and every
          state emoji is a single code point, so it measures the same in every terminal.
          Older spellings (`NNN.MM-<emoji> → <slug>`, `NNN-<emoji>--<slug>`) and the
          emoji they used are still read; `openlanes resync dirs` renames them.

          - **`NNN` counts from `000`.** The first plan of a project is `000.00`; after
            that it is the highest major plus one, zero-padded to three digits.
          - **`MM` is `00` for an ordinary plan** — one specified before it was built.
          - **`MM` from `01` to `99` marks a retroactive plan**: work that shipped with no
            specification, documented after the fact. `openlanes create --after 001`
            takes the next free slot in the gap after 001.

          `001.01` is a **sibling of 001 that arrived later, not a part of 001**. The dot
          reads as containment in almost every other numbering scheme, and here it does
          not — which is worth saying wherever the scheme is described, because the
          containment reading is the one a new reader brings.

          Two digits, always. One would sort into the middle of the two-digit range —
          `001.09` < `001.1` < `001.10` — so a single mixed-width folder silently
          reorders the index. Two digits also retire the question of running out: 99
          slots per gap, against a gap that closes the moment the next plan is created.

          > [!NOTE]
          > Padding every plan to `NNN.MM` is a deliberate choice, and it costs something.
          > A bare `018` next to `018.01` would have told you at a glance which plan was
          > specified in advance and which was written afterwards. With uniform padding
          > that distinction is no longer readable from the number alone — it is carried
          > by `MM > 0`, which you have to know to look for. What padding buys is
          > alignment and one shape to parse everywhere.

          **A retroactive `spec.md` must open with a dated line saying so**, naming the
          pull requests it describes. It documents what exists; it does not pretend to
          have decided anything in advance. Anchor by *when the work merged*, not by what
          it is about — compare merge dates against folder creation dates
          (`git log --diff-filter=A`). Anchoring by topic invites an argument nobody can
          settle, and the number is a slot, not a claim about subject matter.

        MARKDOWN
      end

      # Where a plan lives, derived from {Plans::Tree::INACTIVE_DIRS}.
      #
      # @return [String]
      def places
        rows = OpenLanes::Plans::Tree::INACTIVE_DIRS.group_by { |_, dir| dir }.map do |dir, pairs|
          states = pairs.map { |key, _| "#{status(key).emoji} #{status(key).label}" }.join(", ")
          "| `#{OpenLanes::PLANS_DIR}/#{dir}/` | #{states} |"
        end
        dated = name("001.00", :approved, "dev-foundation", archived_on: Date.new(2026, 9, 1))

        <<~MARKDOWN
          ## Where a plan lives

          The top of `#{OpenLanes::PLANS_DIR}` holds only plans somebody may still work on.
          A plan in one of these states moves into a subfolder, and its name gains the
          date it got there:

          | Folder | States |
          | --- | --- |
          #{rows.join("\n")}

          ```
          #{OpenLanes::PLANS_DIR}/#{OpenLanes::Plans::Tree.subfolder_for(status(:approved))}/#{dated}
          ```

          `openlanes resync dirs` does the moving, with `git mv`, and moves a plan back
          to the top, undated, once its state is open again. The date is the folder's
          last rename in git, else `state.json`'s `updated_at`, else today. Numbers span
          the subfolders: a number in `archive/` is never handed out again.
          `openlanes list-plans` shows the open plans; `--all` adds the rest.

          While an agent works in a plan, the folder holds a git-ignored
          `#{OpenLanes::Plans::Lock::FILENAME}` (pid, host, start time) and `list-plans`
          shows 🔑. The folder is never renamed while it is locked. `resync dirs` clears a
          lock whose process is gone from this machine, and only reports one from another.

        MARKDOWN
      end

      # @param ordinal [String]
      # @param key [Symbol]
      # @param slug [String]
      # @param archived_on [Date, nil]
      # @return [String] a folder name, spelled the one way {Plans.plan_dirname} spells it
      def name(ordinal, key, slug, archived_on: nil) = OpenLanes::Plans.plan_dirname(ordinal, status(key), slug, archived_on:)

      # @return [String]
      def starting
        headings = OpenLanes::Lifecycle::Brief::HEADINGS.map { |h| "- `## #{h}`" }.join("\n")

        <<~MARKDOWN
          ## Starting a feature that does not exist yet

          `openlanes create <two to five words>` mints the folder at #{status(:new).emoji} #{status(:new).label}
          and, for a genuinely new feature, scaffolds `spec.md` with a title and four
          headings, verbatim:

          #{headings}

          `#{OpenLanes::Lifecycle::Brief::AGENT_NAME}` — a half-agent: it runs only inside `create` and
          holds no roster entry — then makes a best-effort attempt at each from what
          the project already has on disk — its own docs, `#{OpenLanes::Lifecycle::Brief::BACKLOG_FILE}` when
          the project keeps one, anything already downloaded or already built that
          bears on the topic — and opens the result for a human to finish.
          `--no-draft` skips the attempt and leaves the headings bare; `--no-open`
          leaves the file for you to open.

          **Nothing else belongs in that first pass.** It writes no `## Goals`, no
          `## Non-Goals`, no conclusions — deciding those before `leah-researcher` and
          `yoda-writer` have looked is choosing the answer before the research runs.
          Above all, it writes no heading beginning with the word "Research": that
          heading is not decoration, it is the #{status(:researched).emoji} #{status(:researched).label} invariant, so writing
          one — even empty — flips the folder's state out from under whoever reads it
          next, and the research nobody did gets skipped rather than assigned.

          This is only for work that does not exist yet. `create --after <plan> --prs
          <n,...>` is the other path — the work already shipped, so `yoda-writer`
          reconstructs the specification from the pull requests instead of guessing at
          a feature that has no facts yet to guess from.

        MARKDOWN
      end

      # @return [String]
      def status_table
        rows = OpenLanes::Plans::STATUSES.map do |s|
          required = s.requires.empty? ? "—" : s.requires.map { |f| "`#{f}`" }.join(", ")
          "| #{s.emoji} | **#{s.label}** | `#{s.key}` | #{required} | #{s.note} |"
        end

        <<~MARKDOWN
          ## The states

          | Symbol | Meaning | Key | Files required | Description |
          | :----: | :------ | :-- | :------------- | :---------- |
          #{rows.join("\n")}

          "Files required" is a **minimum**, not an exact match: a #{status(:new).emoji} folder that
          has grown a `plan.md` still satisfies #{status(:new).emoji}, and is #{status(:planned).emoji} anyway. That is
          why `resync dirs` moves a folder to the furthest state its contents justify
          rather than only fixing outright lies.

          Some states share their requirements on purpose, and are told apart only by the
          folder name. #{status(:blocked).emoji} #{status(:blocked).label} and #{status(:product_blocked).emoji} #{status(:product_blocked).label} both mean "a human must
          decide before this can move"; *which* human is recorded nowhere but the emoji.
          #{Plans::StateMachine::FAMILIES.last.map { |k| status(k).emoji }.join(" ")} all mean "the work exists and pull requests are open"; whether
          anyone has started reviewing is written down nowhere either.

          So nothing re-derives one of them from a folder's contents — otherwise every
          #{status(:blocked).emoji} would silently become #{status(:product_blocked).emoji} the first time anything resynced. A folder
          falling back into that group from outside lands on its weakest member,
          #{status(Plans::StateMachine::FAMILIES.last.first).emoji} #{status(Plans::StateMachine::FAMILIES.last.first).label}, because that is all its contents can prove.

          #{merged_note}

        MARKDOWN
      end

      # @return [String]
      def merged_note
        "🟣 Merged is deliberately **not** a folder state. It describes a pull request, " \
          "and a folder that claimed it would be claiming a pull request's condition as its own."
      end

      # Why this is prose rather than another derived table: the mechanism is a
      # rule about the *contents* of one file, and the only part of it a program
      # can see is the invariant. Everything that makes the rule safe — a human
      # types the command, an agent never answers anything — is a decision, and
      # decisions belong in sentences.
      #
      # @return [String]
      def blocking
        settled = Plans::StateMachine::SETTLED.map { |k| status(k).emoji }.join(" ")

        <<~MARKDOWN
          ## When a plan is stopped, and how it starts again

          #{status(:blocked).emoji} #{status(:blocked).label} and #{status(:product_blocked).emoji} #{status(:product_blocked).label} mean an agent hit a question that was not
          its to answer and wrote `blocked.md` instead of guessing past it. Both belong to
          the settled group `openlanes run` leaves alone (#{settled}), so the loop
          never offers a stopped plan to anybody. A loop that could move one would make
          the state mean nothing.

          Questions are numbered `B1`, `B2`, and that numbering is how the file gets
          referenced in conversation and in pull requests. **`blocked.md` holds open
          questions and nothing else.** That is what the #{status(:blocked).emoji}/#{status(:product_blocked).emoji} invariant reads, so a
          file naming no question justifies neither state and `resync dirs` renames the
          folder out of it.

          Which is how a block drains, in pieces:

          1. A human writes each answer under `## Answers` as it arrives, dated and
             attributed to whoever decided.
          1. `openlanes unblock NNN` hands the folder to `lando-broker`.
             Nothing else reaches it: answers arriving is not a fact the tool can
             observe, so a human running the command *is* the signal.
          1. `lando-broker` folds each answered question into the document that question
             was stopping — `spec.md` when the answer changes what we are building or
             why, `plan.md` when it changes how or in what order — and deletes the
             question and its answer from `blocked.md`.
          1. When the last question goes, the file goes with it, and the folder leaves
             #{status(:blocked).emoji} on the resync that follows.

          An entry that names no decider, carries no date, or restates the options
          instead of choosing one is not an answer, and is left exactly where it is.
          So is any question nobody has answered yet: two answers out of five is a
          successful run, and the plan stays stopped on the other three, which is true.
          `lando-broker` never answers a question itself, and never retires one for
          being stale — dropping a question is a human's call, and it makes the plan
          #{status(:deferred).emoji} #{status(:deferred).label} or #{status(:discarded).emoji} #{status(:discarded).label}, not quietly shorter.

        MARKDOWN
      end

      # @return [String]
      def transitions
        rows = OpenLanes::Plans::STATUSES.map do |s|
          out = Plans::StateMachine.outbound(s.key)
          targets = out.empty? ? "_terminal_" : out.map { |k| status(k).emoji }.join(" ")
          spine = Plans::StateMachine::SPINE[s.key]
          "| #{s.emoji} #{s.label} | #{targets} | #{spine ? "#{status(spine).emoji} #{status(spine).label}" : "—"} |"
        end

        <<~MARKDOWN
          ## Transitions

          | From | May become | `promote` goes to |
          | :--- | :--------- | :---------------- |
          #{rows.join("\n")}

          A bare promote walks the **spine** — spec → plan → build. Everything off it
          (blocking, deferring, rejecting) has to be named explicitly. That is the whole
          reason there is a machine here rather than a rename: a transition is refused
          when the destination's requirements are not already met, and that refusal is
          information — it means the phase has not actually happened yet.

        MARKDOWN
      end

      # The picture is a hand-drawn PNG, not the mermaid block, because mermaid
      # lays fifteen states out in a way nobody wants to read.
      #
      # The mermaid source is still emitted underneath it, and still derived from
      # the machine — which is precisely what makes it the staleness check for a
      # hand-drawn image. Regenerating this document rewrites that block from
      # {STATUSES} and {StateMachine.inbound}, so a diff there means the PNG no
      # longer matches. No diff there, no redraw.
      #
      # @return [String]
      def diagram
        edges = Plans::StateMachine.inbound.flat_map { |to, froms|
          froms.map { |from| "    #{from} --> #{to}" }
        }

        <<~MARKDOWN

          <details>
          <summary>Mermaid source for the diagram above</summary>

          ```mermaid
          stateDiagram-v2
              direction LR
          #{OpenLanes::Plans::STATUSES.map { |s| "    #{s.key} : #{s.emoji} #{s.label}" }.join("\n")}

          #{edges.join("\n")}
          ```

          </details>

        MARKDOWN
      end

      # @return [String]
      def files_section
        known = OpenLanes::Plans::STATUSES
                .flat_map(&:requires)
                .uniq
                .map { |f| "| `#{f}` | #{holders_of(f)} |" }

        <<~MARKDOWN
          ## Files allowed in a plan folder

          | File | Required by |
          | :--- | :---------- |
          | `spec.md` | the specification; written first |
          | `plan.md` | the execution plan; written from the spec |
          | `contract.md` | the contract between the two halves of building |
          | `openapi.yaml` | the HTTP surface, when the plan has one |
          #{known.reject { |r| r.start_with?("| `spec.md`", "| `plan.md`") }.join("\n")}

          `contract.md` is the one file no state requires. `luke-backend` writes it
          before it writes code, and `rey-frontend` builds from it a round later: the
          interfaces the back end landed, their shapes and their errors, which files
          each half owns, which units may run concurrently, and the one test that
          proves the halves are joined rather than merely both present. No state
          requires it because a plan with no back-end work never needs one. When
          `plan.md` says the plan has an HTTP surface, `openapi.yaml` sits beside it,
          linked from it, and `openlanes api docs` lists every one in the project.

          The units themselves live in `plan.md`, under `## Backend` and
          `## Frontend`. `rey-frontend` is started only when `## Frontend` holds a
          unit heading.

          Nothing else belongs there. A folder holding notes, diagrams or scratch files
          is a folder nobody can audit at a glance.

        MARKDOWN
      end

      # @param file [String]
      # @return [String]
      def holders_of(file)
        OpenLanes::Plans::STATUSES
          .select { |s| s.requires.include?(file) }
          .map { |s| "#{s.emoji} #{s.label}" }
          .join(", ")
      end

      # @return [String]
      def pull_requests
        <<~MARKDOWN
          ## Pull requests carry the number

          A pull request that implements a plan says so in its title:

          ```
          [003.00] Make the core deterministic and require as_of
          ```

          `pull-requests.md` is generated from these titles, so the prefix is the join key
          between a pull request and a plan, not decoration. Name branches
          `<user>/NNN.MM-slug` and the number carries itself from branch creation through
          to a merged, squashed pull request with nobody having to remember it.

          `openlanes resync prs` fills in missing prefixes. It reads the branch name
          first and falls back to the diff only when that touches exactly one plan folder.
          **It refuses rather than guessing.** A wrong number does not announce itself: it
          files the work under a plan that did not do it, and leaves the plan that did
          looking untouched.

          ### `[#{OpenLanes::NO_PLAN_PREFIX}]` when there is no plan

          Not every pull request implements a feature. Dependency bumps, CI configuration,
          hotfixes and developer tooling implement no plan, and forcing a number onto them
          produces a number chosen to satisfy the rule. Those are titled:

          ```
          [#{OpenLanes::NO_PLAN_PREFIX}] Bump json from 2.21.1 to 2.21.2
          ```

          `#{OpenLanes::NO_PLAN_PREFIX}` means **"this deliberately belongs to no specification"**, and it
          exists so that "no plan" is *asserted* rather than merely absent. A title with no
          prefix is ambiguous between "no plan applies" and "nobody looked".

          `resync prs` will propose it, but marks every such title as **assumed** and never
          applies one without you seeing it. Emitting it silently on a failed lookup would
          launder "I could not tell" into "there is definitely none", which is the same
          lie as guessing a number, told in the other direction.

          ### What does not deserve a retroactive plan

          Most unmatched pull requests. The test is whether **somebody would need to read
          it** — a capability with behaviour, an interface, or invariants that are not
          obvious from the code. "Fix a typo", "remove dead code" and "bump a dependency"
          are `[#{OpenLanes::NO_PLAN_PREFIX}]` and always were. Backfilling those produces an index that is
          longer without being more informative, which makes the real plans harder to find.

        MARKDOWN
      end

      # @return [String]
      def footer
        <<~MARKDOWN
          ## If a real issue tracker arrives, this scheme retires

          This numbering is homegrown because there is nothing else to join on. If the
          work moves to Linear or Jira, **the issue key replaces it**: `[EQL-142] <title>`
          in pull request titles, `EQL-142-<status>-<slug>` for the folder, and the issue
          becomes the thing `pull-requests.md` is generated against.

          Recording that matters more than it looks. A numbering scheme with no stated
          exit becomes permanent by default: it accretes tooling, the tooling accretes
          rules, and by the time a real tracker shows up, migrating is a project rather
          than a decision. The exit is cheap only while it is written down and unbuilt.

          Two things to hold to when that day comes:

          - **Existing numbers are not rewritten.** A plan's number is its identity and
            merged pull request titles are immutable history. `000` stays `000` forever and
            new plans start taking issue keys. A mixed index is ugly for a while and honest
            permanently, which beats a renumbering that breaks every link that ever pointed
            at a plan.
          - **Do not teach the tooling to accept issue keys before the tracker exists.** A
            validator that accepts `[EQL-142]` with nothing to check it against is a guard
            that passes anything shaped like an answer, which is worse than one that fails
            loudly on first use.

          ______________________________________________________________________

          Generated by `openlanes docs` — version #{OpenLanes::VERSION}.
        MARKDOWN
      end

      # @param key [Symbol]
      # @return [OpenLanes::Plans::Status]
      def status(key) = OpenLanes::Plans::STATUS_BY_KEY.fetch(key)
    end
  end
end
