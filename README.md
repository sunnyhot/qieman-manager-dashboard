# 且慢主理人抓取与看板

这个项目包含三部分：

- `qieman_scraper.py`
  抓且慢公开内容页，适合按关键词、栏目名、主理人名称检索公开文章。
- `qieman_community_scraper.py`
  抓且慢社区里的主理人动态，支持公开小组流、登录后的关注动态、关注用户、已加入小组、个人空间动态。
- `dashboard_server.py`
  本地浏览器看板，用来同时查看平台调仓、论坛发言、历史快照、评论和持仓分析。

项目零第三方 Python 依赖，默认使用系统自带的标准库即可运行。

## 目录

- `qieman_scraper.py`
- `qieman_community_scraper.py`
- `dashboard_server.py`
- `output/`
  抓取结果和导出的历史快照。
- `qieman.cookie`
  本地登录态文件，仅本机使用，不应提交到仓库。

## 快速开始

## macOS 应用（.app）

现在支持把整个项目打包成一个正式的本地 macOS 应用：

- 主界面是原生 SwiftUI，不再只是包一层网页
- 现有 PC 网页版完整保留在 App 内的“网页备份”入口，但已经改成按需启动
- 核心数据链路已经原生化：`group-manager`、`following-posts`、`following-users`、`my-groups`、`space-items`、`auth-check`、评论、平台调仓、持仓估值、调仓时间线
- 新增“我的持仓”原生模块：支持手动粘贴个人持仓并做实时估值
- App 现在支持常驻菜单栏，点开就能看到个人持仓总市值、浮盈和单只估值
- 历史快照列表、快照详情、默认首屏快照选择已经改为 Swift 原生读取本地 `output/`
- App 内新增“登录且慢”原生登录窗口：直接在内嵌页面完成登录，自动抓取并保存 `qieman.cookie`
- Python 本地服务现在只承担“网页备份”兼容入口，不再是原生主界面的核心依赖

### 构建

```bash
cd /Users/xufan65/Documents/Codex/2026-04-17-new-chat
bash scripts/build_macos_app.sh
```

产物路径：

`dist/macos-app/QiemanDashboard.app`

分发压缩包：

`dist/macos-app/QiemanDashboard-2.1.0.zip`

构建脚本现在会自动完成：

- 生成 `.icns` 图标
- 生成完整 `.app` bundle
- 写入版本号、构建号、Bundle ID、最低系统版本
- 做本地 ad-hoc 签名
- 输出可分发的 `.zip`

如果要自定义版本信息，可以直接传环境变量：

```bash
APP_VERSION=2.1.0 \
APP_BUILD=210 \
BUNDLE_ID=com.sunnyhot.qieman.manager.dashboard \
MIN_MACOS_VERSION=14.0 \
bash scripts/build_macos_app.sh
```

### 运行

```bash
open /Users/xufan65/Documents/Codex/2026-04-17-new-chat/dist/macos-app/QiemanDashboard.app
```

启动行为：

- App 默认直接走原生界面和原生抓取，不会一启动就自动拉起网页服务。
- 当你打开“网页备份”时，App 才会按需拉起内置 `dashboard_server.py`，并把运行日志写到 `dashboard.log`。
- 如果本机已经有 `http://127.0.0.1:8765` 的旧看板服务在运行，App 会直接复用，不再因为端口被占用就报错。
- App 首次启动会把旧网页版本的历史快照导入到自己的运行目录，原生界面开箱就能看到备份数据。
- App 内包含原生模块：
  - 总览
  - 平台调仓
  - 论坛发言
  - 历史快照
  - 网页备份

### 应用数据目录

应用运行时数据不会写进 `.app`，而是写到：

`~/Library/Application Support/QiemanDashboard`

其中包括：

- `qieman.cookie`（可选，登录态）
- `output/`（抓取快照与历史数据）
- `user-portfolio.json`（个人持仓）
- `user-pending-trades.json`（买入中 / 待确认交易）
- `dashboard.log`（应用日志）

### 应用内导入中心

原生 App 的“我的持仓”页现在内置了一个统一的“导入中心”，可以分别录入：

- 持仓中
- 买入中
- 定投计划

每一类都支持三种方式：

- 手动录入  
  直接在草稿框里粘贴文本，再点保存。
- 上传图片  
  App 会先做 OCR，把识别结果放进草稿框，适合支付宝截图、交易记录截图、计划列表截图；保存前可以先人工核对。
- 上传表格  
  支持 `txt / csv / tsv / json / xlsx`，会先转成对应的标准草稿格式，再由你确认后保存。

导入策略：

- 图片和表格不会直接覆盖正式数据，而是先进入草稿区，避免误识别后直接落盘。
- 草稿区按“持仓中 / 买入中 / 定投计划”三类分别保存和重载。
- 持仓保存后可直接点“刷新估值”，买入中和定投计划保存后会立刻出现在对应原生卡片里。

### 个人持仓导入格式

“我的持仓”页面支持手动粘贴，每行一条，支持这两种常见格式：

```text
021550 1200 1.1304 博时红利低波100
博时红利低波100 021550 1200 1.1304
```

其中：

- 第 1 列或第 2 列是基金代码
- 份额必填
- 成本价可选
- 名称可选

如果你手里是支付宝持仓摘要，也可以先整理成这种文本：

```text
华泰柏瑞纳斯达克100ETF联接(QDII)A | 16700.76 | 2290.76 | 16.13%
摩根标普500指数(QDII)A | 6935.26 | 115.26 | 1.74%
```

然后运行：

```bash
python3 /Users/xufan65/Documents/Codex/2026-04-17-new-chat/scripts/import_alipay_portfolio.py \
  --input /path/to/alipay-holdings.txt \
  --preview /tmp/alipay-import-preview.json
```

脚本会自动：

- 解析基金名、当前金额、持有收益、收益率
- 自动补基金代码
- 用最新估值或最近净值回推份额
- 估算成本价
- 直接写入 `~/Library/Application Support/QiemanDashboard/user-portfolio.json`

如果 App 正在运行，去“我的持仓”页点一次“重载已保存”就能立刻看到。

### 买入中 / 交易进行中导入格式

如果你手里还有支付宝里的“交易进行中”列表，可以整理成这种文本：

```text
2026-04-23 09:48:33 | 定投 | 华泰柏瑞纳斯达克100ETF联接(QDII)A | 10.00元 | 交易进行中
2026-04-22 14:10:02 | 买入 | 国泰中证畜牧养殖ETF联接A | 3000.00元 | 交易进行中
2026-04-18 08:28:26 | 转换 | 华夏标普500ETF联接(QDII)A -> 摩根标普500指数(QDII)A | 32.33份 | 交易进行中
```

然后运行：

```bash
python3 /Users/xufan65/Documents/Codex/2026-04-17-new-chat/scripts/import_alipay_pending_trades.py \
  --input /path/to/alipay-pending.txt \
  --preview /tmp/alipay-pending-preview.json
```

脚本会自动：

- 写入 `~/Library/Application Support/QiemanDashboard/user-pending-trades.json`
- 识别“买入 / 定投 / 转换”
- 分开记录金额单和份额单
- 尽量补齐基金代码

如果 App 正在运行，去“我的持仓”页点一次“重载买入中”就能立刻看到。

### 定投计划导入格式

如果你手里还有支付宝里的“投资计划”列表，可以整理成这种文本：

```text
定投 | 易方达恒生科技ETF联接(QDII)A | 每周三定投 | 500.00元 | 2 | 1000.00元 | 余额宝 | 2026-04-29(星期三)
智能定投 | 华夏中证A500ETF联接A | 每周二定投-涨跌幅模式 | 250.00~1,000.00元 | 2 | 1000.00元 | 余额宝 | 2026-04-28(星期二)
```

然后运行：

```bash
python3 /Users/xufan65/Documents/Codex/2026-04-17-new-chat/scripts/import_alipay_investment_plans.py \
  --input /path/to/alipay-plans.txt \
  --preview /tmp/alipay-plans-preview.json
```

脚本会自动：

- 写入 `~/Library/Application Support/QiemanDashboard/user-investment-plans.json`
- 识别“定投 / 智能定投”
- 识别固定金额和区间金额
- 尽量补齐基金代码
- 保留下一次执行日期、累计期数和累计投入

如果 App 正在运行，去“我的持仓”页点一次“重载计划”就能立刻看到。

### 1. 运行本地看板

```bash
cd /Users/xufan65/Documents/Codex/2026-04-17-new-chat
python3 dashboard_server.py --open
```

如果不想自动打开浏览器：

```bash
python3 dashboard_server.py
```

默认地址：

[http://127.0.0.1:8765](http://127.0.0.1:8765)

### 2. 抓公开内容

```bash
python3 qieman_scraper.py --query "长期指数投资" --markdown
```

按主理人过滤：

```bash
python3 qieman_scraper.py --query "长赢计划" --author "ETF拯救世界" --markdown
```

### 3. 抓社区主理人动态

按产品代码解析公开小组并抓主理人发言：

```bash
python3 qieman_community_scraper.py --prod-code LONG_WIN --pages 3 --markdown
```

按主理人名自动解析：

```bash
python3 qieman_community_scraper.py --manager-name "ETF拯救世界" --pages 3 --markdown
```

按关键词和日期范围过滤：

```bash
python3 qieman_community_scraper.py --prod-code LONG_WIN --keyword "创业板" --since 2026-04-16 --until 2026-04-16 --markdown
```

## 登录态抓取

先从浏览器导出 `qieman.com` 的 Cookie，推荐放进文件：

```bash
pbpaste > qieman.cookie
```

验证登录态：

```bash
python3 qieman_community_scraper.py --mode auth-check --cookie-file qieman.cookie
```

抓关注动态流：

```bash
python3 qieman_community_scraper.py --mode following-posts --cookie-file qieman.cookie --pages 5 --markdown
```

只抓某个主理人的关注动态：

```bash
python3 qieman_community_scraper.py --mode following-posts --cookie-file qieman.cookie --user-name "ETF拯救世界" --pages 5 --markdown
python3 qieman_community_scraper.py --mode following-posts --cookie-file qieman.cookie --broker-user-id 793413 --pages 5 --markdown
```

导出关注用户列表：

```bash
python3 qieman_community_scraper.py --mode following-users --cookie-file qieman.cookie --pages 2 --markdown
```

导出已加入小组：

```bash
python3 qieman_community_scraper.py --mode my-groups --cookie-file qieman.cookie --markdown
```

抓个人空间动态：

```bash
python3 qieman_community_scraper.py --mode space-items --cookie-file qieman.cookie --user-name "ETF拯救世界" --pages 5 --markdown
```

也支持环境变量：

- `QIEMAN_COOKIE`
- `QIEMAN_ACCESS_TOKEN`

## 看板能力

当前看板已经拆成三类页面：

- 首页 `/`
  只展示摘要，避免页面过长。
- 平台调仓 `/platform`
  只看且慢平台真实调仓数据。
- 论坛发言 `/forum`
  只看主理人社区发言和评论。
- 调仓时间线 `/timeline`
  单独看按标的聚合的真实调仓轨迹。

### 平台调仓

平台调仓来自且慢平台接口 `/long-win/plan/adjustments`，不是从帖子里推断买卖动作。

支持：

- 真实调仓记录、买入动作、卖出动作
- 时间筛选
  - `全部`
  - `近30天`
  - `近60天`
  - `今年`
  - `近1年`
- 当前持仓情况
- 当前持仓分类占比
- 单独的按标的时间线页面

当前持仓分类采用更常见的资产分类口径：

- 宽基指数
- 行业主题
- 红利策略
- 主动权益
- 海外权益
- 海外债券
- 债券固收
- 黄金

当前无持仓的分类不会显示。

### 持仓成本与估值

平台持仓卡片里会显示：

- 平均成本
- 当前估值
- 按当前份数估值
- 相对成本

口径说明：

- 平均成本：
  基于且慢平台的全量调仓历史，按调仓日期回填基金净值，并用移动平均法估算当前剩余份额的平均成本。
- 当前估值：
  优先使用天天基金盘中估值；拿不到盘中估值时，回退到最近官方净值。
- 按当前份数估值：
  这是为了比较平均成本和当前估值的归一化值，不等于真实账户金额。

这个模块的主要用途是辅助判断“当前估值相对自己的历史持仓成本是偏高还是偏低”，不是直接给出投资建议。

### 论坛发言与评论

论坛页面支持：

- 历史快照浏览
- 实时刷新最新发言
- 关键词和日期范围筛选
- 展开正文
- 展开评论
- `热评 / 最新评论` 切换
- `加载更多评论`
- `只看主理人回复过的评论`

### 平台与论坛拆分

看板现在明确分成两块：

- `平台调仓`
  来自平台接口的真实调仓动作。
- `论坛发言`
  来自社区的帖子、正文、评论和回复。

两者不再混在同一个模块里。

## 输出结果

抓取结果默认写入：

```text
output/
```

常见输出包括：

- `*.json`
- `*.md`

这些文件适合留在本地做历史快照，不建议默认提交到仓库。

## 说明

- 当前版本优先抓公开内容页，稳定性比直接扫社区页面更高。
- 社区接口里有登录态和校验逻辑，所以登录后模式推荐使用 `qieman.cookie`。
- 查询词越具体，结果越准，例如主理人昵称、策略名、栏目名。
- 看板默认只监听本机 `127.0.0.1`。

## 安全建议

- 不要把 `qieman.cookie` 提交到 Git。
- 不要把包含隐私数据的 `output/` 快照直接公开。
- 如果 Cookie 已经用于调试并且不再需要，建议删除或重新登录刷新。
