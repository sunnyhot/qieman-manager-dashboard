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
