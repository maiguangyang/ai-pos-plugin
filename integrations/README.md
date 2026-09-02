# Third-Party Integrations

这里只存放已经确认并通过审核的真实第三方业务 Workspace，以及明确标注为 EasyPOS-owned development-only 的验证 Workspace。不要创建空目录、占位 vendor 或虚构合作方。

## 命名与结构

- Workspace 目录使用 `lowercase_snake_case`；共享 package 和独立 App 分别使用 `<name>_integration`、`<name>_app`。
- Manifest ID 使用反向域名，例如 `com.partner.delivery`，由合作方身份和业务域共同确定。
- 默认一个第三方系统一个 Workspace；共享业务只能存在于 integration package，独立 App 只负责启动、平台配置、签名和发布。
- package 必须包含 manifest/插件入口、按 feature 组织的共享业务代码、测试和直接依赖清单；manifest 的 `name` 与 `description` 会显示在宿主操作 Sheet 中。

推荐结构：

```text
integrations/<partner_system>/
├── integration.yaml
├── README.md
├── packages/
│   └── <partner_system>_integration/
│       ├── lib/<partner_system>_integration.dart
│       ├── lib/src/<feature>/
│       ├── test/
│       └── pubspec.yaml
└── apps/
    └── <partner_system>_app/
        ├── android, ios, lib/
        ├── test/
        └── pubspec.yaml
```

## 强制边界

- 只能通过 `ai_pos_plugin_api` 与宿主协作；禁止导入 `package:ai_pos_app/...` 或任何指向 `ai-pos-app` 的相对路径。
- 禁止依赖 `ai_pos_plugin_runtime`、其他 integration、宿主的 GraphQL/client/provider/数据库实现。
- 门禁会同时扫描 Dart 指令和 `pubspec.yaml` 依赖区；仅声明但暂未 import 的禁止依赖同样不能通过 `make verify`。
- `apps/<system>_app` 可以依赖同一 Workspace 的 integration package，但业务页面、Repository 和状态不得在 App 中复制。
- 禁止把 API key、token、私钥、账号或测试凭据写入源码、资源、日志或提交历史。
- 所需宿主数据和操作必须先抽象为受版本控制的 capability；不得绕过合同访问宿主内部对象。

## 审核清单

- 源码：入口、页面、生命周期和异常路径可审查，合同测试齐全。
- 依赖：来源、版本、许可证、维护状态和传递依赖可接受。
- 网络：域名、协议、超时、重试、证书策略和数据范围明确。
- 存储：保存内容、位置、加密、清理和迁移策略明确。
- 日志：不记录凭据、个人数据或原始敏感异常。
- 权限：声明最小 Flutter/系统权限，拒绝未授权能力时行为安全。
- 原生代码：单独审核 Android/iOS 实现、隐私清单、供应链和二进制来源。
- 集成：宿主显式添加依赖和注册，完整执行 `make verify` 后重新构建。
- 验证：`make verify` 自动发现 `integrations/*/packages/*` 与 `integrations/*/apps/*`，新增 Workspace 不得依赖人工补充 Makefile 清单。

## 资源所有权清单

每个插件必须记录资源由页面还是插件实例拥有，并在相应的 `State.dispose()` 或插件 `dispose()` 中清理：

- `Timer`、debounce/throttle、后台任务：取消并清除持有业务对象的回调。
- `StreamController`、`StreamSubscription`、ChangeNotifier/Controller：先停止生产，再取消订阅并关闭或 dispose。
- 网络请求与自动重试：设置超时，响应 lifecycle 取消，禁止无限重试和退出后的回调写状态。
- 原生 listener、MethodChannel/EventChannel、SDK delegate：对称注销，说明 native 端是否仍可能持有 Dart 回调。
- 页面 BuildContext、PageContext 和 result：不得写入 static、全局单例、长生命周期缓存或插件实例字段。
- 页面可见性：监听 `foreground / floating / closing`；浮窗时暂停非必要 Timer、动画和原生监听，恢复时复用原业务状态，页面销毁时对称移除 visibility listener。
- 快照：所有页面可被宿主捕获为仅内存快照；禁止插件读取、编码、持久化、记录或分析宿主浮窗像素。

宿主最多保留五个浮窗并按 FIFO 淘汰。无论用户从浮窗卡片、Drawer、快捷入口还是其他宿主入口回到同一插件，runtime 都会销毁旧快照后恢复原页面；integration 不得自行复制会话或缓存快照。

`dispose()` 必须可在初始化只完成一部分时调用，并且重复调用结果一致。合同测试除“调用过 dispose”外，还要断言 Timer 已停止、订阅已取消、Controller 已关闭、PageContext 已失效；对真实 SDK 需使用 DevTools heap/retaining path 或等价工具验证多轮进入退出后旧对象不可达。
