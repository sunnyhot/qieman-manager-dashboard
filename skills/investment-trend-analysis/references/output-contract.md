# Output Contract

Return a single JSON object. Required top-level fields are:

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

Every top-level horizon must include `rationale` and `counterSignals`. Every action must include `triggerConditions` and `invalidatingConditions`. Do not include markdown fences.
