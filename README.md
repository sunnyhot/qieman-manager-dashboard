# 且慢主理人看板 / Qieman Manager Dashboard

> 一个面向本地使用的且慢工具箱：既能抓主理人论坛发言和平台调仓，也能作为原生 macOS App 管理个人持仓、待确认买入、定投计划、菜单栏估值与系统通知。

## 项目现状

这个仓库现在已经不是单一爬虫脚本，而是四层能力放在一起：

1. **原生 macOS App**
   - SwiftUI 原生界面
   - 原生登录窗口，自动抓取并保存且慢登录态
   - 原生“我的持仓 / 平台调仓 / 论坛发言 / 历史快照”
   - 菜单栏弹框显示个人持仓的实时估值、今日涨跌、总收益，并支持排序
   - 关闭主窗口后可只保留菜单栏，支持开机自启
   - 可定时巡检主理人调仓和发言，并通过系统通知推送，点击通知可直接跳到对应详情

2. **本地浏览器看板（兼容工具）**
   - `dashboard_server.py` 提供浏览器版看板
   - 当前主要作为调试与兼容工具保留，不再作为原生 App 的导航入口

3. **Python 抓取脚本**
   - `qieman_scraper.py`：抓且慢公开内容页
   - `qieman_community_scraper.py`：抓社区公开/登录态动态、关注流、小组流、空间流
   - 零第三方 Python 依赖，默认使用系统 Python 标准库即可运行

4. **给 OpenClaw / Hermes / Codex 的技能层**
   - `skills/qieman-alpha-signals/` 提供原子化脚本能力
   - 支持一键拉起整个项目、增量监听新调仓/新发言、估值查询、调仓时间线、快照读取、信号提取等

## 现在能做什么

### 主理人内容与调仓

- 抓取且慢公开内容页，支持关键词、作者过滤
- 抓取社区主理人动态，支持：
  - `group-manager`
  - `following-posts`
  - `following-users`
  - `my-groups`
  - `space-items`
  - `auth-check`
- 平台调仓直接走平台接口，不再靠论坛文本猜测
- 平台调仓页支持：
  - 买入 / 卖出拆分
  - 调仓时间线
  - 月度交易总览
  - 窄窗口单双栏自适应
- 论坛发言页支持：
  - 列表 + 详情浏览
  - 评论抓取
  - 主理人回复过滤
  - 窄窗口单双栏自适应

### 个人资产与估值

- 录入 **持仓中 / 买入中 / 定投计划**
- 支持 **手动录入 / 上传图片 OCR / 上传表格** 三种导入方式
- “我的持仓”页可按基金聚合展示：
  - 实时估值
  - 今日涨跌金额 / 涨跌率
  - 总收益金额 / 总收益率
  - 待确认金额
  - 定投计划状态
- 菜单栏弹框可直接查看：
  - 总资产估值
  - 今日涨跌
  - 总收益
  - 每只持仓标的的实时估值、今日涨跌、总收益
  - 排序方式：按今日涨跌 / 按总收益 / 按市值

### 登录、通知与自动巡检

- App 内嵌登录窗口，直接在 WebView 中完成登录
- 自动检测并保存 `qieman.cookie`
- 可开启主理人通知巡检：
  - 监控平台调仓
  - 监控主理人发言
  - 频率可调
  - 支持开机自启
  - 点击系统通知可跳到对应调仓或发言详情

## 仓库结构

```text
.
├── dashboard_server.py                  # 浏览器版本地看板
├── qieman_scraper.py                    # 抓且慢公开内容
├── qieman_community_scraper.py          # 抓社区流 / 关注流 / 主理人动态
├── macos-app/                           # 原生 macOS App（SwiftUI）
├── scripts/                             # 打包、导入、辅助脚本
├── skills/qieman-alpha-signals/         # 给 Agent 用的原子能力 skill
├── output/                              # 本地快照与历史抓取结果
├── qieman.cookie                        # 本地登录态（不要提交）
└── README.md
```

## 环境要求

### Python / Web 看板

- macOS / Linux / Windows 均可运行 Python 脚本
- Python 3.x
- **不需要安装任何第三方 Python 包**

### 原生 macOS App

- macOS 14+
- Xcode Command Line Tools
- 需要系统自带工具：
  - `swiftc`
  - `iconutil`
  - `codesign`
  - `ditto`

## 快速开始

## 方式一：运行原生 macOS App

### 构建

```bash
cd /Users/xufan65/Documents/Codex/2026-04-17-new-chat
bash scripts/build_macos_app.sh
```

### 产物

- App Bundle：`dist/macos-app/QiemanDashboard.app`
- 分发压缩包：`dist/macos-app/QiemanDashboard-2.1.4.zip`

### 运行

```bash
open dist/macos-app/QiemanDashboard.app
```

### 打包脚本会自动完成的事

- 生成 `.icns` 图标
- 编译 SwiftUI 原生 App
- 写入版本号、构建号、Bundle ID、最低系统版本
- 进行本地 ad-hoc 签名
- 输出 `.zip` 分发包

### 自定义构建参数

```bash
APP_VERSION=2.1.4 \
APP_BUILD=210 \
BUNDLE_ID=com.sunnyhot.qieman.manager.dashboard \
MIN_MACOS_VERSION=14.0 \
bash scripts/build_macos_app.sh
```

### 自动检查更新

原生 App 会在启动后自动轻量检查一次更新，也可以在右上角「更多」菜单或 macOS 应用菜单里手动点「检查更新」。发现新版本后，应用会弹出更新窗口；用户点「下载并重启安装」后，App 会下载 GitHub 上的 zip，校验 Bundle ID、版本号和签名，再覆盖当前 `.app` 并自动重启。默认更新源是仓库里的静态更新清单：

```text
https://raw.githubusercontent.com/sunnyhot/qieman-manager-dashboard/main/releases/macos/latest.json
```

发布新版本时：

```bash
APP_VERSION=2.1.4 bash scripts/build_macos_app.sh
cp dist/macos-app/QiemanDashboard-2.1.4.zip releases/macos/
# 同步更新 releases/macos/latest.json 里的 tag_name、资源 URL 和 size
git add releases/macos/latest.json releases/macos/QiemanDashboard-2.1.4.zip
git commit -m "Publish QiemanDashboard 2.1.4"
git push
```

也可以通过环境变量覆盖更新仓库或更新源：

```bash
UPDATE_REPOSITORY=sunnyhot/qieman-manager-dashboard \
UPDATE_FEED_URL=https://raw.githubusercontent.com/sunnyhot/qieman-manager-dashboard/main/releases/macos/latest.json \
bash scripts/build_macos_app.sh
```

如果希望继续用 GitHub Releases，也可以把 `UPDATE_FEED_URL` 指到 `https://api.github.com/repos/<owner>/<repo>/releases/latest`，应用兼容 GitHub Release API 的 JSON 结构。

### 签名说明

当前构建脚本做的是 **本地 ad-hoc 签名**，适合自用与测试。

如果要对外正式分发并尽量消除系统安全提示，还需要：

- Apple Developer 证书
- Notarization（苹果公证）

## 方式二：运行浏览器版看板

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

## 登录与 Cookie

### 在 App 中登录

推荐直接使用 App 里的 **“登录且慢”**：

- 在内嵌登录页完成登录
- App 会检测 `qieman.com` 登录态
- 自动保存到本地 `qieman.cookie`
- 不需要再手工复制粘贴 Cookie

### 在脚本中使用登录态

可以使用以下任一方式：

- 根目录 `qieman.cookie`
- `--cookie-file /path/to/qieman.cookie`
- `--cookie-env YOUR_ENV_NAME`
- `--access-token` / `--access-token-env`

### 验证登录态

```bash
python3 qieman_community_scraper.py --mode auth-check --cookie-file qieman.cookie
```

## 主理人内容抓取

### 抓公开内容页

```bash
python3 qieman_scraper.py --query "长期指数投资" --markdown
```

按主理人过滤：

```bash
python3 qieman_scraper.py --query "长赢计划" --author "ETF拯救世界" --markdown
```

### 抓社区主理人动态

按产品代码解析公开小组：

```bash
python3 qieman_community_scraper.py --prod-code LONG_WIN --pages 3 --markdown
```

按主理人昵称解析：

```bash
python3 qieman_community_scraper.py --mode group-manager --manager-name "ETF拯救世界" --pages 5 --markdown
```

抓登录后的关注动态：

```bash
python3 qieman_community_scraper.py \
  --mode following-posts \
  --user-name "ETF拯救世界" \
  --cookie-file qieman.cookie \
  --pages 5 \
  --markdown
```

抓单帖评论：

```bash
python3 skills/qieman-alpha-signals/scripts/post_comments_query.py \
  --post-id 1234567890 \
  --sort-type hot \
  --page-size 20 \
  --json
```

## 个人资产：持仓中 / 买入中 / 定投计划

原生 App 的“我的持仓”页现在支持统一管理三类个人数据：

- 持仓中
- 买入中
- 定投计划

### App 内支持的导入方式

每一类都支持：

- **手动录入**：直接粘贴文本到草稿框
- **上传图片**：先 OCR，再进入草稿区确认
- **上传表格**：支持 `txt / csv / tsv / json / xlsx`

导入不会直接覆盖正式数据，而是先进入草稿区，确认后再保存。

### 持仓中示例格式

```text
021550 1200 1.1304 博时红利低波100
博时红利低波100 021550 1200 1.1304
```

含义：

- 基金代码必填
- 份额必填
- 成本价可选
- 名称可选

### 买入中示例格式

```text
2026-04-23 09:48:33 | 定投 | 华泰柏瑞纳斯达克100ETF联接(QDII)A | 10.00元 | 交易进行中
2026-04-22 14:10:02 | 买入 | 国泰中证畜牧养殖ETF联接A | 3000.00元 | 交易进行中
```

### 定投计划示例格式

```text
定投 | 易方达恒生科技ETF联接(QDII)A | 每周三定投 | 500.00元 | 2 | 1000.00元 | 余额宝 | 2026-04-29(星期三)
智能定投 | 华夏中证A500ETF联接A | 每周二定投-涨跌幅模式 | 250.00~1,000.00元 | 2 | 1000.00元 | 余额宝 | 2026-04-28(星期二)
```

### 支付宝文本导入脚本

#### 1. 导入支付宝持仓摘要

```bash
python3 scripts/import_alipay_portfolio.py \
  --input /path/to/alipay-holdings.txt \
  --preview /tmp/alipay-import-preview.json
```

输入格式：`基金名 | 当前金额 | 持有收益 | 持有收益率`

#### 2. 导入支付宝交易进行中

```bash
python3 scripts/import_alipay_pending_trades.py \
  --input /path/to/alipay-pending.txt \
  --preview /tmp/alipay-pending-preview.json
```

输入格式：`时间 | 动作 | 基金名 | 金额/份额 | 状态`

#### 3. 导入支付宝定投计划

```bash
python3 scripts/import_alipay_investment_plans.py \
  --input /path/to/alipay-plans.txt \
  --preview /tmp/alipay-plans-preview.json
```

#### 4. 把 OCR / 表格预处理为导入草稿

```bash
python3 scripts/prepare_personal_import.py \
  --target holdings \
  --source ocr \
  --input /path/to/ocr.txt
```

可选 `--target`：

- `holdings`
- `pending_trades`
- `investment_plans`

可选 `--source`：

- `ocr`
- `table`

## App 中“我的持仓”现在会显示什么

### 顶部汇总

- 总持仓估值
- 今日涨跌
- 总收益
- 待确认金额
- 计划档案
- 覆盖基金数

### 每只标的维度

- 实时估值
- 今日涨跌金额 / 涨跌率
- 总收益金额 / 总收益率
- 待确认买入
- 计划状态
- 当前价格 / 成本 / 价格来源

### 菜单栏弹框

菜单栏弹框已经对齐到个人资产视角，不再优先显示主理人提醒大卡片。当前会显示：

- 总资产估值
- 今日涨跌
- 总收益
- 总收益率
- 每只持仓标的的：
  - 实时估值
  - 今日涨跌
  - 总收益
  - 现价 / 成本 / 来源
- 排序方式：
  - 按今日涨跌
  - 按总收益
  - 按市值

## 主理人通知巡检

App 内置了主理人监控设置，可以：

- 监控平台调仓
- 监控主理人发言
- 设置巡检频率
- 点击通知跳转到对应详情
- 结合菜单栏常驻使用

### CLI 增量巡检脚本

如果你想在终端或自动化中使用，可以直接运行：

```bash
python3 skills/qieman-alpha-signals/scripts/updates_watch.py \
  --prod-code LONG_WIN \
  --manager-name "ETF拯救世界" \
  --forum-mode auto \
  --json
```

说明：

- 首次运行默认只建立基线，不提醒历史数据
- 后续运行只返回新增调仓和新增发言
- 状态文件默认落在 `output/watch-state-*.json`

## 给 OpenClaw / Hermes / Codex 用的 Skills

仓库里已经带了可复用的 agent skill：

### 1. `qieman-alpha-signals`

路径：`skills/qieman-alpha-signals/`

用途：给 Agent 提供原子化能力调用，包括：

- 登录态检查
- 关注用户查询
- 小组解析
- 关注流 / 小组流 / 空间流 / 公开内容流
- 评论抓取
- 平台调仓
- 平台持仓
- 调仓时间线
- 月度交易概览
- 估值查询
- 快照索引 / 快照读取
- 信号提取
- 增量巡检
- 一键拉起整个项目

一键运行整个项目：

```bash
python3 skills/qieman-alpha-signals/scripts/project_runtime.py --open-browser --json
```

### 2. `qieman-manager-dashboard`

这个 skill 更像“控制层”，适合把整个项目当作一个可复用工具来调度。

## 数据目录

### 仓库里的本地输出

- `output/`：主理人抓取结果、历史快照、监控状态文件

### App 运行时数据目录

App 不会把运行时数据写进 `.app`，而是写到：

`~/Library/Application Support/QiemanDashboard`

常见文件包括：

- `qieman.cookie`
- `output/`
- `user-portfolio.json`
- `user-pending-trades.json`
- `user-investment-plans.json`
- `manager-watch-settings.json`
- `dashboard.log`

## 常用命令速查

### 一键拉起浏览器版看板

```bash
python3 dashboard_server.py --open
```

### 查公开内容

```bash
python3 qieman_scraper.py --query "长期指数投资" --markdown
```

### 查社区主理人动态

```bash
python3 qieman_community_scraper.py --prod-code LONG_WIN --pages 3 --markdown
```

### 验证登录态

```bash
python3 qieman_community_scraper.py --mode auth-check --cookie-file qieman.cookie
```

### 一键管理项目运行（dashboard + 前端页面）

```bash
python3 skills/qieman-alpha-signals/scripts/project_runtime.py --action start --open-browser --json
python3 skills/qieman-alpha-signals/scripts/project_runtime.py --action status --json
python3 skills/qieman-alpha-signals/scripts/project_runtime.py --action stop --json
```

## 说明

- `output/` 和 `qieman.cookie` 都属于本地工作数据，不是源码的一部分
- 默认推荐使用原生 macOS App；浏览器版主要作为调试与兼容工具保留
- 当前 App 打包是“本地正式产物”级别：有完整 bundle、版本号、zip 和 ad-hoc 签名；如果要对外分发，还建议补苹果开发者签名和 notarization
