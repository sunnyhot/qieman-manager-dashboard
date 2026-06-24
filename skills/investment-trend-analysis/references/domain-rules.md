# Domain Rules

Treat the report as personal research, not investment advice. Chinese market color convention is red for gains and green for losses.

## Analysis Workflow

1. **portfolio baseline**: summarize asset count, holding count, active plans, pending trades, concentration hints, and whether values are sanitized or full detail.
2. **sector-first**: judge broad sector exposure before individual funds or stocks. Group similar assets by sector/theme, then choose only the most portfolio-relevant key assets.
3. **manager and platform signals**: weigh Qieman manager posts, platform launch or rebalancing events, holdings changes, plan cadence, and watch summaries before weaker market chatter.
4. **horizon split**: give separate short, medium, and long reasoning. Short is tactical confirmation, medium is trend and policy/valuation balance, long is structural allocation quality.
5. **risk bridge**: connect judgments to portfolio risk, pending cash, active plans, and asset overlap. Explain when diversification is real versus duplicated exposure.
6. **conditional actions**: every action must be conditional. Write concrete `triggerConditions` and `invalidatingConditions` so the user knows what would confirm or break the view.
7. **counter-signal first check**: for every confident view, add at least one opposite signal that would force reconsideration.

## Evidence Discipline

- Use high-quality evidence first: local portfolio facts, platform holdings/rebalancing data, manager statements, valuation snapshots, policy or macro signals with dates, and clearly material asset-level data.
- Distinguish facts from judgment. Start rationales from observed data, then state interpretation.
- If external access is reliable, cite evidence with source name, title, timestamp, URL if available, retrievedAt, and a short summary.
- If external data is missing, stale, or partial, lower confidence and set `externalSignalStatus` to `unavailable`, `stale`, or `partial`; do not fill gaps with invented news.
- Prefer fewer, stronger evidence items over many weak ones.

## Writing Rules

- Use Chinese output.
- Do not claim guaranteed returns.
- Do not use mandatory language such as `必须买入`, `必须卖出`, `保证收益`, or `一定上涨`.
- Prefer `可考虑`, `关注`, `等待确认`, `若...则...`, and `反之...`.
