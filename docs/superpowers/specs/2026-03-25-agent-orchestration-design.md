# Agent Orchestration System — Design Spec

## Context

Managing 13-25 repositories across mixed platforms (Azure DevOps, GitHub) with tasks arriving from multiple sources (Jira, Azure DevOps, ad-hoc emails/meetings). The current workflow involves manually navigating to project folders, spinning up Claude Code sessions, providing context, and juggling 4-6 concurrent tasks across different projects. This overhead adds significant friction to daily work.

**Goal:** A single orchestration layer where the user talks to one Claude Code session, describes tasks in natural language, and the system handles dispatching work to sub-agents across the right repositories — with the user never needing to interact with sub-agents directly.

## Architecture Overview

**Hybrid CLAUDE.md + Script approach:**
- The orchestrator is a Claude Code session launched from a master folder, driven by a comprehensive CLAUDE.md
- Bash scripts handle process lifecycle (launching agents, monitoring, notifications)
- Beads (distributed task tracker built on Dolt) serves as shared state between orchestrator and agents
- Git worktrees provide instant, lightweight parallel working copies from a single clone per repo

**Core principles:**
- User talks ONLY to the orchestrator — sub-agents are invisible
- Agent questions bubble up through the orchestrator as orchestrator questions to the user
- Beads is the shared nervous system — both orchestrator and agents read/write task state
- Worktrees eliminate expensive clones — one clone per repo, instant worktrees for parallel work

## Directory Structure

```
AgentOrchestration/
├── CLAUDE.md                        # Orchestrator brain
├── config/
│   ├── repos.yaml                   # Repo registry (name, URL, platform, default branch)
│   ├── defaults.yaml                # Default autonomy, PR behavior, etc.
│   └── agent-template.md            # Template prompt for sub-agents
├── pool/
│   ├── product-a/                   # Pre-cloned repo (the base clone)
│   ├── product-b/
│   └── ...
├── worktrees/                       # Active git worktrees (created from pool clones)
│   ├── product-a--bd-a3f8--fix-billing/
│   ├── product-a--bd-c4d2--add-logging/
│   └── product-b--bd-b2c1--update-deps/
├── scripts/
│   ├── dispatch.sh                  # Provision worktree, launch agent, attach monitor
│   ├── continue.sh                  # Resume blocked agent with user's answer
│   ├── monitor.sh                   # Watch agent stdout for BLOCKED/DONE, fire notifications
│   └── pool-manage.sh               # Clone, fetch, worktree create/remove, GC
├── logs/
│   └── <task-id>.log                # Per-task agent output
└── .beads/                          # Beads database (managed by bd CLI)
```

### Key directories

- **`pool/`** — One full git clone per repo. Long-lived. `git fetch` keeps them current. These are never worked in directly.
- **`worktrees/`** — Lightweight `git worktree` checkouts created from pool clones. Share `.git/objects` with the pool clone. Creation is instant (<1 second) regardless of repo size. Named `<repo>--<task-id>--<slug>` for easy identification.
- **`scripts/`** — Bash scripts (cross-platform via Git Bash on Windows, native bash on macOS) handling process lifecycle.

## Repo Pool & Worktree Management

### Registry (`config/repos.yaml`)

```yaml
repos:
  product-a:
    url: https://dev.azure.com/org/project/_git/product-a
    platform: azure-devops
    default_branch: main
    pre_clone: true
    max_worktrees: 3
  product-b:
    url: https://github.com/org/product-b
    platform: github
    default_branch: develop
    pre_clone: true
    max_worktrees: 3
  # ... up to 25 repos
```

### Pool lifecycle

1. **Init:** `pool-manage.sh init` clones all `pre_clone: true` repos into `pool/<repo-name>/`
2. **Checkout:** `pool-manage.sh worktree-create <repo> <task-id> <slug>` runs `git -C pool/<repo> worktree add ../../worktrees/<repo>--<task-id>--<slug> -b <branch-name>` from the pool clone
3. **Release:** `pool-manage.sh worktree-remove <repo> <worktree-name>` runs `git worktree remove` and prunes
4. **Lazy clone:** If a task targets a repo not yet in the pool, clone it first, then create the worktree
5. **Refresh:** `pool-manage.sh fetch <repo>` (or `fetch-all`) runs `git fetch --all` on pool clones to stay current
6. **GC:** `pool-manage.sh gc` prunes stale worktrees and runs `git gc` on pool clones

### Worktree limits

Each repo has a `max_worktrees` setting (default 3). The orchestrator checks this before dispatching. If at the limit, it either queues the task or asks the user which existing task to prioritize.

## Task Dispatch Flow

### Step-by-step

1. **User describes task:** Natural language to the orchestrator
   > "Product A has a bug — users get 500 errors on /api/billing when subscriptions expire"

2. **Orchestrator parses and creates Beads task:**
   - Identifies repo from description (or asks if ambiguous)
   - Creates Beads task: `bd add --title "Fix billing 500 on expired subscriptions" --tag repo:product-a --tag type:bug`
   - Records task ID (e.g., `bd-a3f8`)

3. **Orchestrator provisions worktree:**
   - Calls `pool-manage.sh fetch product-a` to get latest
   - Calls `pool-manage.sh worktree-create product-a bd-a3f8 fix-billing-500`
   - Result: `worktrees/product-a--bd-a3f8--fix-billing-500/` ready to go

4. **Orchestrator launches sub-agent:**
   - Calls `dispatch.sh <task-id> <worktree-path> "<agent-prompt>"`
   - dispatch.sh: generates full prompt from agent-template.md + task brief + repo CLAUDE.md
   - dispatch.sh: launches `claude -p "<prompt>"` in the worktree directory
   - dispatch.sh: pipes stdout to `logs/<task-id>.log` and `monitor.sh`

5. **User continues working:** Feeds more tasks, checks status, does other work

### Agent prompt generation

The orchestrator fills in `config/agent-template.md`:

```markdown
You are working on task {{TASK_ID}} in repo {{REPO_NAME}}.
Your working directory is: {{WORKTREE_PATH}}

## Task
{{TASK_BRIEF}}

## Additional Context
{{USER_CONTEXT}}

## Rules
- Work on branch: {{BRANCH_NAME}}
- Commit frequently with clear messages referencing {{TASK_ID}}
- When you need user input, output EXACTLY on its own line:
  BLOCKED: <your question>
  Then stop and wait for the next message.
- When you're done, output EXACTLY on its own line:
  DONE: <summary of what you did, branch name, files changed>
- Update your Beads task as you work:
  bd update {{TASK_ID}} --status in_progress
  bd update {{TASK_ID}} --status blocked --comment "<question>"
  bd update {{TASK_ID}} --status resolved --comment "<summary>"

## Repo-Specific Instructions
{{REPO_CLAUDE_MD}}
```

## Communication Model

### Orchestrator → User

The orchestrator surfaces information to the user through:
- **Direct responses** in the chat for task acknowledgment, status reports
- **OS notifications** when an agent blocks and needs input (fired by monitor.sh)

### User → Orchestrator → Agent

All user communication goes through the orchestrator:
1. User provides followup context or answers a question
2. Orchestrator identifies which task/agent it's for (by context or explicit task ID)
3. Orchestrator calls `continue.sh <task-id> "<user's message>"`
4. continue.sh runs `claude --continue -p "<message>"` in the agent's worktree, resuming the agent's conversation with full context preserved

### Agent → Orchestrator → User

When an agent needs input:
1. Agent outputs `BLOCKED: <question>` and updates Beads task to blocked
2. monitor.sh detects the BLOCKED pattern in the agent's stdout
3. monitor.sh fires an OS notification
4. On next `/status` check (or triggered by notification), orchestrator reads Beads and surfaces the question
5. User answers through the orchestrator

### Notification System

Cross-platform OS notifications via bash:

**Windows (Git Bash):**
```bash
powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; \
  [System.Windows.Forms.MessageBox]::Show('bd-a3f8: question here', 'Agent needs input')"
# Alternative: use BurntToast PowerShell module for richer toast notifications if installed
```

**macOS:**
```bash
osascript -e 'display notification "bd-a3f8: question here" with title "Agent needs input" sound name "Ping"'
```

The notification script detects the platform and uses the appropriate method.

## Orchestrator Commands

The CLAUDE.md defines these commands for the orchestrator:

| Command | Description |
|---------|-------------|
| *(natural language)* | Parse task, create Beads entry, provision worktree, dispatch agent |
| `/status` | Show all tasks with current state (working/blocked/done) |
| `/status <task-id>` | Detailed view of a specific task including recent agent output |
| `/followup <task-id> <msg>` | Relay context or answer to a specific agent |
| `/pool` | Show repo pool status — cloned repos, active worktrees, capacity |
| `/pool add <name> <url>` | Register and clone a new repo into the pool |
| `/pool fetch` | Fetch latest on all pool clones |
| `/done <task-id>` | Mark task complete, review summary, clean up worktree |
| `/cancel <task-id>` | Kill agent process, clean up worktree, close Beads task |
| `/permissions <repo>` | Show current permission profile for a repo |
| `/permissions <repo> add <tool>` | Add an allowed tool to a repo's profile |

### Status display format

```
/status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 bd-a3f8  product-a  fix-billing-500          ⚠️  BLOCKED
          "Should I consolidate the subscription check into middleware?"

 bd-b2c1  product-b  update-deps              🔄  WORKING
          Running test suite after dependency updates

 bd-c4d2  product-a  add-structured-logging   ✅  DONE
          Branch: feature/add-logging — 12 files changed, tests passing

 bd-d5e3  product-c  fix-ci-docker            📋  QUEUED
          Waiting for product-c worktree capacity
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Sub-Agent Architecture

### Agent lifecycle

```
QUEUED → DISPATCHED → WORKING → (BLOCKED ↔ WORKING)* → DONE
                                                          ↓
                                                    worktree released
                                                    Beads task closed
```

### Autonomy model

Default: **medium autonomy** — agents implement freely but check in before architectural decisions or PRs.

Per-task override possible when dispatching:
- **High:** Implement, test, commit, push, open PR. User reviews the PR.
- **Medium:** Implement and test freely. Block on architectural choices and before PR. (Default)
- **Low:** Present a plan before writing code. Block on design, implementation choices, and PR.

### Agent context

Each agent receives:
1. Task brief from user (via orchestrator)
2. Repo-specific CLAUDE.md (if present in the repo)
3. Standing instructions from agent-template.md
4. Beads task ID for status updates

### Session continuity

When a blocked agent receives a followup via `claude --continue`, it resumes with:
- Full conversation history from previous rounds
- All code changes already made in the worktree
- The user's new input as the latest message

This preserves agent context across the blocked → working transitions.

## Scripts Layer

All scripts are bash, compatible with Git Bash (Windows) and native bash (macOS/Linux).

### `dispatch.sh <task-id> <worktree-path> <prompt>`
1. Generates full agent prompt from template + task brief + repo CLAUDE.md
2. Launches `claude -p "<prompt>"` in the worktree directory
3. Tees stdout to `logs/<task-id>.log`
4. Starts monitor.sh for this agent in background
5. Records PID for lifecycle management

### `continue.sh <task-id> <message>`
1. Looks up the worktree path for the task
2. Runs `claude --continue -p "<message>"` in that directory
3. Re-attaches monitoring
4. Updates Beads task status back to in_progress

### `monitor.sh <task-id> <log-file>`
1. Tails the agent's log file
2. Watches for `BLOCKED:` pattern → fires notification, updates Beads
3. Watches for `DONE:` pattern → fires notification, updates Beads
4. Watches for process exit → detects crashes, updates Beads

### `pool-manage.sh <command> [args]`
- `init` — Clone all pre_clone repos
- `fetch <repo>` / `fetch-all` — Update pool clones
- `worktree-create <repo> <task-id> <slug>` — Create worktree from pool clone
- `worktree-remove <repo> <worktree-name>` — Remove worktree, prune
- `gc` — Garbage collect stale worktrees and git objects
- `status` — Show pool state (cloned repos, worktree count per repo)

## Sub-Agent Permissions

### Two modes

Each repo can operate in one of two permission modes:

- **YOLO mode (`--dangerously-skip-permissions`):** All permission checks skipped. Fast, no friction. Appropriate for trusted repos or when speed matters more than guardrails.
- **Managed mode (`--permission-mode dontAsk` + `--allowedTools`):** Whitelisted tools only. Agents that hit an unapproved tool get blocked, which surfaces to the user through the normal attention flow.

Configured per-repo in `repos.yaml`:

```yaml
repos:
  product-a:
    permission_mode: managed
    allowed_tools:
      - "Read"
      - "Edit"
      - "Write"
      - "Bash(git *)"
      - "Bash(npm *)"
    denied_tools:
      - "Bash(git push --force *)"
  product-b:
    permission_mode: yolo
```

Default mode for new repos is set in `config/defaults.yaml`.

### Permission learning flow

In managed mode, permissions grow organically from actual usage rather than requiring upfront configuration:

1. Agent gets blocked on an unapproved tool (e.g., `Bash(cargo test *)`)
2. Agent surfaces as `BLOCKED` with the specific tool it needs
3. Orchestrator presents: *"Agent bd-a3f8 needs `Bash(cargo test *)` — not currently allowed for product-a"*
4. User responds through the orchestrator:
   - **"allow it"** — adds to this repo's `allowed_tools` in `repos.yaml`, resumes agent
   - **"allow it everywhere"** — adds to all repos and `defaults.yaml`, resumes agent
   - **"allow it this time"** — passes as a one-shot flag, doesn't persist
   - **"deny"** — agent must find an alternative approach
5. Orchestrator updates config, commits the change, and resumes the agent via `continue.sh`

This means a new repo starts with a minimal baseline (Read, Edit, Write, git) and builds up its permission set as agents discover what they need — with the user approving each addition exactly once.

### dispatch.sh permission handling

The dispatch script reads the repo's permission config and builds the CLI flags:

```bash
# Managed mode
claude -p "<prompt>" \
  --permission-mode dontAsk \
  --allowedTools "Read,Edit,Write,Bash(git *),Bash(npm *)"

# YOLO mode
claude -p "<prompt>" \
  --dangerously-skip-permissions
```

Tool patterns support wildcards: `Bash(npm run *)` matches `npm run build`, `npm run test`, etc. The `*` is word-boundary aware — `Bash(git *)` matches `git commit` but not `gitk`.

## Self-Modification & Process Evolution

### The orchestrator as its own meta-manager

The orchestration system is entirely file-based: CLAUDE.md, YAML configs, Markdown templates, bash scripts. The orchestrator is a Claude Code session with full read/write access to all of these files. This means the user can evolve the system's behavior by simply asking the orchestrator in natural language.

**No separate tooling or meta-management layer is needed.** The orchestrator *is* the meta-management layer.

### What the orchestrator can modify

| File | What changes | Example request |
|------|-------------|-----------------|
| `CLAUDE.md` | Orchestrator's own behavior, commands | "Add a `/priority` command that lets me reorder queued tasks" |
| `config/agent-template.md` | How all sub-agents behave | "Agents should always run the test suite before marking done" |
| `config/repos.yaml` | Repo registry, permissions, settings | "Add infra-tooling repo, URL is ..." |
| `config/defaults.yaml` | Default autonomy, permissions, etc. | "Change default autonomy to high" |
| `scripts/*.sh` | Process lifecycle scripts | "After an agent finishes, auto-fetch the pool clone so it's fresh" |

### Examples of process evolution

- *"When agents finish a bug fix, have them run the test suite before marking done"* — orchestrator edits `agent-template.md` to add test-run instructions
- *"Product-b's CI catches everything, set it to high autonomy"* — orchestrator updates `repos.yaml`
- *"Add a rule: agents should check for existing tests before writing new ones"* — orchestrator edits `agent-template.md`
- *"The notification on Windows isn't working well, switch to a different approach"* — orchestrator edits the notification script

### Git-backed change tracking

The AgentOrchestration directory is a git repo. Every process change the orchestrator makes is committed with a descriptive message. This provides:

- **History:** `git log` shows how the process evolved and why
- **Revert:** Bad change? `git revert` brings back the previous behavior
- **Experimentation:** Branch to try process changes, merge if they work
- **Portability:** Clone the repo to another machine and the full orchestration setup comes with it

### Session boundary behavior

Changes to different files take effect at different times:

- **`config/repos.yaml`, `config/defaults.yaml`** — take effect on the next agent dispatch (read fresh each time)
- **`config/agent-template.md`** — takes effect on the next agent dispatch (baked into the agent prompt)
- **`scripts/*.sh`** — take effect immediately (scripts are invoked fresh each time)
- **`CLAUDE.md`** — takes effect on the next orchestrator session start (Claude Code reads it once at launch)

This is a useful safety property: the orchestrator can't accidentally destabilize itself mid-session by editing its own CLAUDE.md. The user sees the change in the commit, and it applies next session.

## Open Questions / Assumptions

- **Claude CLI flags:** This spec assumes `claude -p "<prompt>"` runs a single-shot prompt and `claude --continue -p "<message>"` resumes the last conversation in a directory. These flags should be validated against the current Claude Code CLI documentation before implementation. If `--continue` doesn't work with `-p`, an alternative approach (session files, `--resume`) may be needed.
- **Beads CLI syntax:** The `bd add`, `bd update` commands in the agent template are approximations based on the Beads README. Exact syntax should be validated against the installed version during implementation.
- **Git Bash on Windows:** The scripts use bash constructs that should work in Git Bash, but edge cases (path separators, process management, background jobs) should be tested early.

## Prerequisites

- **Claude Code CLI** (`claude`) installed and authenticated
- **Beads** (`bd`) CLI installed (`npm install -g @beads/bd` or `brew install beads`)
- **Git** with worktree support (Git 2.5+)
- **Git Bash** on Windows (typically included with Git for Windows)

## Verification Plan

1. **Pool management:** Clone a test repo, create/remove worktrees, verify they share .git objects
2. **Task dispatch:** Create a Beads task, launch a simple agent (e.g., "list files and describe the project"), verify it completes and updates Beads
3. **Blocking flow:** Launch an agent designed to block (ask a question), verify notification fires, verify `continue.sh` resumes it with the answer
4. **Concurrent tasks:** Dispatch 3 tasks across 2 repos simultaneously, verify worktrees are created correctly and agents run in parallel
5. **Status command:** With multiple agents running, verify `/status` accurately reflects all task states from Beads
6. **Cleanup:** Complete a task, verify worktree is removed and pool clone remains
7. **Cross-platform:** Run the above on both Windows (Git Bash) and macOS
