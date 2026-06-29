# Output Contract

Return a single JSON object. Do not include markdown fences or explanation text. Required top-level fields are:

- `generatedAt`
- `dataAsOf`
- `privacyMode`
- `externalSignalStatus`
- `portfolio`
- `horizons`
- `marketOutlook`
- `sectors`
- `opportunities`
- `keyAssets`
- `assetTrends`
- `actions`
- `evidence`
- `warnings`
- `disclaimer`

## Required Content

- `horizons` must contain exactly three horizon objects: `short`, `medium`, and `long`.
- Every horizon must include `direction`, `confidence`, `rationale`, and `counterSignals`.
- `marketOutlook` must summarize 大盘 and relevant major asset classes before sector details. Include A-share broad indices, Hong Kong, US equities, bonds, commodities, or gold/黄金 when material. Each item needs `name`, `category`, `direction`, `confidence`, `rationale`, `evidenceIDs`, and `counterSignals`.
- `sectors` should be sector/theme level first, not a flat repeat of every asset. Each sector needs `name`, `exposureText`, `direction`, `confidence`, `rationale`, `evidenceIDs`, and `counterSignals`.
- `opportunities` should describe still-actionable opportunities outside or across current holdings, such as gold/黄金, broad index pullbacks, bond/cash alternatives, or sector rotation setups. Each opportunity needs `name`, `category`, `direction`, `confidence`, `rationale`, `triggerConditions`, `invalidatingConditions`, `evidenceIDs`, and `counterSignals`.
- `keyAssets` should include only trend-relevant assets, not every holding by default. Use sectors and warnings for low-importance or uncovered holdings. Each key asset needs `name`, `code`, `sector`, `impactText`, `horizons`, `rationale`, and `counterSignals`.
- `assetTrends` must include every held fund from the input context. Each item uses the same shape as `keyAssets`, but the purpose is full held-fund coverage rather than prioritization.
- Every `actions` item must include `kind`, `title`, `detail`, `targetName`, `confidence`, `triggerConditions`, and `invalidatingConditions`.
- `evidence` items need `sourceName`, `title`, `url`, `publishedAt`, `retrievedAt`, and `summary`. Use an empty array when no reliable evidence exists.
- `warnings` should name data gaps, stale signals, privacy-mode limits, concentration risk, or model uncertainty.
- `disclaimer` must state that the report is not investment advice and is for personal research only.

## Field Discipline

- Use enum values exactly as defined by `schema/trend-report.schema.json`.
- Use `null` for unavailable nullable fields such as `code`, `targetName`, `url`, or `publishedAt`.
- Keep strings concise and specific. Avoid generic filler like `继续观察市场变化` unless tied to a trigger or invalidating condition.
- Keep final reports focused: usually no more than 5 key assets, 5 actions, and 6 evidence items. `assetTrends` is the exception: it should cover every held fund.
- When the input is a chunk report, cover every held fund in that chunk through `assetTrends`; when the input is a final synthesis, deduplicate chunk assets, keep all held-fund `assetTrends`, and keep only the strongest portfolio-relevant `keyAssets`.
