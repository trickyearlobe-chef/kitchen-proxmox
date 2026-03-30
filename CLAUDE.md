# CLAUDE.md

## CLAUDE.md

- CLAUDE.md is operating rules for the AI, not project documentation.
- Keep it concise. Every line costs context window budget.
- If we change our working practices, CLAUDE.md must be updated.

## Constraints

- Rules are specific and actionable.
- Hard constraints use NEVER in caps. No ambiguity.
- Explicit permission boundaries — say what needs human approval.
- No implementation code in CLAUDE.md or specs. That's what TDD is for.
- NEVER use the console/terminal for file editing. Always use `file-edit-mcp` tools (`fem_*`) for file operations.

## Token Efficiency

- Always be concise and NEVER include preamble or narrative in generated files.
- Only read specs, todos, or plans relevant to the current task.
- Be concise when creating or updating specs and todos so tokens are not wasted retrieving context.

## Knowledge

- Component specs and todos live in `specifications/`.
- Each component spec is self-contained. Read only what you need for the current task.
- Background research is available via Nuclia RAG through MCP. Query it when specs are insufficient.
- Work plans live in `plans/`. One file per task or feature.

## Cross-Project Knowledge Base

- The Nuclia KB is shared across all projects. This project's labelset is `kitchen-proxmox`.
- Standard labels: `bug`, `enhancement`, `architecture`, `debugging`, `dependency`, `ops`, `api`.
- At session start: Query `nuclia_find` filtered to `kitchen-proxmox` labelset.
- After fixing a hard bug: Upload the finding with the project's labels.
- Before uploading external markdown/HTML to Nuclia, clean it with `nuclia_clean_text`.

## Specs

- NEVER silently diverge from a spec.
- Do not modify specs without asking.
- Specs define *what*, not *how*.
- NEVER write implementation code without specs first. Specs drive the code, not the other way around.

## Planning

- Before starting work, create a plan in `plans/<task>.md`.
- Plans are short: goal, which specs to read, ordered steps, and acceptance criteria.
- Delete the plan when the work is done. Git is the history.

## Quality Maintenance

- Session start checklist: (a) read CLAUDE.md, (b) read the plan, (c) check for draft files pending review, (d) check git status.
- TODO hygiene: a session should not end with a net increase in TODOs unless they are genuinely open questions.
- Always update todos when items are completed or blocked to avoid losing context.

## File Format

- No headings deeper than H3. Keep files under ~500 lines. Split if longer.

## Git

- All work is local. NEVER push, create PRs, or interact with remotes.
- Spawned agents NEVER run git commands. Only the main Claude commits.
- Every spawn message MUST include: Do NOT run any git commands. Write files only — the caller handles git.
- Commit early and often. One logical change per commit.
- Commit messages: imperative mood, `<scope>: <summary>`.
- NEVER include personal hostnames, IPs, usernames, or internal domain names.

## Spawned Agents

- Scope spawned agents tightly. One file or one narrow topic per agent.
- ALWAYS use `file-edit-mcp` tools (`fem_*`) for file operations. NEVER use `sed`, `awk`, `cat >`, `echo >>`.

## Permission Boundaries

- Do not start implementation without a plan in `plans/`.
- Ask before deleting or renaming existing files.
- Ask before restructuring directory layout.

## Project Type — Ruby Test Kitchen Driver Gem

### Reference Implementation

- kitchen-vagrant (`test-kitchen/kitchen-vagrant`) is the canonical reference for file layout, conventions, and patterns. When in doubt, match what kitchen-vagrant does.

### Layout (follows kitchen-vagrant)

- `lib/kitchen/driver/proxmox.rb` — driver class.
- `lib/kitchen/driver/proxmox_version.rb` — version constant (`Kitchen::Driver::PROXMOX_VERSION`).
- `lib/kitchen/driver/proxmox/` — supporting classes (API client, helpers).
- `spec/kitchen/driver/proxmox_spec.rb` — driver specs. No `unit/` nesting.
- `spec/spec_helper.rb` — shared RSpec config.

### Ruby / Dependency Rules

- NEVER use system Ruby. Always use Chef Workstation Ruby via `chef exec`.
- The ONLY gem that gets installed is `kitchen-proxmox` itself. Everything else ships with Chef Workstation.
- NEVER run `bundle install` or `gem install` for dependencies. NEVER pull gems from rubygems.org.
- NEVER add runtime or development dependencies that are not already in Chef Workstation. Check with `chef exec gem list <name>` before even considering a gem.
- No Gemfile. No Gemfile.lock. No bundler. Run tools directly: `chef exec rspec`, `chef exec rubocop`.
- Install the gem itself with: `chef exec gem build kitchen-proxmox.gemspec && chef exec gem install kitchen-proxmox-*.gem`
- Use `rspec` for unit tests, `chefstyle`/`rubocop` for linting.
- Run tests: `chef exec rspec`. Run lint: `chef exec rubocop`.
- Gem name: `kitchen-proxmox`. Driver class: `Kitchen::Driver::Proxmox`.
- Test Kitchen discovers the driver via `lib/kitchen/driver/proxmox.rb`.

### TDD Workflow

- Write specs first, then implementation. NEVER the other way around.
- Specs use pure RSpec doubles/mocks — no external HTTP stubbing libraries.
- All Proxmox API interactions must be testable in isolation.

### Licensing

- All code is Apache 2.0.
- Dependencies must be compatible with Apache 2.0.
