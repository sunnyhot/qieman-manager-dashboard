# Agent-Based Trend Analysis

Date: 2026-06-24
Project: qieman-manager-dashboard
Target version: next release

## Goal

Replace direct OpenAI-compatible trend generation with local agent execution. The app should prepare a bounded investment-analysis work packet, invoke a selected local agent such as Claude CLI, Codex CLI, OpenClaw, Hermes, or a custom command, then validate and render the structured trend report.

The feature remains a research assistant. It must not execute trades, change plans, or present model output as guaranteed investment advice.

## Decisions

- Remove the direct model endpoint path from the trend-analysis product surface.
- Treat Claude CLI and Codex CLI as first-class supported agents.
- Treat OpenClaw, Hermes, and future tools as external agents through configurable command templates until their CLI contracts are known.
- Package trend-analysis guidance as a reusable skill pack passed to agents at runtime.
- Keep the app responsible for data preparation, privacy filtering, process supervision, schema validation, and UI rendering.
- Keep the agent responsible for reasoning and report generation only.

## Confirmed Scope

The first agent-based version supports:

- Automatic detection of installed agent commands.
- Manual agent selection and persisted default selection.
- Agent connection/check action that verifies command availability and structured-output capability where possible.
- Claude CLI execution through non-interactive print mode.
- Codex CLI execution through non-interactive exec mode.
- Custom external-agent execution through command templates.
- A local trend-analysis skill pack stored in the repository and copied into each run packet.
- Sanitized and full-detail portfolio input modes.
- JSON schema output validation before report rendering.
- Progress logs for data preparation, skill loading, agent launch, waiting, parsing, validation, and saving.
- Last successful report retention when a new agent run fails.

Out of scope for the first agent-based version:

- Running multiple agents and comparing their reports.
- Free-form chat with the agent from inside the app.
- Letting the agent modify repository files or user investment data.
- Automatic trading or plan mutation.
- Dedicated OpenClaw/Hermes adapters before their CLI options are verified.
- Shell-profile scraping for secret discovery.

## Architecture

Use a new provider boundary that models local agents instead of API endpoints.

Core components:

- `TrendAgentSettings`
  - Stores selected agent kind, command path, optional model/profile, timeout, and custom command template.
- `TrendAgentKind`
  - Cases: `claudeCLI`, `codexCLI`, `openClaw`, `hermes`, `custom`.
- `TrendAgentDetector`
  - Searches safe command locations and `PATH`.
  - Returns candidates with command path, detected version where cheap, capability notes, and warnings.
- `TrendAgentRunner`
  - Protocol used by `AppModel`.
  - Runs one trend request and returns raw report JSON plus execution metadata.
- `ClaudeTrendAgentRunner`
  - Invokes `claude -p` with JSON output and schema where supported.
- `CodexTrendAgentRunner`
  - Invokes `codex exec` with ephemeral execution and schema output.
- `ExternalTrendAgentRunner`
  - Invokes a user-configured command template for OpenClaw, Hermes, or another compatible agent.
- `TrendRunWorkspace`
  - Creates an isolated temporary directory for each analysis run.
  - Writes context, schema, skill instructions, prompt, and output paths.
  - Cleans up by default, with an optional debug-retain setting.
- `TrendAnalysisSkillPack`
  - Repository resource containing reusable instructions, schema, examples, and domain rules.

Existing components that remain:

- `TrendAnalysisContextBuilder`
- `TrendAnalysisChunker`
- `TrendPromptBuilder`, renamed or reduced toward run-packet prompt creation.
- `TrendAnalysisReport`
- `TrendAnalysisValidator`
- `TrendAnalysisStore`
- Trend UI panels and progress logs.

Components to remove or replace:

- `TrendAIClient`
- `TrendAIProviderSettings`
- OpenAI-compatible base URL/API key UI.
- Local API-key configuration import flow.

## Run Packet

Each analysis creates a temp directory with this shape:

```text
trend-run-<uuid>/
├── input/
│   ├── portfolio-context.json
│   ├── platform-signals.json
│   ├── watch-events.json
│   ├── pending-trades.json
│   └── metadata.json
├── skill/
│   ├── instructions.md
│   ├── domain-rules.md
│   ├── output-contract.md
│   └── examples.json
├── schema/
│   └── trend-report.schema.json
├── prompt.md
└── output/
    ├── trend-report.json
    └── agent-log.txt
```

The app writes only the data needed for analysis. In sanitized mode, it excludes real holding amounts, costs, profits, pending trade amounts, and plan amounts. In full-detail mode, it includes those values only after explicit user selection.

## Agent Commands

Claude CLI first-class runner:

```bash
claude -p \
  --output-format json \
  --json-schema schema/trend-report.schema.json \
  --no-session-persistence \
  --tools "" \
  --add-dir "$RUN_DIR" \
  "$(cat prompt.md)"
```

If a Claude version cannot enforce `--json-schema`, the runner still requests JSON and relies on app-side validation.

Codex CLI first-class runner:

```bash
codex exec \
  --ephemeral \
  --sandbox read-only \
  --ask-for-approval never \
  --cd "$RUN_DIR" \
  --output-schema schema/trend-report.schema.json \
  --output-last-message output/trend-report.json \
  -
```

The prompt is sent on stdin. Codex runs in the temp workspace, not in the project root.

External agent runner:

```text
{{command}} {{promptFile}} {{schemaFile}} {{outputFile}} {{runDir}}
```

The app expands placeholders and requires the command to produce valid `trend-report.json`. This supports OpenClaw, Hermes, and user-specific wrappers without blocking on their exact CLI contracts.

## Skill Pack

Create a repository-local skill pack dedicated to investment trend analysis. It is not a general Codex skill dependency; it is the domain instruction bundle passed to any supported agent.

Files:

- `skills/investment-trend-analysis/SKILL.md`
  - Concise trigger and workflow for Codex-compatible use.
- `skills/investment-trend-analysis/references/domain-rules.md`
  - Portfolio interpretation rules, risk language, Chinese market red-gain/green-loss convention, and non-advice boundaries.
- `skills/investment-trend-analysis/references/output-contract.md`
  - Required sections, rationale requirements, counter-signal rules, and evidence rules.
- `skills/investment-trend-analysis/assets/trend-report.schema.json`
  - JSON schema matching `TrendAnalysisReport`.
- `skills/investment-trend-analysis/assets/examples.json`
  - Small valid examples for sanitized and full-detail reports.

The app copies only the needed files into the run packet. The schema remains the final contract; skill text is guidance, not trusted output.

## Data Flow

Manual generation:

1. User opens `增强 -> 趋势`.
2. UI shows detected agents and selected default agent.
3. User chooses privacy mode and starts analysis.
4. `TrendAnalysisContextBuilder` builds app-side context.
5. `TrendRunWorkspace` writes the run packet.
6. Selected `TrendAgentRunner` launches the agent process.
7. App streams or polls progress logs.
8. Runner returns raw JSON output or a process error.
9. App decodes `TrendAnalysisReport`.
10. `TrendAnalysisValidator` rejects missing required fields or unsafe language.
11. App saves the report and updates the enhancement center.

Daily automatic generation uses the same path, but only runs when a configured agent is available and at most once per local day.

## UI Changes

Settings trend panel changes from model endpoint configuration to local agent configuration:

- `自动选择`
- `Claude CLI`
- `Codex CLI`
- `OpenClaw`
- `Hermes`
- `自定义`

Agent rows show:

- install status;
- command path;
- capability notes;
- last check result;
- selected/default state.

The old fields for base URL, API key, and OpenAI-compatible model are removed. A custom agent section provides command path, command template, and timeout.

The trend panel status text changes from model connection language to agent language, for example `Claude CLI 可用`, `Codex CLI 未登录或不可执行`, or `未检测到本地 Agent`.

## Error Handling

The app distinguishes:

- command not found;
- command not executable;
- login/auth missing;
- timeout;
- non-zero process exit;
- empty output;
- invalid JSON;
- schema mismatch;
- validation rejection;
- privacy packet creation failure.

On failure, the last successful report remains visible. The latest failure appears in progress logs and the enhancement action queue.

## Migration

Existing saved trend reports remain readable because `TrendAnalysisReport` stays stable.

Existing provider settings are not reused automatically. On first launch after migration:

- the app detects local agents;
- selected agent defaults to `automatic`;
- old direct endpoint credentials are ignored by trend generation;
- settings save rewrites the new agent settings format.

If preserving old settings is useful for debugging, the migration can keep a non-UI legacy blob for one release, but generation must not use it.

## Testing Strategy

Unit tests:

- agent detection for Claude, Codex, missing commands, and custom paths;
- settings load/save and legacy migration;
- run workspace writes expected files and respects sanitized/full-detail privacy;
- command construction for Claude, Codex, and external templates;
- process runner handles timeout, non-zero exit, empty output, and valid JSON;
- validator still rejects unsafe or incomplete reports.

Integration-style tests:

- fake executable returns a valid report and the app saves it;
- fake executable returns invalid JSON and the last successful report is preserved;
- fake slow executable emits waiting progress before timeout.

Manual verification:

- detect and run Claude CLI on the local machine;
- detect and run Codex CLI on the local machine;
- configure a fake custom agent command;
- verify old API-key settings no longer appear in the UI.

## Implementation Phases

1. Add agent settings, candidates, detector, and store migration.
2. Add run workspace and repository skill pack.
3. Add Claude runner and tests.
4. Add Codex runner and tests.
5. Add external command-template runner and tests.
6. Replace AppModel trend generation path.
7. Replace settings and trend-panel copy.
8. Remove direct client and API-key UI.
9. Run full Swift test suite and build the macOS app.

