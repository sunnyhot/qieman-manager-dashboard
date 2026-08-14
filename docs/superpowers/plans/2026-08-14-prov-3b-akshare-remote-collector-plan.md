# PROV-3b AKShare Remote Collector 实施计划

> 面向 Coder 与 Reviewer-Opus。每个任务都必须先写/更新测试，再实现最小代码，再跑本任务命令。不要把本文中的 VPS、域名、真实 key 或数据许可当成已经具备。

**Goal：** 在 `feature/investment-intelligence-v2` 上实现签名的 AKShare 远程 JSONL staging、App 端验签/缓存/三档降级，以及 Python↔Swift 契约测试，同时保持 App 零 Python 运行时依赖。

**Design：** Python Collector 由固定 timer 低频抓公开 allowlist，精确去重并原子发布 content-addressed JSONL objects + Ed25519 signed manifest。Swift 端按固定 `/v1` contract 拉取，先验签/防重放，再验 object hash、PROV-1 Reader/SchemaValidator，最后由独立 coordinator 走 remote/native/unavailable。

**Baseline：** 本计划基于 `origin/feature/investment-intelligence-v2` commit `81c5a59fb25788229c7b8564489d5ffad64446a6`。实施时目标分支可能前进，但必须确认该 commit 是祖先，并重新核对本文列出的前置状态。

**Related design：** `docs/superpowers/specs/2026-08-14-prov-3b-akshare-remote-collector-design.md`

## 0. 执行规则与依赖图

### 0.1 工作类型

- **OFFLINE**：只依赖仓库、固定 fixture、test key 和注入 transport；可在没有 VPS/域名/生产 secret/上游网络时完成。
- **EXTERNAL**：需要安装 Python dependencies、真实上游、VPS、域名、nginx、Cloudflare 或生产 secret。
- **MANUAL GATE**：需要 owner 对成本、许可、密钥或产品默认行为做决定；没有确认时必须停在 gate，不得伪造“已完成”。

### 0.2 依赖图

```text
Task 1 ADR/contract decision
  ├─> Task 2 Provider payload codec ─┐
  ├─> Task 3 JSON schemas/fixtures ──┼─> Task 5 Python core/publisher
  └─> Task 4 ProviderHealth monitor ─┤
                                      ├─> Task 6 Python AKShare planner/adapters
Task 3 ─> Task 7 Swift verifier/HTTP ┤
Task 4 + 7 ─> Task 8 cache/state ─────┤
Task 2 + 7 + 8 ─> Task 9 RemoteStagingProvider
Task 4 + 9 ─> Task 10 fallback coordinator
Task 5..10 ─> Task 11 offline full-chain acceptance
Task 5 + 6 ─> Task 12 deploy artifacts
Task 11 + 12 + Manual Gates ─> Task 13 VPS/nginx/live acceptance
Task 11 (+ Task 13 evidence when available) ─> Task 14 delivery
```

PROV-3b 离线实现 PR 可以在 Task 11 后提交审查；没有 Task 13 证据时，issue/rollout/DATA010 必须仍写“真实部署未验收”，不能签成完整生产可用。

### 0.3 全局禁区

- 不新增或引用 `macos-app/Core/InvestmentIntelligence/`、`macos-app/Core/TrendResearch/`。
- V2 Swift 不 `import SwiftUI` / `import AppKit`。
- 不新增 SQLite/GRDB 或 Factor 代码；M2 仍是独立 go/no-go。
- Python 服务端不读取 App 用户目录、Cookie、持仓、资产、设备信息。
- 不提交生产 auth key、private signing key、真实 secret 文件或带 secret 的日志。
- 不把 failed/unknown 数据写成 0、空对象或“最后值就是最新值”。

## Task 1 — 先冻结 ADR 与实现边界

**类型：OFFLINE；DATA010 保持 Proposed，直到 Task 13 通过。**

**Files：**

- Modify: `docs/adr/DATA010-remote-public-data-collector.md`
- Modify: `docs/adr/DATA007-external-collector-isolation.md`
- Modify: `docs/adr/FREE001-zero-paid-dependency.md`
- Modify: `AGENTS.md`
- Review only: `docs/investment-intelligence-rollout.md`

### Step 1.1 — 重核基线

```bash
git fetch origin feature/investment-intelligence-v2
git merge-base --is-ancestor 81c5a59fb25788229c7b8564489d5ffad64446a6 HEAD
git rev-parse HEAD
git rev-parse origin/feature/investment-intelligence-v2
rg -n 'PROV-3b|PROV-1|PROV-8|M2 当前|M3 进行中' docs/investment-intelligence-rollout.md
rg -n 'ProviderHealthMonitor|ProviderPayloadCodec' macos-app/InvestmentIntelligenceV2 macos-app/Tests
```

验收：基线 commit 是当前实现分支祖先；若 rollout/前置实现已变化，先更新 Spec/Plan 的事实表，再写代码。

### Step 1.2 — 修订 ADR 内容，但不提前 Accept

DATA010 必须增加：

- mandatory Ed25519 envelope、manifest generation、防 replay/equivocation、固定 `/v1` 版本门；
- App static access key 的真实能力边界；
- Cloudflare cache 不得绕过 origin auth；
- 同机 signing key 只能防局部 web/CDN 篡改，不能防 root 失陷；
- rollback 必须以更高 generation 重发旧 objects；
- 真实验收完成前 Status 仍是 Proposed。

DATA007 澄清 iOS 不含 Python 但可读取 PROV-3b；FREE001/AGENTS.md 记录 VPS 受控付费与 Python 仅存在于远程进程，不改变 App 纯 Swift runtime。

### Step 1.3 — ADR 文档审查

```bash
rg -n 'Status|Ed25519|generation|replay|root|X-Collector-Key|iOS|VPS' \
  docs/adr/DATA010-remote-public-data-collector.md \
  docs/adr/DATA007-external-collector-isolation.md \
  docs/adr/FREE001-zero-paid-dependency.md AGENTS.md
git diff --check
```

验收：所有例外与威胁边界可从 ADR/AGENTS 独立读懂；没有把 DATA010 改为 Accepted。

## Task 2 — 收口 PROV-1 raw payload codec

**类型：OFFLINE；依赖 Task 1。**

**Files：**

- Create: `macos-app/InvestmentIntelligenceV2/Providers/ProviderPayloadCodec.swift`
- Modify: `macos-app/InvestmentIntelligenceV2/Providers/ObservationFactory.swift`
- Modify: `macos-app/InvestmentIntelligenceV2/Providers/ProviderRecordSchemaValidator.swift`
- Modify only where raw payload is encoded:
  - `macos-app/InvestmentIntelligenceV2/Providers/EastmoneyResponseParser.swift`
  - `macos-app/InvestmentIntelligenceV2/Providers/EastmoneyHoldingRecordBuilder.swift`
  - `macos-app/InvestmentIntelligenceV2/Providers/StooqResponseParser.swift`
  - `macos-app/InvestmentIntelligenceV2/Providers/FREDResponseParser.swift`
  - `macos-app/InvestmentIntelligenceV2/Providers/AlphaVantageResponseParser.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/ProviderPayloadCodecTests.swift`
- Modify: `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/ProviderStagingTests.swift`

### Step 2.1 — 先写 codec 失败测试

覆盖：

- 新编码的 `CorporateActionPayload.Date` 是无小数秒 UTC RFC 3339，不是 Foundation reference-date number；
- decoder 接受新 RFC 3339；只为旧 spool/fixture 接受 legacy reference-date number；
- encoder 永远不再写 legacy number；
- Decimal finite，真实 0 保留；optional missing 可 decode；
- Validator 与 Factory 注入同一 decoder 后结论一致。

```bash
swift test --package-path macos-app --filter 'ProviderPayloadCodecTests|ProviderRecordSchemaValidatorTests'
```

预期：缺少 `ProviderPayloadCodec` 或日期格式断言失败。

### Step 2.2 — 实现共享 codec

接口骨架：

```swift
enum ProviderPayloadCodec {
    static func makeEncoder() -> JSONEncoder
    static func makeDecoder(acceptLegacyReferenceDate: Bool = true) -> JSONDecoder

    static func encode<T: Encodable & Sendable>(_ value: T) throws -> Data
    static func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> T
}
```

编码日期只用 UTC RFC 3339 seconds；legacy 只在 decoder 的明确兼容分支。将 Factory/Validator 的默认 decoder 改成共享 codec，并替换 V2 Adapter 中直接 `JSONEncoder().encode(payload)` 的位置。不要改变外层 `ProviderStaging.defaultEncoder/defaultDecoder` 的 ISO-8601 对称契约。

### Step 2.3 — 回归

```bash
swift test --package-path macos-app --filter 'ProviderPayloadCodecTests|ProviderStagingTests|StooqAdapterTests|FREDAdapterTests|AlphaVantageAdapterTests|EastmoneyHoldingProviderTests'
```

验收：新 payload 输出统一；已有 staging/adapters 全绿；legacy 读取有测试但没有 legacy 写入路径。

## Task 3 — 建立唯一 wire schema 与 golden fixtures

**类型：OFFLINE；依赖 Task 1，可与 Task 2 并行。**

**Files：**

- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Contract/provider-record-v1.schema.json`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Contract/manifest-v1.schema.json`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Contract/README.md`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Contract/Fixtures/provider-record-all-kinds.v1.jsonl`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Contract/Fixtures/provider-record-revision.v1.jsonl`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Contract/Fixtures/manifest-payload.v1.json`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Contract/Fixtures/manifest-envelope-test-key.v1.json`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Contract/Fixtures/invalid/*.json`
- Modify: `macos-app/Package.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/RemoteStagingContractTests.swift`

### Step 3.1 — 定义 schema

`additionalProperties: false` 用在 envelope/manifest 和所有 payload object。冻结：

- outer camelCase field names 与 enum raw values；
- `rawPayload` 为 padded standard Base64；
- outer/payload dates 为 `YYYY-MM-DDTHH:mm:ssZ`；
- plain finite decimal lexical policy（JSON Schema 不能完全检查的词法约束由 Python/Swift codec tests 补）；
- optional key 缺失，不以 null/0 冒充；
- manifest path/sha/size/count/time/generation bounds。

`README.md` 必须写“schema 是权威，Swift/Python 是实现”。test key fixture 顶部或邻近 README 明确 `TEST ONLY — NEVER DEPLOY`。

### Step 3.2 — SwiftPM 排除 server files

在 `macos-app/Package.swift` executable target 的 `exclude` 中加入：

```swift
"InvestmentIntelligenceV2/RemoteCollector"
```

测试通过 `#filePath` 解析 repository fixture，或增加明确 test resource copy；不得复制出第二份会漂移的 schema/fixture。

### Step 3.3 — 写 Swift contract tests

测试把 all-kinds fixture 交给 `ProviderStagingReader`、`ProviderRecordSchemaValidator` 和 `ProviderPayloadCodec`，断言 revision 两条均保留。此 Task 只断言现有 PROV-1 能识别的 invalid（坏 enum/Base64/时间序/payload-kind）；未知 key 等 `additionalProperties: false` 负例留给 Task 7 的严格 wire preflight，避免假称 Swift Codable 会拒绝未知字段。

```bash
swift test --package-path macos-app --filter RemoteStagingContractTests
swift build --package-path macos-app
```

验收：SwiftPM 无 RemoteCollector unhandled-file warning；唯一 fixture 被 Swift 直接消费。

## Task 4 — 实现 PROV-8 最小 Monitor 前置

**类型：OFFLINE；依赖 Task 1。若 PROV-8 由另一 PR 实现，先 rebase 并适配，不造第二套 monitor。**

**Files：**

- Create: `macos-app/InvestmentIntelligenceV2/Observations/ProviderHealthMonitor.swift`
- Modify only if needed: `macos-app/InvestmentIntelligenceV2/Observations/ProviderHealth.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/ProviderHealthMonitorTests.swift`

### Step 4.1 — 先写状态阈值测试

事件至少包括：

```swift
enum ProviderHealthEvent: Sendable, Equatable {
    case success(at: Date, latency: Duration)
    case transientFailure(at: Date)
    case rateLimited(at: Date)
    case authenticationRejected(at: Date)
    case schemaDrift(at: Date)
    case integrityFailure(at: Date, reason: IntegrityFailureReason)
    case cacheSupplemental(at: Date, age: Duration)
    case quota(QuotaSnapshot, at: Date)
}

protocol ProviderHealthRecording: Sendable {
    func record(_ event: ProviderHealthEvent) async
    func snapshot(for providerID: DataProviderID) async -> ProviderHealth
}
```

固定初始阈值并测试：窗口最近 20 次；quota=0 或 auth/integrity hard failure → unavailable；至少 5 次后 success rate < 0.5 或连续 3 次失败 → unavailable；success rate < 0.9、rate limit、schema drift、quota≤10% 或 supplemental cache → degraded；完整成功恢复按窗口渐进，不因一次 success 瞬间洗掉安全失败。

### Step 4.2 — actor 实现

用 actor 保存有界事件窗口；`ProviderHealth` 是派生快照，不进 GRDB。详细 failure reason 可保留在有界内存事件中，禁止把 auth key/raw payload 放入事件。

### Step 4.3 — 验证

```bash
swift test --package-path macos-app --filter 'ProviderHealthTests|ProviderHealthMonitorTests'
```

验收：既有 DOM-8 tests 不退化；PROV-3b 可依赖真实 monitor protocol，不再手工构造状态冒充监控。

## Task 5 — Python contract、签名、合并与原子 publisher

**类型：OFFLINE（安装依赖本身需要 package network）；依赖 Task 2、3。**

**Files：**

- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/pyproject.toml`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/requirements.lock`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Sources/remote_collector/__init__.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Sources/remote_collector/models.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Sources/remote_collector/codecs.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Sources/remote_collector/publisher.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Sources/remote_collector/signer.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Sources/remote_collector/cli.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Tests/test_codecs.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Tests/test_publisher.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Tests/test_signer.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Tests/test_public_data_boundary.py`

### Step 5.1 — 建 isolated venv 并锁依赖

实现时选择与当日 AKShare 兼容的 exact versions，生成带 hashes 的 `requirements.lock`；不要从本文猜一个未来版本。允许的 runtime dependencies 仅限 AKShare 及其必要依赖、Ed25519/JCS/schema validation。每个新增库在 PR 写许可与零订阅/零按量计费声明。

```bash
python3 -m venv macos-app/InvestmentIntelligenceV2/RemoteCollector/.venv
macos-app/InvestmentIntelligenceV2/RemoteCollector/.venv/bin/python -m pip install --require-hashes \
  -r macos-app/InvestmentIntelligenceV2/RemoteCollector/requirements.lock
```

`.venv/` 必须被 ignore，不能提交。

### Step 5.2 — 先写 fixture/签名/publisher 失败测试

覆盖：

- Python 读取 all-kinds golden 并按 schema 通过；invalid 全拒；
- `encode_provider_record()` bytes 与 golden line 完全相等；
- record key 忽略 ingestedAt，但保留 publishedAt/payload revision；
- signer 产生与 golden envelope 一致的 test vector；bit flip 失败；
- publisher crash 在 envelope swap 前时旧 publication 不变；
- path/size/count 上限；
- public-data boundary 扫描 config/model，不允许 cookie/portfolio/user upload 字段。

```bash
macos-app/InvestmentIntelligenceV2/RemoteCollector/.venv/bin/python -m unittest discover \
  -s macos-app/InvestmentIntelligenceV2/RemoteCollector/Tests -p 'test_*.py' -v
```

预期：modules 尚不存在或断言失败。

### Step 5.3 — 实现 canonical codec 与 model

关键骨架：

```python
@dataclass(frozen=True)
class ProviderRecordV1:
    provider_id: str
    provider_code: ProviderCodeV1
    effective_at: datetime
    published_at: datetime
    ingested_at: datetime
    kind: ProviderRecordKindV1
    raw_payload: bytes
    reliability_class: str
    jurisdiction: str

def encode_provider_record(record: ProviderRecordV1) -> bytes: ...
def record_key(record: ProviderRecordV1) -> str: ...
def canonical_manifest_bytes(manifest: ManifestV1) -> bytes: ...
```

所有 datetime 强制 aware UTC；Decimal 非 finite 立即错误；raw payload 与 outer JSON 均 deterministic。不要在 Adapter 层计算 `availableAt` 或 canonical identity。

### Step 5.4 — 实现 signer/publisher

签名输入固定为 `b"qieman.remote-staging.manifest.v1\0" + payload_bytes`。Publisher 使用 run 私有目录、hash object、`fsync`、rename；生成 envelope 前所有 partitions 都完成验证。私钥只接受明确 CLI/env credential path，不支持把 key literal 写进 config。

### Step 5.5 — 验证

```bash
macos-app/InvestmentIntelligenceV2/RemoteCollector/.venv/bin/python -m unittest discover \
  -s macos-app/InvestmentIntelligenceV2/RemoteCollector/Tests -p 'test_*.py' -v
git grep -nE 'BEGIN (OPENSSH|PRIVATE KEY)|X-Collector-Key:' -- \
  macos-app/InvestmentIntelligenceV2/RemoteCollector ':!**/Fixtures/**'
```

验收：golden bytes/签名固定；无 production secret；失败 publication 不影响旧 envelope。

## Task 6 — Python AKShare dataset、缺口 planner 与礼貌调度

**类型：核心逻辑 OFFLINE；真实 AKShare smoke 是 EXTERNAL。依赖 Task 5。**

**Files：**

- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Sources/remote_collector/datasets.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Sources/remote_collector/planner.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Sources/remote_collector/collector.py`
- Modify: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Sources/remote_collector/cli.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Tests/test_datasets.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Tests/test_planner.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Tests/test_collector.py`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Contract/datasets-v1.example.json`

### Step 6.1 — 先写 fake upstream 测试

用 injected fake AKShare facade，不导入真实网络：

- 相同 `(dataset, code, range, upstream)` 只调用一次；
- 已覆盖历史不重抓；同 partition lock 拒绝重入；
- 每 host concurrency 默认 1、硬上限 2；jitter 用 injected random/clock 测试；
- 429/503/Retry-After 结束/延后 partition，不 tight loop；
- 字段漂移只阻止该 partition 发布并产生诊断；
- 初始生产 allowlist 以 `enabled: false` 起步；未获人工批准不能靠 CLI 参数绕过；
- config 不接受 cookie、用户 symbol POST 或私有数据 path。

### Step 6.2 — 实现 dataset interface

```python
class PublicDataset(Protocol):
    name: str
    kind: ProviderRecordKindV1
    def plan(self, coverage: CoverageIndex, now: datetime) -> Iterable[FetchUnit]: ...
    def fetch(self, unit: FetchUnit, upstream: AKShareFacade) -> Iterable[ProviderRecordV1]: ...

class AKShareFacade(Protocol):
    # 只暴露已批准的公开日级方法；无 cookie/user context 参数
    ...
```

首批 adapter 只实现 owner 已批准的 canary dataset；未确认的股票/ETF/指数/NAV/Macro 保留 disabled 配置和明确原因，不写假响应。

### Step 6.3 — 离线验证

```bash
macos-app/InvestmentIntelligenceV2/RemoteCollector/.venv/bin/python -m unittest discover \
  -s macos-app/InvestmentIntelligenceV2/RemoteCollector/Tests -p 'test_*.py' -v
```

### Step 6.4 — 真实 upstream smoke（EXTERNAL，不是默认 CI）

```bash
macos-app/InvestmentIntelligenceV2/RemoteCollector/.venv/bin/python -m remote_collector.cli \
  collect --config <approved-canary-config> --dry-run --network
```

验收：脱敏日志记录计划/调用/429/schema 统计；不发布生产 envelope；失败如实报告。没有许可批准时跳过本 step，并在交付中写明。

## Task 7 — Swift manifest、Ed25519 verifier 与有界 HTTP transport

**类型：OFFLINE；依赖 Task 3。**

**Files：**

- Create: `macos-app/InvestmentIntelligenceV2/Providers/RemoteStagingContract.swift`
- Create: `macos-app/InvestmentIntelligenceV2/Providers/RemoteStagingVerifier.swift`
- Create: `macos-app/InvestmentIntelligenceV2/Providers/RemoteStagingTransport.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/RemoteStagingVerifierTests.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/RemoteStagingTransportTests.swift`

### Step 7.1 — 先写 verifier negative matrix

测试：golden dual signature、unknown signing key、wrong algorithm、bit flip、expired/not-yet-valid、clock >5m、unsupported versions、lower generation、same generation different hash、path traversal/absolute URL、oversize envelope/object/list、cross-origin redirect；同时覆盖 JSONL outer/raw-payload 未知 key、错误 JSON 类型、非 canonical RFC 3339/Base64 和超长行。

```bash
swift test --package-path macos-app --filter 'RemoteStagingVerifierTests|RemoteStagingTransportTests'
```

预期：类型缺失或测试失败。

### Step 7.2 — 实现 DTO 与 verifier

使用 `CryptoKit.Curve25519.Signing.PublicKey` 验 Ed25519。公钥通过 injected `RemoteSigningKeySet` 提供；test key 不得进入 production default。验签在 JSON decode manifest 之前完成（envelope 基本字段除外），签名输入与 Python 完全一致。

在同文件实现 `RemoteStagingWireValidator`，按 shared schema 镜像检查精确 key/type/enum/date/Base64/line-size。它只做 transport preflight，不替代 `ProviderStagingReader`、`ProviderRecordSchemaValidator` 或 ObservationFactory。

```swift
struct RemoteManifestWatermark: Codable, Sendable, Equatable {
    let generation: UInt64
    let payloadSHA256: String
}

struct RemoteSigningKey: Sendable {
    let keyID: String
    let rawPublicKey: Data
    let activeFrom: Date
    let notAfter: Date?
}
```

### Step 7.3 — 实现 HTTP transport

用 injected `URLSession`/protocol fake。强制 HTTPS、base origin、header auth、5s/15s timeout、body size guard、状态码分类与最多一次 retry。403/404/integrity/version 不 retry；429 只在 `Retry-After <= 2s` 且总预算允许时 retry。

### Step 7.4 — 验证

```bash
swift test --package-path macos-app --filter 'RemoteStagingContractTests|RemoteStagingVerifierTests|RemoteStagingTransportTests'
```

验收：Swift 对 Python golden envelope 验签成功；所有攻击/上限 fixture fail-closed。

## Task 8 — Verified cache、高水位与 circuit state

**类型：OFFLINE；依赖 Task 4、7。**

**Files：**

- Create: `macos-app/InvestmentIntelligenceV2/Providers/RemoteStagingCache.swift`
- Create: `macos-app/InvestmentIntelligenceV2/Providers/RemoteProviderStateMachine.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/RemoteStagingCacheTests.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/RemoteProviderStateMachineTests.swift`

### Step 8.1 — 先写 crash/tamper/state tests

覆盖：

- 未验证 temp file 永不出现在 verified objects；
- hash mismatch/Reader fail 时旧 manifest 与高水位不变；
- same/lower generation 拒绝；App 重启高水位保留；
- state 主副本一个损坏仍恢复，两个都损坏时 fail-closed，不接受低 generation；
- LRU 不删当前/最近 manifest 唯一引用；
- circuit 3 次失败 open 15m，half-open 单探针，失败按 30m..6h，成功 reset；
- integrity publication digest 被隔离，不 tight retry；
- file permissions 0700/0600（在支持 POSIX 的测试环境断言）。

### Step 8.2 — 实现 actor/cache 与 state machine

Cache root 由调用方注入；只用 Foundation 文件 API，不引用 `ApplicationDataController`。state 用 atomic temp+rename 和 checksummed primary/backup；verified object 以 SHA-256 命名且 immutable。

### Step 8.3 — 验证

```bash
swift test --package-path macos-app --filter 'RemoteStagingCacheTests|RemoteProviderStateMachineTests'
```

验收：crash/tamper 不会提升未验证 bytes；restart 不造成 replay window。

## Task 9 — RemoteStagingProvider 全链

**类型：OFFLINE；依赖 Task 2、4、7、8。**

**Files：**

- Create: `macos-app/InvestmentIntelligenceV2/Providers/RemoteStagingProvider.swift`
- Modify comment only: `macos-app/InvestmentIntelligenceV2/Identity/CanonicalIDs.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/RemoteStagingProviderTests.swift`

### Step 9.1 — 先写状态与 pipeline tests

场景：

- fresh/full publication → `remoteAvailable`；
- valid cache + refresh 503/circuit/stale/partial → `supplemental`；
- 无 cache/signature fail/hash fail/schema fail/no coverage → `unavailable`；
- integrity/schema 失败不覆盖旧 cache；
- manifest partition selector 只下载目标 code bucket/time range；
- object 中非 `.akshare` provider、range/bucket/dataset 不符 → 整 partition 拒收；
- Python JSONL → `ProviderStagingReader` → `ProviderRecordSchemaValidator` → payload codec；
- 16 MiB/object、64 MiB/request、30s 总预算生效。

### Step 9.2 — 实现 orchestrated fetch

严格遵循 Spec §10.4 顺序。先对 hash 验证后的 bytes 跑 `RemoteStagingWireValidator`；现有 Reader 只接受 URL，因此再把 bounded temp/object URL 交给 Reader，不另写第二套 `ProviderRecord` decoder。Validator invalid 非空时 v1 整 partition fail-closed并记录 schema drift。同步更新 `.akshare` 注释为本地/远程进程外 Collector，不改变 raw value。

```swift
enum RemoteProviderMode: String, Sendable, Codable {
    case remoteAvailable, supplemental, unavailable
}

struct RemoteFetchOutcome: Sendable {
    let mode: RemoteProviderMode
    let records: [ProviderRecord]
    let coveredRange: ClosedRange<Date>?
    let reason: RemoteFallbackReason?
    let manifestGeneration: UInt64?
}
```

### Step 9.3 — 验证

```bash
swift test --package-path macos-app --filter RemoteStagingProviderTests
```

验收：状态、cache、health events 和 records 一致；remote provider 从不返回伪造 native provider record。

## Task 10 — Native fallback coordinator 与 unknown 语义

**类型：OFFLINE；依赖 Task 4、9。**

**Files：**

- Create: `macos-app/InvestmentIntelligenceV2/Providers/ProviderFallbackCoordinator.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/ProviderFallbackCoordinatorTests.swift`

### Step 10.1 — 写优先级/缺口失败测试

- remoteAvailable 完整覆盖时不调用 native；
- supplemental 只对 uncovered ranges 调 native，不全量重复抓；
- remote unavailable 调 native；
- native 403/quota/schema/network 失败后返回明确 gap/unavailable，不 throw 崩整批；
- 同一日期 remote/native 都有时不在 coordinator 静默改 canonical reliability；保留 records 来源，交后续 pipeline tie-break；
- 真实 0 保留，missing 不变 0。

### Step 10.2 — 实现 coordinator

建议返回：

```swift
struct ProviderCoverageGap: Sendable, Equatable {
    let range: ClosedRange<Date>
    let reason: ProviderGapReason
}

struct ProviderChainResult: Sendable {
    let records: [ProviderRecord]
    let remoteMode: RemoteProviderMode
    let gaps: [ProviderCoverageGap]
    let attempts: [ProviderAttemptSummary]
}
```

native providers 通过 `[any ProviderAdapter]` 注入；映射哪个 dataset/code 用哪个 native secondary 是配置，不硬编码 UI/AppModel。

### Step 10.3 — 验证

```bash
swift test --package-path macos-app --filter 'ProviderFallbackCoordinatorTests|ProviderHealthMonitorTests'
```

验收：三档链路、部分覆盖和双失败都可审计；无默认值伪造。

## Task 11 — 跨语言与离线 E2E 收口

**类型：OFFLINE；依赖 Task 5–10。**

**Files：**

- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Scripts/verify_contract.sh`
- Create: `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/RemoteStagingEndToEndTests.swift`
- Modify: `.github/workflows/ci.yml`

### Step 11.1 — 建单一 contract 命令

脚本只编排命令，不复制 fixture：

```bash
python -m unittest discover -s <RemoteCollector/Tests> -p 'test_*.py' -v
swift test --package-path macos-app --filter \
  'ProviderPayloadCodecTests|RemoteStagingContractTests|RemoteStagingVerifierTests|RemoteStagingEndToEndTests'
```

CI 增加 Python job/step：按 lock+hash 安装、跑 Python tests，再跑 Swift contract。CI 中使用 test key fixture，绝不注入生产 secret或访问真实 AKShare/VPS。

### Step 11.2 — E2E fixture server

用 `URLProtocol` 或本地注入 transport 返回同一 golden envelope/object，验证：

```text
HTTP response
→ Ed25519
→ generation/version/path/size
→ SHA-256
→ verified cache
→ RemoteStagingWireValidator
→ ProviderStagingReader
→ ProviderRecordSchemaValidator
→ RemoteStagingProvider mode
→ ProviderFallbackCoordinator
```

再注入 503、403、429、timeout、signature/hash/schema/replay 各一条端到端负例。

### Step 11.3 — 全量离线验证

```bash
bash macos-app/InvestmentIntelligenceV2/RemoteCollector/Scripts/verify_contract.sh
swift test --package-path macos-app
swift build --package-path macos-app
git diff --check
rg -n 'import (SwiftUI|AppKit)|Core/InvestmentIntelligence|Core/TrendResearch' \
  macos-app/InvestmentIntelligenceV2
```

验收：Python/Swift/E2E/全量 Swift 全绿；禁止 import 搜索无结果；网络/VPS tests 不在默认 CI。

## Task 12 — nginx/systemd 部署件与离线配置检查

**类型：部署件编写 OFFLINE；真实主机执行 EXTERNAL。依赖 Task 5、6。**

**Files：**

- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Deploy/nginx/collector.conf`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Deploy/nginx/collector-secrets.conf.example`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Deploy/systemd/qieman-collector.service`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Deploy/systemd/qieman-collector.timer`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Deploy/systemd/qieman-collector.env.example`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Deploy/README.md`
- Create: `macos-app/InvestmentIntelligenceV2/RemoteCollector/Tests/test_deploy_config.py`

### Step 12.1 — 先写静态部署检查

断言：

- nginx 只允许 GET/HEAD exact prefix，无 autoindex/PUT/POST；
- secret include 是 example placeholder，access log 不记录 header；
- 403/429/503 映射明确；per-key/per-IP/global limits 存在；
- envelope no-store/short cache，objects immutable；CF cache bypass 要求写进 README；
- systemd 使用 dedicated user、`NoNewPrivileges`、`PrivateTmp`、`ProtectSystem=strict`、最小 writable publish/state dirs、credential path；
- timer 有 randomized delay，不重入；
- signing key 与 auth key 是两个 secret，示例值不能工作于生产。

```bash
macos-app/InvestmentIntelligenceV2/RemoteCollector/.venv/bin/python -m unittest \
  macos-app/InvestmentIntelligenceV2/RemoteCollector/Tests/test_deploy_config.py -v
```

### Step 12.2 — 在容器/目标 distro 验配置（EXTERNAL）

```bash
nginx -t -c <rendered-collector.conf>
systemd-analyze verify <qieman-collector.service> <qieman-collector.timer>
```

验收：若本机无 nginx/systemd，可在交付中标记“静态检查通过，目标主机验证待执行”；不能写成已通过。

## Task 13 — VPS/域名/密钥与真实验收

**类型：EXTERNAL + MANUAL GATE；依赖 Task 11、12。**

**Files：**

- Create: `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/RemoteStagingLiveAcceptanceTests.swift`

### Gate 13.A — Owner 决策

必须书面确认：

- 首批 dataset allowlist 及每项再分发/缓存许可；
- VPS provider、区域、月成本上限、SRE owner、停服阈值；
- 域名/Cloudflare/origin firewall；
- static auth key 策略与轮换窗口；
- Ed25519 同机私钥威胁边界是否接受；
- freshness cap 与 canary universe；
- App 首发默认关闭还是内部开启。

任一未决不阻塞 Task 1–12 的离线代码，但阻塞生产部署与 DATA010 Accepted。

### Step 13.1 — 主机准备

按 `Deploy/README.md` 创建无 shell 服务用户、只写 state/publish 目录；安装 locked dependencies；生产 secrets 用 systemd credential/root-only file，权限验证为 `0600`，web root 无 private key。

### Step 13.2 — canary collect/publish

先 `--dry-run --network`，核对上游调用、429、schema 与许可；再发布 generation 1。记录 collectorVersion/publicationID，不记录 secret。至少观察两个计划周期，确认客户端数不影响 upstreamCalls。

### Step 13.3 — nginx/auth/rate/kill switch

在真实 TLS 域名验证：

```text
no key → 403
wrong key → 403
valid key → 200 envelope/object
per-key/IP burst → 429
operator kill switch → 503
cross-origin/plain HTTP → rejected
```

同时确认 Cloudflare 没有把已鉴权 object 公开 cache 给无 key 请求，origin 只接受 Cloudflare egress。

### Step 13.4 — App 实机全链与攻击演练

增加显式 opt-in live test：默认 CI 在 `RUN_PROV3B_LIVE` 未设置时 skip；真实验收必须设置开关、base URL 和 auth-key file path，并保存该次独立命令的结果。不要把 key inline 到命令或进程参数。Epic 9 前以同一 Swift target 的 live test 验证，不为此把 V2 接入 AppModel/UI。

```bash
RUN_PROV3B_LIVE=1 \
PROV3B_BASE_URL=<approved-https-origin> \
PROV3B_ACCESS_KEY_FILE=<0600-secret-file> \
swift test --package-path macos-app --filter RemoteStagingLiveAcceptanceTests
```

用 production public key pin set 验证：

- valid generation 拉取成功并通过 Reader/Validator；
- object/envelope/signature bit flip；N-1 replay；same-N different payload；expired manifest 全拒；
- 503/429/timeout → supplemental/native；无 cache → unavailable/native；native 也失败 → unknown；
- 停 Collector/nginx 后旧 verified cache 只用于覆盖的历史。

### Step 13.5 — 回滚演练

发布 generation N 的错误 canary 后，不回指 N-1；用 `generation=N+1` 重发旧 known-good object list。已见 N 的 App 必须接受 N+1、拒绝 N-1。

### Step 13.6 — 证据与 ADR 收口

脱敏记录：域名类别、App commit、collectorVersion、publicationID/generation、时间、测试结果、上游调用统计和未解决风险。绝不记录 key/private material。

只有以上全部通过，才在单独 commit 中：

- 将 `docs/adr/DATA010-remote-public-data-collector.md` Status 改为 Accepted；
- 更新 `docs/investment-intelligence-rollout.md` PROV-3b 状态与真实证据；
- 仍保持 M2 原结论，除非 M2 自己的 acceptance tests 独立通过。

## Task 14 — 最终质量门与交付

**类型：OFFLINE；生产“完成”声明依赖 Task 13。**

### Step 14.1 — 全量验证

```bash
bash macos-app/InvestmentIntelligenceV2/RemoteCollector/Scripts/verify_contract.sh
swift test --package-path macos-app
swift build --package-path macos-app
git diff --check
git status --short
git diff --stat origin/feature/investment-intelligence-v2...HEAD
```

若依赖或平台允许，再运行 macOS App build；必须带版本：

```bash
APP_VERSION=<test-version> bash scripts/build_macos_app.sh
```

### Step 14.2 — 隔离与 secret 审查

```bash
rg -n 'import (SwiftUI|AppKit)|Core/InvestmentIntelligence|Core/TrendResearch' \
  macos-app/InvestmentIntelligenceV2
git grep -nE 'BEGIN (OPENSSH|PRIVATE KEY)|X-Collector-Key:|qieman\.cookie' -- \
  ':!macos-app/InvestmentIntelligenceV2/RemoteCollector/Contract/Fixtures/**'
git ls-files | rg '/\.venv/|collector-secrets\.conf$|\.env$'
```

预期：禁止引用与 secret 搜索无有效命中，venv/生产 config 未跟踪。

### Step 14.3 — PR

PR target 必须是 `feature/investment-intelligence-v2`，title/body 含可路由 issue key。PR description 明确：

- `Closes ASH-81` 仅在该 PR 确实完成本子 issue、并希望 merge 后自动关闭时使用；否则写 `ASH-81` 只建立链接。
- 遵守 DATA002/003/004/005/006/007/008/009/010、FREE001；
- FREE001 的 VPS 受控让步、所有 Python 只在远程进程；
- 新 dependencies 的许可/计费；
- 测试命令与结果；
- M2 状态不变；
- Task 13 若未做，醒目写“VPS/域名/生产密钥/真实 AKShare 验收未完成”，DATA010 仍 Proposed。

### Step 14.4 — Reviewer handoff checklist

Reviewer-Opus 至少检查：

1. 是否先验签再信 manifest，先 hash 再 Reader；
2. generation 高水位、same-generation equivocation 与 rollback；
3. raw payload Date/Decimal/missing 跨语言一致；
4. exact dedupe 是否错误吞 revision；
5. App key 与 signing key 是否被混用；
6. Cloudflare cache 是否能绕过 origin auth；
7. Remote provider 是否偷偷返回 native provider records；
8. cache/timeout/retry/circuit 是否有界；
9. unknown 是否被默认值替代；
10. 新代码隔离和 M2/DATA009 是否保持。

## 15. 完成定义

### 15.1 “离线实现完成”

- Task 1–12 完成；
- Python/Swift shared schema + golden fixture + signature vector 通过；
- Remote provider、verified cache、三档状态、native fallback 负例齐全；
- 全量 Swift tests/build 通过；
- PR 明确真实部署未验收，DATA010 仍 Proposed。

### 15.2 “PROV-3b 生产验收完成”

- 离线完成定义全部满足；
- Task 13 所有 manual gates 和 live tests 有脱敏证据；
- 403/429/503、篡改/replay、fallback、higher-generation rollback 均真实演练；
- DATA010 改 Accepted、rollout 写真实证据；
- 最终交付分支或 PR 实际包含代码、测试、部署件和文档。

缺少后四项中的任何一项，都必须表述为“尚未完成生产验收”，不能以 fixture、dry-run 或设计文档代替。
