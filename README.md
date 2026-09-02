# AI POS Plugin Platform

本目录是 EasyPOS 的编译期 Flutter 插件平台。宿主制定公共合同，第三方把一套业务功能实现为独立 package；同一 package 既可由合作方自己的 Flutter App 运行和发布，也可在审核后由宿主显式依赖、注册并重新构建 App。

它不是微信小程序式的动态运行时：没有在线下载代码、独立解释器或进程沙箱。插件与宿主共享 Flutter Engine、进程、内存和崩溃域，因此源码、依赖和权限都必须进入发布审核。

## 目录

```text
ai-pos-plugin/
├── core/
│   ├── ai_pos_plugin_api/       # 第三方唯一允许依赖的稳定合同
│   ├── ai_pos_plugin_runtime/   # 宿主注册、能力与生命周期管理
│   └── ai_pos_plugin_testkit/   # 第三方合同测试与 CI 边界检查
├── integrations/                # 一个系统一个 Integration Workspace
│   └── <system>/
│       ├── packages/<system>_integration/ # 共享业务与插件适配器
│       └── apps/<system>_app/              # 可独立运行、打包和发布
└── example/
    └── plugin_host/
        ├── packages/ai_pos_example_plugin/ # 独立开发示例
        └── android, ios, lib/              # 最小可运行宿主
```

## 依赖方向

允许的方向如下：

```text
第三方独立 App ─→ integration package ─→ ai_pos_plugin_api
                           │                    ↑
                           └─→ 可用 testkit 测试 │
                                                │
ai-pos-app ─→ runtime + integration package ────┘
```

第三方业务 package 不得依赖 `ai-pos-app`、runtime、其他第三方 package 或宿主内部服务。testkit 只依赖 API，不依赖 runtime 或 App。宿主负责把公共能力实现为 `AiPosPluginContext`，插件只声明并使用被授予的能力。

依赖门禁同时检查 Dart 的 `import / export / part` 与 `pubspec.yaml` 的 `dependencies / dev_dependencies / dependency_overrides`。根目录 `make verify` 会自动发现每个 Workspace 下的 integration package 和独立 App，无需手工维护验证清单。

## API 兼容策略

公共 API 当前为 `0.3`。在稳定到 `1.0` 前，宿主与插件要求的 major、minor 必须完全相同，例如宿主 `0.3` 只接受要求 `0.3` 的插件。进入稳定版本后，同 major 下宿主 minor 大于等于插件要求的 minor 即兼容。破坏合同必须提升 major。

## 生命周期与页面边界

插件的完整最小生命周期是 `register -> initialize -> ready -> dispose`。`initialize(context, lifecycle)` 接收只读的初始化 Context 和协作式取消信号；插件必须定期检查 `lifecycle.isCancellationRequested`、等待 `cancellationRequested`，或调用 `throwIfCancellationRequested()`。初始化失败、超时、宿主关闭都会触发一次有界清理，`dispose()` 必须支持部分初始化、幂等执行，并关闭所有已创建资源。

`AiPosPluginContext` 只在初始化阶段提供 Locale 和已授权 capability。每个活动页面会话拥有独立的 `AiPosPluginPageContext`；调用 `pageContext.close(result: value)` 会强制关闭整个插件会话并回到宿主。页面必须监听 `visibilityListenable`：`foreground` 可交互，`floating` 保留页面状态但应暂停 Timer、动画、定位等非必要生产者，`closing` 必须停止生产并准备释放。会话关闭后 PageContext 自动失效。

宿主使用 `AiPosPluginPageShell` 全屏承载第三方 UI。Shell 和顶部 bar 透明，不显示宿主 AppBar，只保留 SafeArea 内右上角双按钮胶囊；第三方内容拥有背景、AppBar 和嵌套 Navigator。`…` 从底部打开宿主管理的操作 Sheet：顶部展示 manifest 的 `name` 与 `description`，操作仅包含“浮窗”和“重新进入小程序”。重新进入只重建入口页面和内部路由栈，不重复初始化插件实例。右侧圆形按钮以页面投影缩小、淡出并关闭。系统返回键先退出第三方内部页面；胶囊和 PageContext 可直接退出整个插件，不能被第三方 `PopScope` 拦截。右上角是宿主保留区域，第三方页面不要把关键操作放在其下方。

浮窗完全位于宿主 Flutter 进程内，不申请系统悬浮窗权限，也不跨冷启动持久化。最多保留五个浮窗；第六个捕获完成时按先进先出关闭最老会话。点击 dock 展开全部卡片，向左拖动按距离连续展开，释放同时考虑位置与速度。收起时页面投影连续缩小到右侧 dock；点击缩略图时从该卡片的真实位置和尺寸连续放大到全屏。恢复入口不限于卡片：Drawer、快捷入口或未来 deep-link adapter 只要打开同一插件 ID，都恢复同一个活页面；真实页面先在投影后完成一帧，再撤下并精确释放快照。系统启用减少动态效果时，这些空间动画退化为短淡入淡出。

所有插件页面都允许生成仅驻留内存的快照。持久浮窗快照物理宽度不超过 `480px`，总估算存储不超过 `12 MiB`（`width × height × 4`）；像素不编码、不落盘、不缓存、不记录或分析。PlatformView/捕获失败时页面保持前台；关闭投影失败时降级为当前层变换或淡出。

取消和可见性都是同进程内的协作合同，不是强制终止：恶意代码、忽略取消的 Future、static 单例或原生 SDK 引用无法被 Dart runtime 强制回收。

## 第三方系统如何存放

默认一个真实业务系统对应 `integrations/` 下一个 lowercase_snake_case Workspace。`packages/<system>_integration` 保存唯一一份页面、接口对接、状态管理、插件适配器和测试；`apps/<system>_app` 是依赖该 package 的薄 Flutter Application，可单独运行和发布。两种形态不得复制业务实现。

默认使用纯 Flutter package。若必须接入原生 SDK，应单独提交必要性说明，并完成权限、隐私清单、供应链和 Android/iOS 原生代码审查后才能进入宿主。

## 接入流程

1. 第三方只依赖 `ai_pos_plugin_api`，参考示例 package 实现 manifest、页面和生命周期。
2. 在 Workspace 自己的 `apps/<system>_app` 中独立运行和热重载，并用 testkit 验证合同和导入边界。
3. 提交完整源码、依赖清单、网络/存储/日志/权限说明，不提交密钥。
4. 宿主团队审查通过后，把真实 Workspace 或其不可变 integration package 版本纳入组合。
5. 宿主在自己的 `pubspec.yaml` 和注册表中显式加入该 package。
6. 重新分析、测试和构建 App；插件不会在运行时自行下载或启用。

第三方在提交前还必须运行 retained-path 内存测试：反复进入/退出页面并触发初始化失败、取消和超时，确认旧页面的 BuildContext、PageContext、Controller 和业务对象不再能从 Timer、Stream、回调、重试任务、单例或原生监听器访问。

本地完整验证：

```bash
cd ai-pos-plugin && make verify
```

安全提示：编译期 package 没有安全沙箱。第三方代码可消耗宿主资源并影响稳定性；能力合同是架构边界，不是进程级隔离。
