# PROV-3b AKShare Remote Collector 技术设计

日期：2026-08-14  
状态：待阶段 2 审查；本文只做设计，不代表 VPS、域名、密钥或真实数据链路已经就绪  
基线：`origin/feature/investment-intelligence-v2` @ `81c5a59fb25788229c7b8564489d5ffad64446a6`  
范围：Epic 4 / PROV-3b（5 点）

## 1. 决策摘要

PROV-3b 采用“服务端周期性生成、客户端只读拉取”的签名快照模型：

```text
公开上游
  │（固定计划、低频、无用户触发）
  ▼
Python Collector ──> 合并 / 去重 / 契约校验 ──> 不可变 JSONL objects
  │                                                   │
  └──────────────> 签名 manifest envelope ────────────┤
                                                      ▼
                                      nginx + Cloudflare（鉴权、限流）
                                                      │ HTTPS pull
                                                      ▼
App RemoteStagingProvider
  → Ed25519 验签 → 防重放 / 版本门 → SHA-256 → ProviderStagingReader
  → ProviderRecordSchemaValidator → V2 Pipeline
  → remote available / supplemental / unavailable
  → 必要时由 ProviderFallbackCoordinator 走原生 Provider
```

核心约束：

1. 服务端只处理公开市场数据，不接收用户请求参数，不上传且慢 Cookie、持仓、资产、设备身份或任何用户私有数据。
2. 一个 dataset/partition 只由定时任务抓一次；所有 App 共享签名快照。客户端访问量不会放大成上游访问量。
3. JSONL 仍是 `ProviderRecord`，不含 Canonical ID 和 `availableAt`，不写 GRDB；App 端仍经过 PROV-1 Reader/SchemaValidator 和后续 Identity/Temporal/Canonical pipeline。
4. manifest 必须使用 Ed25519 签名；SHA-256 只负责内容寻址与损坏检测，不能代替签名。
5. App 永远保留原生 Provider 与已验证本地历史。远程链路是增强项，不是基础功能单点。
6. 新业务代码全部位于 `macos-app/InvestmentIntelligenceV2/`；不引用 `Core/InvestmentIntelligence/`、`Core/TrendResearch/`、SwiftUI 或 AppKit。

## 2. 基线核验与前置依赖

### 2.1 当前远端事实

| 项目 | 证据 | 结论 |
|---|---|---|
| checkout 基线 | `HEAD` 与 `refs/remotes/origin/feature/investment-intelligence-v2` 均为 `81c5a59fb257...` | 本设计不是基于旧的 `feature/investment-intelligence-refactor` |
| rollout | `docs/investment-intelligence-rollout.md` §3 Epic 4，PROV-3b 依赖 PROV-1、PROV-8 | PROV-3b 是默认远程增强路径，PROV-3a 是进阶本地路径 |
| DATA010 | `docs/adr/DATA010-remote-public-data-collector.md` 存在，状态为 Proposed | 实施与真实验收后才可改为 Accepted |
| PROV-1 Reader | `macos-app/InvestmentIntelligenceV2/Persistence/ProviderStaging.swift` | `ProviderStagingReader` 已实现 ISO-8601 外层日期的 JSONL 解码 |
| PROV-1 Validator | `macos-app/InvestmentIntelligenceV2/Providers/ProviderRecordSchemaValidator.swift` | 已校验必填字段、`effectiveAt <= publishedAt` 和五种 raw payload 形状 |
| PROV-1 测试 | `macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/ProviderStagingTests.swift` | 已有读写、损坏行、五 kind 与 partition 测试 |
| PROV-8 模型 | `macos-app/InvestmentIntelligenceV2/Observations/ProviderHealth.swift` | `ProviderHealth` / `ProviderStatus` / quota DTO 已存在 |
| PROV-8 执行层 | 全仓未找到 `ProviderHealthMonitor` | 尚无事件采集、阈值计算、状态转换、熔断或持久化高水位 |
| M2 | rollout 的 2026-08-13 状态与 `M2LiveAcceptanceTests` | 仍被天天基金公告日契约和 Stooq anti-bot live gate 阻塞 |

### 2.2 不得假定已存在的接口

PROV-3b 实施前必须补齐以下最小契约：

- `ProviderPayloadCodec`：统一 raw payload 的日期、Decimal 与缺失值编解码。当前 `ObservationFactory` 和 `ProviderRecordSchemaValidator` 直接使用默认 `JSONDecoder()`；含 `Date` 的 `CorporateActionPayload` 仍会采用 Foundation reference-date 数字，不满足跨语言的“所有时间均 RFC 3339”约定。
- `ProviderHealthRecording` / `ProviderHealthMonitor`：至少能接收远程成功、HTTP 失败、限流、鉴权失败、schema 漂移、完整性失败和缓存降级事件，并产生 `ProviderHealth`。
- `ProviderFallbackCoordinator`：负责 remote → 原生 secondary → unavailable 的选择。`RemoteStagingProvider` 本身只返回 AKShare `ProviderRecord`，不能伪装成另一个 Provider 或在 `providerID == .akshare` 的接口中偷偷返回 Eastmoney/Stooq 记录。

PROV-1 已可直接复用，但 raw payload codec 需先收口；PROV-8 的 DTO 可复用，但 Monitor 不能写成“已存在”。实现顺序见配套 Plan。

### 2.3 与 M2 的关系

本 Story 不引入 SQLite/GRDB，不实现 Factor，因此可以离线先行，不违反 DATA009。它不能把当前 M2 标记为通过，也不能静默修改 `M2LiveAcceptanceTests` 用 AKShare 替代 Stooq；若要改变 M2 的真实 Provider 验收源，必须单独修订 rollout/ADR 并重新审查。

## 3. 目标与非目标

### 3.1 目标

- 默认 App 零 Python 依赖，macOS/iOS 都只通过 HTTPS 拉取。
- 支持 A 股/ETF/指数日线、基金净值和宏观公开数据；所有 dataset 都经过 allowlist 和许可复核后才可上线。
- 服务端聚合缓存、分区与增量更新，避免 N 个客户端重复命中上游。
- Python 与 Swift 共用一个版本化 wire contract 和 golden fixtures。
- 下载内容可验证来源、完整性、版本、新鲜度与单调 generation。
- 网络、鉴权、签名、schema、陈旧或限流失败都可降级，且不会用 0/默认值伪造缺失数据。
- 提供离线单测、契约测试、HTTP 集成测试和 VPS/nginx 真实验收路径。

### 3.2 非目标

- 不抓且慢私有接口，不集中保存用户 Cookie，不接收持仓或资产列表。
- 不提供客户端任意 symbol/date 查询并即时触发 AKShare。
- 不做分钟级、Level-2 或实时行情；v1 是收盘后/日级批处理。
- 不让 Python 直接写 Canonical Store、GRDB 或 App 数据目录。
- 不在此 Story 实现 SYNC-2/6 全市场调度、GRDB commit 或 UI。
- 不承诺公开可访问等于可再分发；每个上游 dataset 的条款/robots/许可需人工确认。
- 不把 App 内置的静态访问 key 描述为强身份认证；它只提高白嫖门槛。

## 4. 组件边界与目录

### 4.1 仓库目录

```text
macos-app/InvestmentIntelligenceV2/
├── Observations/
│   └── ProviderHealthMonitor.swift          # PROV-8 最小可用 monitor
├── Providers/
│   ├── ProviderPayloadCodec.swift           # PROV-1 跨语言 codec 收口
│   ├── RemoteStagingContract.swift          # DTO + 严格 wire key/type preflight
│   ├── RemoteStagingTransport.swift         # HTTP 抽象 + URLSession 实现
│   ├── RemoteStagingVerifier.swift          # Ed25519/hash/replay/version
│   ├── RemoteStagingCache.swift              # 仅存已验证对象与高水位
│   ├── RemoteProviderStateMachine.swift      # 三档状态 + retry/circuit
│   ├── RemoteStagingProvider.swift           # manifest/object → ProviderRecord
│   └── ProviderFallbackCoordinator.swift     # remote/native/unavailable 编排
└── RemoteCollector/
    ├── Contract/
    │   ├── provider-record-v1.schema.json    # wire contract 权威定义
    │   ├── manifest-v1.schema.json
    │   └── README.md
    ├── Sources/remote_collector/
    │   ├── models.py
    │   ├── codecs.py
    │   ├── datasets.py
    │   ├── planner.py
    │   ├── collector.py
    │   ├── publisher.py
    │   ├── signer.py
    │   └── cli.py
    ├── Tests/
    ├── Deploy/
    │   ├── nginx/collector.conf
    │   └── systemd/
    │       ├── qieman-collector.service
    │       └── qieman-collector.timer
    ├── pyproject.toml
    └── requirements.lock
```

`macos-app/Package.swift` 只需把 `InvestmentIntelligenceV2/RemoteCollector` 从 Swift target 排除，避免 Python/schema/deploy 文件被 SwiftPM 当作未处理资源；这不是业务代码跨目录扩散。

测试放在既有 test target：

```text
macos-app/Tests/QiemanDashboardTests/InvestmentIntelligenceV2/
├── ProviderPayloadCodecTests.swift
├── ProviderHealthMonitorTests.swift
├── RemoteStagingContractTests.swift
├── RemoteStagingVerifierTests.swift
├── RemoteStagingCacheTests.swift
├── RemoteProviderStateMachineTests.swift
├── RemoteStagingProviderTests.swift
└── ProviderFallbackCoordinatorTests.swift
```

### 4.2 责任矩阵

| 组件 | 拥有 | 明确不拥有 |
|---|---|---|
| Dataset adapter | 上游调用、字段提取、来源时间、诊断 | Canonical identity、`availableAt`、用户请求 |
| Planner | 固定 allowlist、缺口计划、jitter、并发/频率上限 | HTTP serving、App 调度 |
| Publisher | 合并、精确去重、分区、原子发布、manifest | 上游凭证、Canonical commit |
| Signer | 对 manifest payload 做 Ed25519 签名 | App 访问 key、nginx 配置 |
| nginx/Cloudflare | TLS、访问 key、限流、带宽、静态文件 | 采集、重写 JSONL、签名 |
| RemoteStagingTransport | 有界 HTTP 拉取、状态码与 Retry-After 分类 | 验签、解码、降级策略 |
| Verifier | 公钥、签名、hash、版本、generation、时钟边界 | Provider schema 语义、fallback |
| Cache | 已验证 envelope/object、高水位、circuit 状态 | 未验证下载、Canonical 数据 |
| RemoteStagingProvider | 选择分区、Reader + SchemaValidator、AKShare records | 原生 Provider 冒充、Canonical commit |
| FallbackCoordinator | 三档优先级、缺口合并、unknown | 签名与网络细节 |
| ProviderHealthMonitor | 事件窗口、状态与 quota/限流/schema 指标 | 业务数据内容 |

## 5. Python Collector 与聚合去重

### 5.1 固定计划，不允许 read-through

生产 nginx 只暴露两类静态资源：版本化 envelope 和 content-addressed objects。不存在 `/query?symbol=...`、回调、上传或其他动态 API。Collector 只读本地 allowlist 配置，由 systemd timer 触发：

- 历史 backfill：显式 CLI 操作，按 dataset/月份/桶逐批执行，成功后永久保留。
- 日常增量：收盘后执行一次；宏观/基金净值按各自节奏执行。
- 同一 partition 使用文件锁，重复 timer 不会并发抓取。
- 上游并发默认每 host 1，硬上限 2；请求间加入 jitter。
- 429/503 必须尊重 `Retry-After`，当前 run 不硬冲；失败 partition 留到下次。

这保证 1 个或 10,000 个 App 请求同一对象时，上游调用次数相同。

### 5.2 分区

v1 使用 `(dataset, UTC month, bucket)`：

```text
bucket = firstByte(SHA256(providerCode.scheme + "\0" + normalizedCode)) % 64
logical partition = <dataset>/<YYYY-MM>/<00...63>
published object = /v1/objects/<lowercase-sha256>.jsonl
```

每个 object 必须小于 16 MiB；超过时增加 `part`，不能扩大客户端内存上限。manifest entry 带 dataset、bucket、时间覆盖和 code 范围元数据，App 可只选与 `ProviderCode`/请求时间相交的 objects。

v1 不在 wire 中启用压缩；可使用 HTTP transport compression，但 manifest 的 `sha256` 和 `byteCount` 永远针对 App 得到的未压缩 JSONL bytes。若未来引入对象级 gzip/zstd，必须升 object encoding contract，不能复用 v1 字段偷换含义。

### 5.3 两层去重

第一层是抓取计划去重：相同 `(dataset, normalizedCode, from, to, upstream)` 在同一 run 只出现一次；本地已覆盖的历史区间不重抓。

第二层是记录精确去重：

```text
rawPayloadHash = SHA256(rawPayload bytes)
recordKey = SHA256(
  recordSchemaVersion + NUL + providerID + NUL + kind + NUL +
  providerCode.scheme + NUL + normalized providerCode.value + NUL +
  effectiveAt + NUL + publishedAt + NUL + rawPayloadHash
)
```

- 相同 key 只保留一条。
- 同 `effectiveAt` 但 `publishedAt` 或 payload 不同是新 vintage，必须同时保留，符合 DATA008。
- `ingestedAt` 不参与 key；重复抓取不能仅因采集时间不同制造新 vintage。保留首次成功采集时间，另在 server run 日志记录最近观察时间。
- 跨 Provider 不在 Collector 中语义合并；preferred Provider 和 canonical 去重仍属于 App Pipeline。
- 输出按 `(providerID, kind, scheme, value, effectiveAt, publishedAt, rawPayloadHash)` 排序，确保相同输入产生相同 bytes/hash。

### 5.4 原子发布

Publisher 的顺序固定：

1. 在 run 私有临时目录生成 objects。
2. 对每条 record 做 JSON Schema + 业务边界校验；任一 partition 有非法记录时，该 partition 不发布。
3. 计算 object SHA-256、行数、字节数与时间覆盖。
4. 把 object 以 hash 命名移动到 immutable 目录；已存在同 hash 时复用。
5. 生成新的 manifest payload，`generation` 严格递增。
6. 用当前 signing key 签名，生成 envelope。
7. `fsync` 文件与目录后，原子替换 `/v1/envelope.json`。

对象先于 envelope 可见，因此客户端不会拿到指向不存在对象的新 manifest。运行失败时旧 envelope 继续服务，不出现半发布。

## 6. Python ↔ Swift 权威 wire contract

### 6.1 权威来源与版本

`RemoteCollector/Contract/provider-record-v1.schema.json` 是 `ProviderRecord` 远程 wire 的权威定义；Swift Codable 和 Python model 都是实现，不能各自成为第二份真相。`manifest-v1.schema.json` 定义 transport envelope/payload。

Swift `Codable` 默认忽略未知 key，单靠 `ProviderStagingReader` 无法执行 JSON Schema 的 `additionalProperties: false`。因此 `RemoteStagingContract.swift` 还要提供一个只服务远程边界的 `RemoteStagingWireValidator`：在 Reader 前逐行检查 outer/raw-payload 的精确 key 集、JSON 类型、enum、RFC 3339/Base64 词法和大小上限。它不解析 identity、PIT 或 Canonical 业务语义；通过后仍必须复用 PROV-1 Reader/SchemaValidator。共享 schema + golden fixtures 是权威，Swift 手写 preflight 的镜像行为由契约测试锁定。

版本不写入每条 `ProviderRecord`，而由签名 manifest 的 `recordSchemaVersion` 覆盖整个 object。v1 App 只请求 `/v1/envelope.json`，并且只接受：

```text
envelopeVersion == 1
manifestVersion == 1
recordSchemaVersion == 1
signature algorithm == "Ed25519"
```

服务端不能通过响应字段要求客户端降到更老版本。未来 v2 使用新路径、新 schema 和 App 内编译的显式版本选择；v1 路径保持冻结。

### 6.2 ProviderRecord v1

| 字段 | wire 类型 | 语义 |
|---|---|---|
| `providerID` | non-empty string | v1 生产对象固定为 `akshare` |
| `providerCode` | `{scheme,value}` | scheme 与规范化规则由 dataset allowlist 定义 |
| `effectiveAt` | RFC 3339 UTC string | 经济事件/交易日锚点 |
| `publishedAt` | RFC 3339 UTC string | 上游公开时间；未知精确时刻时使用该法域日期的 00:00 anchor，并记录 dataset precision，不能用抓取时间冒充 |
| `ingestedAt` | RFC 3339 UTC string | Collector 首次成功看到此 record 的时间 |
| `kind` | 五个 `ProviderRecordKind` raw value 之一 | `DAILY_BAR` 等，大小写冻结 |
| `rawPayload` | padded standard Base64 | 对应 kind 的 compact UTF-8 JSON bytes |
| `reliabilityClass` | enum string | AKShare 固定 `COMMUNITY_AGGREGATED` |
| `jurisdiction` | `CN/HK/US/PLATFORM` | 初始生产 allowlist 只开放已核验法域 |

外层日期固定为 `YYYY-MM-DDTHH:mm:ssZ`，不带小数秒。日期仅是 anchor 时，先按来源法域本地 00:00 建模再转换 UTC；它不宣称上游恰在 00:00 发布。`availableAt` 仍由 App 的 `TemporalNormalizer` 计算。

### 6.3 raw payload

v1 schema 覆盖现有五种 payload；首批生产 allowlist 只开启已完成许可与真实样本验收的 DailyBar/NAV/Macro dataset，其他 kind 保留契约但默认关闭。

- 所有 `Date` 均使用同样的 RFC 3339 UTC 字符串。Swift 新增 `ProviderPayloadCodec`，Validator、Factory 和所有 Adapter 共用其 ISO-8601 decoder/encoder；兼容读取旧的 Foundation reference-date 数字只用于已有本地 fixture/旧 spool，任何新写出一律 RFC 3339。
- `Decimal` 使用 JSON number，词法限定为普通十进制，不允许 exponent、NaN、Infinity、`-0` 或前导零；编码时去无意义尾零。
- `volume` 必须落在 signed 64-bit 范围。
- “未知”必须省略 optional key；不写 `null`，更不能写 `0`、空串或空对象冒充。真实 0 必须保留。
- `rawPayload` 内 JSON 使用 UTF-8、key 字典序、无多余空白、无 BOM/尾换行，然后再 Base64。这个 canonicalization 用于稳定 record key 和 fixture，不把 raw payload 变成 Canonical 业务转换。
- 外层 JSONL 同样 compact、key 字典序，一行一个 object，以单个 LF 结尾；Reader 不依赖 key 顺序。

### 6.4 跨语言 fixture

同一组 golden fixtures 必须覆盖：

- 五个 kind 的最小合法/全字段 record；
- 日期 anchor、UTC 转换、Decimal 精度、真实 0、missing optional；
- revision（同 effectiveAt、不同 publishedAt/payload）不去重；
- 非法 enum、未知必填字段、非法 Base64、NaN/Infinity、时间逆序、payload-kind 不匹配；
- Python 生成 JSONL → Swift `ProviderStagingReader` → `ProviderRecordSchemaValidator`；
- Swift fixture 经 Reader 读出后，raw payload 用 `ProviderPayloadCodec` 解码，再由 Python validator 验证同一 bytes。

“Python 测试各过、Swift 测试各过”不等于契约通过；CI 必须有一条跨语言 golden 命令串行跑两端。

## 7. 签名 envelope、密钥与防降级

### 7.1 Envelope

`/v1/envelope.json` 是小型 JSON：

```json
{
  "envelopeVersion": 1,
  "payload": "<base64url-without-padding of canonical manifest UTF-8 bytes>",
  "signatures": [
    {
      "algorithm": "Ed25519",
      "keyID": "collector-2026-q3",
      "signature": "<base64url-without-padding>"
    }
  ]
}
```

manifest payload 只含 string/integer/bool/array/object，不含浮点数，按 RFC 8785 JCS 规则 canonicalize。App 不重新序列化再验签：它先 Base64URL 解出原始 canonical payload bytes，直接验签，再 decode DTO，避免 Python/Swift JSON encoder 的 key/number 差异。

签名输入使用 domain separation：

```text
UTF8("qieman.remote-staging.manifest.v1\0") || payloadBytes
```

### 7.2 SignedManifest v1

必填字段：

```text
manifestVersion: 1
recordSchemaVersion: 1
generation: monotonically increasing UInt64
generatedAt / notBefore / expiresAt: RFC 3339 UTC
collectorVersion: immutable build identifier
publicationID: UUID/ULID for diagnostics
files: [RemoteStagingFile]
```

每个 file 至少包含：

```text
dataset, logicalPartition, path, sha256, byteCount, recordCount,
scheme, bucket, effectiveFrom, effectiveThrough, publishedThrough, freshUntil
```

约束：

- `path` 只能匹配 `/v1/objects/[0-9a-f]{64}.jsonl`，禁止绝对 URL、`..`、query 和跨 origin redirect。
- `path` 中 hash 必须等于字段 `sha256`。
- envelope 最大 256 KiB、file 数最大 20,000、单 object 最大 16 MiB、单次 fetch 总下载最大 64 MiB，超限直接拒绝。
- `notBefore <= generatedAt <= expiresAt`；App 容忍未来时钟漂移最多 5 分钟。
- `freshUntil <= expiresAt`，并受 App 内按 kind 的最大 freshness cap 约束；服务端不能签一个无限新鲜的旧快照。

### 7.3 验证顺序

客户端顺序不可调整：

1. HTTPS、同 origin、禁止降级 redirect。
2. envelope 大小/JSON 基本上限。
3. 解出 payload/signature，算法必须是 Ed25519，`keyID` 必须在 App pin set。
4. 验 Ed25519 签名。
5. decode manifest，检查版本/时间/路径/数量/大小。
6. 检查 `generation` 高水位：更小为 replay；相同 generation 但 payload hash 不同为 equivocation；两者均拒绝。
7. 下载需要的 content-addressed object。
8. 先验 byteCount/SHA-256，再把对象移入 verified cache。
9. `RemoteStagingWireValidator` 对原始 JSONL 做严格 wire preflight，拒绝未知 key、错误类型与非 v1 词法。
10. `ProviderStagingReader` 解码，`ProviderRecordSchemaValidator` 分桶；任何非法 record 不进入返回值并记录 schema drift。生产 v1 默认整 partition fail-closed，不发布“部分看似可用”的远程分区。
11. 只有 envelope 和所有选中 object 均通过后，才原子更新 manifest/generation 高水位。

### 7.4 密钥分发与轮换

- 私钥不入 Git、不进 App、不放 nginx web root；由 systemd credential 或 root-only `0600` 文件注入 unprivileged collector 进程。
- App 编译进 `keyID → Ed25519 public key + activation/notAfter` pin set。
- 正常轮换顺序：先发布含 old+new 公钥的 App → 服务端 envelope 双签至少一个发布窗口 → 切 new 为主签 → 等旧 App 淘汰窗口 → 后续 App 删除 old。
- 验证端“任一已 pin 且处于有效窗口的签名通过”即可；不接受服务端自带公钥。
- 私钥疑似泄露时不能依赖同一 VPS 下发撤销：先发布 App 更新撤销旧 key/加入新 key，再用新 key 发布更高 generation。

真实威胁边界必须写清：私钥若常驻同一 VPS，签名能抵抗 CDN/nginx/web-root 篡改、传输损坏和未取得 credential 的局部入侵，但不能抵抗拿到 root 与 signing credential 的整机失陷。要获得“VPS root 失陷仍不可伪造”的保证，需要独立签名机/HSM/离线人工签名，超出 5 点 Story。DATA010 当前“VPS 被攻陷仍不能伪造”的措辞需按此修订。

## 8. 鉴权、限流与滥用防护

### 8.1 凭证边界

服务端配置 schema 只允许 dataset、公开 symbol universe、调度、访问 key 和 signing key path。代码与部署检查必须拒绝：

- `qieman.cookie`、Cookie header、用户 token、持仓/资产 JSON；
- 客户端上传、动态 symbol 查询、用户级日志；
- 付费数据 key 或无再分发授权的数据集。

App 的 `X-Collector-Key` 是服务访问 key，不是用户私有凭证。它可被反编译，因此只能挡随机扫描和低成本白嫖，不能声称能识别真实设备。若实际滥用超过静态 key 能力，再单独设计 per-install token；不在本 Story 偷加账号系统。

### 8.2 请求路径

```text
Cloudflare proxy（隐藏 origin；origin firewall 仅允许 CF egress）
  → 对 /collector/* 明确 bypass public cache，避免缓存绕过 origin auth
  → nginx TLS origin
  → X-Collector-Key allowlist（版本化；日志只记 keyID，不记值）
  → per-key limit_req + per-IP burst + global connection/bandwidth cap
  → 只读 static exact paths
```

- 无 key/错 key 返回 403；每 key/IP 超限返回 429；运维 kill switch 返回 503。
- 不把 key 放 URL/query、Referer 或 access log。
- envelope `Cache-Control: no-store` 或短 TTL；content-addressed object 可 `immutable`，但仍须每次先过鉴权。Cloudflare 若不能保证 edge auth，必须 bypass cache。
- nginx 禁止目录列表、range 放大滥用（或限制单 range）、跨 origin redirect、PUT/POST、符号链接逃逸。
- 设日/月总 egress 告警与硬 cap；达到 cap 可直接 503，因为客户端有降级路径。

### 8.3 Collector 对上游的礼貌策略

- 以“本地已有覆盖”为输入规划缺口，不全量刷新。
- 按 host 设并发 1、指数退避和 jitter；429/503 不切换代理硬冲。
- 主/备上游只能在 dataset allowlist 中显式配置，保留来源和失败诊断；不把不同来源数据无痕混为 AKShare 单一事实。
- 每个 dataset 上线前记录来源 URL 类别、许可/使用条款、抓取频率和人工批准人。公开访问不自动授予再分发权。

## 9. App 端接口骨架

以下是实现边界，不要求类型名逐字不变，但职责不能合并成一个不可测试的大类。

```swift
import Foundation

protocol RemoteStagingTransport: Sendable {
    func fetchEnvelope(etag: String?) async throws -> RemoteHTTPResponse
    func fetchObject(path: String, expectedBytes: Int) async throws -> RemoteHTTPResponse
}

struct RemoteHTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

protocol RemoteStagingVerifying: Sendable {
    func verifyEnvelope(
        _ data: Data,
        now: Date,
        highWatermark: RemoteManifestWatermark?
    ) throws -> VerifiedRemoteManifest

    func verifyObject(_ data: Data, descriptor: RemoteStagingFile) throws
}

protocol ProviderHealthRecording: Sendable {
    func record(_ event: ProviderHealthEvent) async
    func snapshot(for providerID: DataProviderID) async -> ProviderHealth
}

enum RemoteProviderMode: String, Sendable, Codable {
    case remoteAvailable
    case supplemental
    case unavailable
}

struct RemoteFetchOutcome: Sendable {
    let mode: RemoteProviderMode
    let records: [ProviderRecord]
    let coveredRange: ClosedRange<Date>?
    let reason: RemoteFallbackReason?
    let manifestGeneration: UInt64?
}

struct RemoteStagingProvider: Sendable {
    func fetchOutcome(
        code: ProviderCode,
        from: Date,
        to: Date,
        now: Date
    ) async -> RemoteFetchOutcome
}

struct ProviderFallbackCoordinator: Sendable {
    func fetch(
        code: ProviderCode,
        from: Date,
        to: Date
    ) async -> ProviderChainResult
}
```

`RemoteStagingProvider` 内部先用 `RemoteStagingWireValidator` 锁定跨语言 wire，再使用现有 `ProviderStagingReader` 与 `ProviderRecordSchemaValidator`。Cache root、base URL、key provider、clock、transport、verifier、health recorder 均注入，测试不读真实网络/Keychain/全局目录。

访问 key 的产品集成可由 App composition layer 注入；V2 文件不引用现有 AppModel、SwiftUI/AppKit 或旧 Investment Intelligence 类型。

## 10. 三档状态、优先级与失败行为

### 10.1 状态定义

| 状态 | 进入条件 | 可用数据 | ProviderHealth 映射 |
|---|---|---|---|
| `remoteAvailable` | envelope/签名/版本/generation/object/schema 全通过；所选 objects 覆盖请求范围；`now <= freshUntil` | 新下载或已验证且仍 fresh 的 remote records，作为 primary | `.healthy`；若刷新偶发失败但 cache 仍完整可用，可带 degraded event 而不立即丢数据 |
| `supplemental` | 有已验证 cache，但远程刷新失败、circuit open、对象陈旧或只覆盖部分请求 | remote 仅用于已覆盖历史；缺口交给原生 secondary | `.degraded` |
| `unavailable` | 没有可用 verified cache，或 cache 对本请求零覆盖 | 不返回伪造 remote record，完全交给原生 secondary；secondary 也失败则 unknown | `.unavailable` |

签名/hash/replay/schema 失败绝不使用本次下载。若旧 verified cache 仍覆盖部分历史，状态是 supplemental；否则 unavailable。失败不能删除最后一份 verified cache。

### 10.2 优先级

```text
1. remoteAvailable：AKShare signed records
2. supplemental：verified remote historical records + native provider 补缺口
3. unavailable：native provider
4. native 也失败：显式 unavailable/unknown，不写 0，不把旧值标成最新
```

合并时按时间范围补缺口，不按数组简单覆盖；跨 Provider 的最终选择仍遵循现有 reliability/sourceProviderID tie-break 和后续 canonical pipeline。返回结果保留每条真实 `providerID`。

### 10.3 timeout、retry 与 circuit breaker

- envelope request timeout 5 秒，object request timeout 15 秒，单次用户触发总预算 30 秒。
- 只对连接错误、408、429、5xx 重试一次；使用 250–750ms jitter。`Retry-After <= 2s` 可在预算内遵守，更长则结束本次并交由下次调度，不阻塞 UI。
- 403、404（manifest 引用对象缺失）、版本不兼容、签名/hash/replay/schema 错误不即时重试。
- 10 分钟内连续 3 次 transient refresh 失败：open 15 分钟；half-open 只放 1 个 envelope 请求。再次失败按 30m/1h/2h/4h/6h 上限递增；成功验证完整 publication 后清零。
- 完整性/重放/版本失败对该 publication digest 立即 fail-closed 并隔离；至少等下一 generation 或人工/版本变化再试，避免攻击输入重试风暴。
- circuit 状态与 manifest 高水位持久化到 transport cache；App 重启不清零高水位、也不立即冲击故障服务。

### 10.4 核心伪代码

```text
fetchOutcome(request):
  cached = cache.verifiedCoverage(request)

  if circuit.disallowsProbe(now):
      return cached.partial ? supplemental(cached) : unavailable(circuitOpen)

  try:
      envelopeBytes = transport.fetchEnvelope(cache.etag)
      manifest = verifier.verifyEnvelope(envelopeBytes, now, cache.highWatermark)
      descriptors = manifest.select(request)
      enforceCoverageAndBudgets(descriptors, request)

      stagedObjects = []
      for descriptor in descriptors:
          bytes = cache.object(descriptor.sha256) ?? transport.fetchObject(descriptor.path)
          verifier.verifyObject(bytes, descriptor)
          require RemoteStagingWireValidator.validate(bytes, descriptor)
          records = ProviderStagingReader.read(boundedTempFile(bytes))
          require validator.partition(records).invalid.isEmpty
          require every record.providerID == .akshare
          require every record matches descriptor dataset/range/bucket
          stagedObjects.append(verified bytes + records)

      cache.atomicCommit(envelope, manifest, stagedObjects, highWatermark)
      health.record(success)
      circuit.close()
      return manifest.covers(request) && manifest.isFresh(now)
          ? remoteAvailable(records)
          : supplemental(records)

  catch classifiedError:
      health.record(classifiedError)
      circuit.record(classifiedError)
      quarantineOnlyUnverifiedDownloads()
      return cached.partial ? supplemental(cached) : unavailable(classifiedError)
```

## 11. Cache 与本地完整性

Remote cache 只是 transport/staging cache，不是 Canonical Store，不冻结 SQLite schema。建议布局：

```text
<injected-cache-root>/remote-staging/v1/
├── state.json                 # high watermark, etag, circuit；原子写
├── manifests/<payloadHash>.json
├── envelopes/<generation>.json
├── objects/<sha256>.jsonl     # 仅 verified immutable bytes
└── quarantine/                # 可选、受大小上限；永不交给 Reader/Pipeline
```

- root `0700`、文件 `0600`，尽管内容公开，防止本地低权限进程替换已验证缓存。
- 写临时文件 → hash/Reader/Validator 全通过 → `fsync` → rename；未验证内容不能使用目标 hash 文件名进入 verified tree。
- 启动时重验 state 引用的 manifest/object hash；state 损坏时保留 objects，但清建索引，不能把 generation 高水位降为 0 后接受旧 manifest。高水位另保留双份 checksummed journal 或 fail-closed 要求重新联网取得未过期更高 generation。
- LRU 只删除未被当前/最近 manifest 引用的 immutable objects；不能删除唯一 verified 历史后把缺口当 0。

## 12. 可观测性

### 12.1 服务端

每个 Collector run 输出结构化字段：

```text
runID, collectorVersion, dataset, partition, plannedRequests, upstreamCalls,
cacheHits, recordsSeen, exactDuplicatesDropped, revisionsRetained,
malformedDropped, http429, http5xx, durationMs, publishedGeneration
```

nginx 日志只记 request ID、path class、status、bytes、latency、匿名 keyID/IP hash；禁止 header value、query token、raw payload。最低告警：

- 某 dataset 连续 2 个计划周期未成功；
- upstream 429/403 或 schema reject 突增；
- envelope generation 未推进；
- 403/429/egress 异常增长；
- object hash/record count 与发布前校验不一致。

可用 journald + logrotate + 本机 timer 做零额外订阅的监控；是否接外部告警服务由人工决定，不能在实现中静默引入付费依赖。

### 12.2 客户端

`ProviderHealthEvent` 至少区分：success、transient network、rate limited、auth rejected、manifest stale、signature invalid、hash mismatch、replay/downgrade、schema drift、cache supplemental、no coverage。指标只含类别、generation、keyID、age、bytes、计数与 latency，不含访问 key 和 raw records。

现有 `ProviderHealth.lastSchemaDrift` 可直接更新；签名/重放是安全事件，不能伪装成普通 schema drift。若 DTO 无字段容纳详细 reason，reason 留在有界事件日志，`ProviderHealth.status` 仍映射为 degraded/unavailable。

## 13. 测试矩阵

| 层 | 离线场景 | 验收 |
|---|---|---|
| Python codec | 五 kind、Decimal/date/missing、invalid fixture | deterministic bytes；非法值 fail-closed |
| Planner | 已覆盖区间、重复 symbol、lock、jitter、429 | 不重复抓；并发/频率不超阈值 |
| Publisher | exact duplicate、revision、超大 partition、crash before swap | 去重不吞 revision；旧 envelope 始终完整 |
| Signer | golden test key、双签、未知 key、payload bit flip | Swift/Python 对同一向量结论一致 |
| Swift verifier | version、expiry、clock skew、path traversal、size cap、lower/same generation | downgrade/replay/equivocation 全拒绝 |
| Wire/Reader/Validator | Python JSONL → strict wire preflight → Swift PROV-1 → payload codec | 五 kind 契约通过；未知 key/词法/schema mismatch 拒绝 |
| HTTP | 200/304/403/404/408/429/5xx、Retry-After、redirect | retry 分类与预算正确；无跨 origin |
| Cache | 中途 crash、tampered file、state 损坏、LRU | 未验证不晋级；旧 verified cache 可用 |
| State machine | fresh/partial/stale/no cache/circuit/half-open | 三档状态与 health 映射固定 |
| Fallback | remote/full、remote partial + native、双失败 | 不冒充 provider；缺口为 unknown |
| E2E fixture server | 签名 envelope + objects + native fake | HTTP→验签→Reader→Validator→fallback 全链 |
| VPS/nginx | 无/错/对 key、限流、kill switch、真实 TLS | 403/429/503、同 origin、App 实机验签 |

跨语言 test key 只能放在 test fixtures，并明显标为 `TEST ONLY`；生产公钥与私钥材料不得复用。

## 14. 真实 VPS/nginx 验收

PROV-3b 不能仅凭 fixture 标记完成。真实验收至少包括：

1. 人工确认域名、VPS、Cloudflare/origin firewall、数据许可与每月成本/SRE owner。
2. 在干净主机按 lock file 安装 Collector；服务账户无 shell、无 App 用户目录权限。
3. 私钥和访问 key 通过主机 secret file/systemd credential 注入，仓库与日志中搜索不到实际值。
4. 选择一组公开 canary（A 股、ETF、指数、基金净值、宏观各至少一项，未获许可 dataset 跳过并说明）真实抓取。
5. 观察 upstream 调用数等于计划 partition 数，与发起 App 数无关；确认 jitter/并发/Retry-After。
6. 发布 generation N；独立执行 Python contract verifier，再用同一 Swift target 的显式 live acceptance test（或已接线的内部 App build）拉取并通过 Ed25519、SHA-256、wire preflight、Reader、SchemaValidator。Epic 9 前不得为了验收把 V2 偷接入 AppModel/UI。
7. 无 key/错 key/超限/kill switch 分别得到 403/403/429/503，App 分别进入 supplemental 或 unavailable 并成功走 native fallback。
8. 篡改 object、envelope payload、signature，重放 N-1，以及同 N 不同 payload，App 全部拒收且不覆盖最后 verified cache。
9. 停 Collector/nginx，确认历史 cache 只以 supplemental 使用，最新缺口不会伪造。
10. 记录实际域名、generation、collectorVersion、App commit、验收时间与脱敏日志；不把秘密贴进 issue/PR。

## 15. 发布、回滚与灾难处置

### 15.1 渐进发布

1. 仅离线 fixture/contract。
2. staging 域名 + canary universe，App 配置默认关闭。
3. 内部 build 开启，观察至少两个计划周期。
4. 扩 universe，但仍维持全局 egress cap。
5. DATA010 验收证据齐全后改 Accepted，并由产品 composition 选择默认开启。

### 15.2 回滚

- 服务异常：nginx kill switch 返回 503，客户端自动 fallback。
- 数据错误：不能把 `/v1/envelope.json` 直接指回低 generation；已见高水位的客户端会正确拒绝。应创建 `generation = N+1` 的新签名 manifest，重新引用上一组已知良好 immutable objects。
- App 错误：composition 层关闭 remote provider；不删除 verified cache，避免失去可审计证据。
- signing key 泄露：停止发布/503，发布带新公钥和旧 key revoke 的 App，再用新 key 发布更高 generation。仅在服务端换 key 对旧 App 无效。
- auth key 泄露：nginx 临时限流/503，发布双 key overlap 的 App 后撤旧 key；不把 auth key rotation 与 Ed25519 signing rotation 混为一谈。

## 16. ADR 合规与需修订内容

本设计遵守：

- **DATA002 / DATA005 / DATA008**：保留 effective/published/ingested，`availableAt` 仍由 App policy 推导；revision 不覆盖。
- **DATA003**：远程只产 ProviderRecord，Reader/SchemaValidator/Identity/Temporal/DataValidator/Canonical commit 防火墙不绕过。
- **DATA004**：只补缺口、历史对象不可变并可复用；remote cache 不冒充 Canonical Store。
- **DATA006**：明确 ProviderHealth 事件、三档状态、unknown 与 native fallback。
- **DATA007**：Python 继续进程外；远程变体不进 App/iOS runtime。
- **DATA009**：不引入 SQLite/Factor，不宣称 M2 已通过。
- **DATA010**：公开数据 only、聚合去重、鉴权反白嫖、三档降级、验签完整性。
- **FREE001**：无付费数据/API；VPS 是已声明受控让步。

实施 PR 必须修订而不是口头忽略以下内容：

1. DATA010：`Ed25519` 从“可选”改为 PROV-3b 必选；补 envelope、generation、防重放、密钥轮换和真实威胁边界。
2. DATA010：明确静态 App key 只是资源滥用门槛，不是不可提取设备身份；Cloudflare cache 必须避免绕过 origin auth。
3. DATA010/FREE001/AGENTS.md：记录 VPS 持续成本、SRE owner、服务端 Python 例外和不进入 App runtime 的边界。
4. DATA007：澄清“iOS 不含本地 Python，但可消费 PROV-3b 远程 staging”，避免旧文字被理解为 iOS 无 A 股增强。
5. PROV-1 说明或 ADR-DATA003：冻结跨语言 `ProviderPayloadCodec`，解决 raw payload Date 当前默认 codec 不一致。

不需要新增 DATA011：上述决策均属于 DATA010 的远程传输与安全细化。若未来引入 per-device identity、独立签名服务/HSM 或动态查询 API，范围已显著变化，应另立 ADR。

## 17. 风险与待人工决策

| 风险/决策 | 影响 | 处理 |
|---|---|---|
| 数据再分发许可 | “公开”不等于允许缓存后分发 | 每 dataset 上线前人工法务/条款确认；未确认默认关闭 |
| VPS/SRE owner 与预算 | 违反零基础设施付费默认 | 明确月预算、owner、告警与停服阈值后才生产化 |
| 签名私钥同机 | root compromise 可伪造 | v1 诚实接受此边界；如不可接受，另做独立 signer ADR |
| 静态访问 key 可提取 | 大规模滥用时保护有限 | 限流/egress cap/轮换；实际发生后再评估 per-device token |
| PROV-8 未完成 | 无统一 health/circuit 会让降级不可审计 | 先落最小 Monitor 契约；未集成不能签收 PROV-3b |
| M2 仍 blocked | 不能冻结 persistence/factor，也不能把 remote 当作绕过证据 | 保持独立状态；PROV-3b 不改 M2 结论 |
| AKShare/upstream schema 漂移 | publication 可能停更 | partition fail-closed、旧 cache supplemental、schema 告警 |
| manifest/object 规模 | App 内存和带宽风险 | 64 buckets、16 MiB/object、64 MiB/request、内容寻址 |
| 时钟错误 | expiry/notBefore 误判 | 5 分钟容忍；记录 clock error；不放宽 generation 高水位 |
| key/app 轮换窗口 | 旧 App 可能无法读新 key | 先 App 后服务端、双签 overlap、遥测确认后撤旧 key |

阶段 2 审查需要明确确认：首批 dataset allowlist、数据再分发结论、VPS/SRE owner、最大月成本、默认 freshness cap、App 首发是否默认关闭，以及同机 signing key 的威胁边界是否可接受。
