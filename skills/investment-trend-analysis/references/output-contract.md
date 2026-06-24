# Output Contract

Return a single JSON object. Do not include markdown fences or explanation text. Required top-level fields are:

- `generatedAt`
- `dataAsOf`
- `privacyMode`
- `externalSignalStatus`
- `portfolio`
- `horizons`
- `sectors`
- `keyAssets`
- `actions`
- `evidence`
- `warnings`
- `disclaimer`

## Required Content

- `horizons` must contain exactly three horizon objects: `short`, `medium`, and `long`.
- Every horizon must include `direction`, `confidence`, `rationale`, and `counterSignals`.
- `sectors` should be sector/theme level first, not a flat repeat of every asset. Each sector needs `name`, `exposureText`, `direction`, `confidence`, `rationale`, `evidenceIDs`, and `counterSignals`.
- `keyAssets` should include only portfolio-relevant assets. Each key asset needs `name`, `code`, `sector`, `impactText`, `horizons`, `rationale`, and `counterSignals`.
- Every `actions` item must include `kind`, `title`, `detail`, `targetName`, `confidence`, `triggerConditions`, and `invalidatingConditions`.
- `evidence` items need `sourceName`, `title`, `url`, `publishedAt`, `retrievedAt`, and `summary`. Use an empty array when no reliable evidence exists.
- `warnings` should name data gaps, stale signals, privacy-mode limits, concentration risk, or model uncertainty.
- `disclaimer` must state that the report is not investment advice and is for personal research only.

## Field Discipline

- Use enum values exactly as defined by `schema/trend-report.schema.json`.
- Use `null` for unavailable nullable fields such as `code`, `targetName`, `url`, or `publishedAt`.
- Keep strings concise and specific. Avoid generic filler like `继续观察市场变化` unless tied to a trigger or invalidating condition.
- Keep final reports focused: usually no more than 5 key assets, 5 actions, and 6 evidence items.
