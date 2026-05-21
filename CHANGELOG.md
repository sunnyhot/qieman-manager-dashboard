# Changelog

## [2.5.6] - 2026-05-21

### Fixed
- 修复收到推送通知后 createMainWindow() 在后台线程崩溃 (SIGABRT) (LUC-195)
  - 在 AppModel.init() 的 Combine 订阅中添加 .receive(on: DispatchQueue.main)

## [2.5.5] - 2026-05-21

### Fixed
- 开机自启动后，若设置中 Dock 为不显示，自动隐藏 Dock 图标 (LUC-187)
  - 在 `applicationDidFinishLaunching` 中立即读取 UserDefaults 并设置 activationPolicy

## [2.5.4] - 2026-05-21

### Fixed
- 改进浅色模式对比度

## [2.5.3] - 2026-05-20

### Fixed
- 防止个人资产表格重叠
- 构建脚本增加产物完整性验证

## [2.5.2] - 2026-05-20

### Fixed
- QiemanDashboardApp 编译错误修复
- latest.json 指向正确版本

## [2.5.1] - 2026-05-20

### Fixed
- 解决 AppModel 合并冲突
- 去掉 clipShape 避免裁剪表格详情内容
