# Agent Orchestration

A single-pane orchestration layer for managing multiple Claude Code sub-agents across many repositories simultaneously. You talk to one orchestrator session in natural language, and it dispatches work to invisible sub-agents working in isolated git worktrees.

## The Problem

When you manage 13-25+ repos across mixed platforms (Azure DevOps, GitHub, etc.), tasks arrive from everywhere: Jira, Azure DevOps, ad-hoc emails, meetings. Manually navigating to each project folder, spinning up Claude Code sessions, providing context, and juggling 4-6 concurrent tasks adds significant overhead.

## The Solution

Launch one Claude Code session from this directory. Describe tasks in natural language. The orchestrator handles the rest:

```
You:          "Product A has a billing bug — 500 errors on expired subscriptions"
Orchestrator: "Task AgentOrchestration-a3f8 created, agent dispatched to product-a."

You:          "Also, product-b needs its dependencies updated"
Orchestrator: "Task AgentOrchestration-b2c1 created, agent dispatched to product-b."

You:          "/status"
Orchestrator:
  AgentOrchestration-a3f8  product-a  fix-billing     BLOCKED
    "Should I consolidate the subscription check into middleware?"
  AgentOrchestration-b2c1  product-b  update-deps     WORKING
    Running test suite after dependency updates

You:          "For the billing bug, yes consolidate into middleware"
Orchestrator: "Relayed to AgentOrchestration-a3f8, agent continuing."
```

## Architecture

```
 You <---> Orchestrator (CLAUDE.md) <---> Bash Scripts <---> Sub-Agents (claude -p)
                  |                            |                    |
                  |                      pool-manage.sh        worktrees/
                  |                      dispatch.sh           pool/
                  |                      monitor.sh            logs/
                  |                      continue.sh
                  |
             Beads (bd)  <-- shared task state between orchestrator & agents
```

**Orchestrator:** A Claude Code session driven by `CLAUDE.md`. Your single interface — sub-agents are invisible.

**Repo Pool:** One full git clone per repo in `pool/`. Git worktrees provide instant (<1s) parallel working copies that share `.git` objects. No expensive re-cloning.

**Task State:** [Beads](https://github.com/steveyegge/beads) (Dolt-backed distributed task tracker) is the shared nervous system. Both the orchestrator and sub-agents read/write task state.

**Sub-Agents:** `claude -p` processes launched in worktree directories. They work autonomously, output `BLOCKED:` when they need input and `DONE:` when finished. A monitor script watches their logs and fires OS notifications.

**Communication Flow:**
1. You tell the orchestrator about a task
2. Orchestrator creates a Beads task, provisions a worktree, launches a sub-agent
3. Sub-agent works autonomously, updating Beads as it goes
4. If the agent needs input, it outputs `BLOCKED:` — monitor fires an OS notification
5. You answer through the orchestrator, which resumes the agent via `claude --continue`
6. When done, the agent outputs `DONE:` — worktree is cleaned up and released back to the pool

## Sub-Agent Permissions

Two modes per repo:

- **YOLO mode** (`--dangerously-skip-permissions`): No guardrails. Fast. For trusted repos.
- **Managed mode** (`--permission-mode dontAsk` + `--allowedTools`): Whitelisted tools only. Permissions grow organically — when an agent gets blocked on a tool, you approve it once and it's persisted.

## Self-Modifying Process

The entire system is files the orchestrator can edit: CLAUDE.md, YAML configs, Markdown templates, bash scripts. Ask the orchestrator to change its own behavior in natural language:

- *"Agents should run tests before marking done"* — edits `config/agent-template.md`
- *"Add a new repo called infra-tooling"* — edits `config/repos.yaml`
- *"Change default autonomy to high for product-b"* — edits `config/repos.yaml`

All changes are git-committed with descriptive messages. Revert if something goes wrong.

## Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`) — installed and authenticated
- [Dolt](https://docs.dolthub.com/introduction/installation) (`dolt`) — database backend for Beads
- [Beads](https://github.com/steveyegge/beads) (`bd`) — distributed task tracker
- Git 2.5+ with worktree support
- Git Bash on Windows (included with Git for Windows)

## Setup

```bash
# 1. Clone this repo
git clone <your-remote-url> AgentOrchestration
cd AgentOrchestration

# 2. Install dependencies
brew install dolt                  # macOS
npm install -g @beads/bd           # or: go install github.com/steveyegge/beads/cmd/bd@latest

# 3. Initialize Beads
bd init

# 4. Register your repos in config/repos.yaml
#    (or ask the orchestrator to do it with /pool add)

# 5. Clone repos into the pool
scripts/pool-manage.sh init

# 6. Launch the orchestrator
claude
```

## Orchestrator Commands

| Command | Description |
|---------|-------------|
| *(natural language)* | Describe a task — orchestrator dispatches an agent |
| `/status` | Show all tasks and their current state |
| `/status <id>` | Detailed view of a specific task |
| `/followup <id> <msg>` | Send context or answers to a specific agent |
| `/pool` | Show repo pool status |
| `/pool add <name> <url>` | Register and clone a new repo |
| `/pool fetch` | Fetch latest on all pool clones |
| `/done <id>` | Review completed work, clean up worktree |
| `/cancel <id>` | Kill agent, clean up, close task |
| `/permissions <repo>` | Show permission profile for a repo |
| `/permissions <repo> add <tool>` | Add an allowed tool |

## Directory Structure

```
AgentOrchestration/
├── CLAUDE.md                   # Orchestrator brain
├── config/
│   ├── repos.yaml              # Repo registry
│   ├── defaults.yaml           # Default settings
│   └── agent-template.md       # Sub-agent prompt template
├── scripts/
│   ├── pool-manage.sh          # Repo pool & worktree lifecycle
│   ├── dispatch.sh             # Launch sub-agents
│   ├── monitor.sh              # Watch agent output, fire notifications
│   ├── continue.sh             # Resume blocked agents
│   ├── notify.sh               # Cross-platform OS notifications
│   └── parse-yaml.sh           # Config file parser
├── pool/                       # Pre-cloned repos (gitignored)
├── worktrees/                  # Active git worktrees (gitignored)
├── logs/                       # Agent output logs (gitignored)
└── tests/                      # Test suite
```

## Configuration

### Adding a repo (`config/repos.yaml`)

```yaml
repos:
  my-service:
    url: https://github.com/org/my-service
    platform: github
    default_branch: main
    pre_clone: true
    max_worktrees: 3
    permission_mode: managed    # or "yolo"
    autonomy: medium            # high, medium, or low
    allowed_tools:
      - "Read"
      - "Edit"
      - "Write"
      - "Bash(git *)"
      - "Bash(npm *)"
    denied_tools:
      - "Bash(git push --force *)"
```

### Autonomy levels

- **High:** Agent implements, tests, commits, pushes, and opens a PR. You review the PR.
- **Medium** (default): Agent implements and tests freely. Blocks on architectural decisions and before PRs.
- **Low:** Agent presents a plan before writing code. Blocks on design, implementation, and PRs.

## Running Tests

```bash
# All tests
bash tests/test-parse-yaml.sh
bash tests/test-pool-manage.sh
bash tests/test-notify.sh
bash tests/test-monitor.sh
bash tests/test-dispatch.sh
bash tests/test-continue.sh
bash tests/test-integration.sh
```

## Cross-Platform Support

- **Windows:** Scripts run in Git Bash. Notifications use PowerShell toast notifications.
- **macOS:** Native bash. Notifications use `osascript`.
- **Linux:** Native bash. Notifications use `notify-send` (falls back to terminal output).
