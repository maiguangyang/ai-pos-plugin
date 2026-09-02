# ai_pos_plugin_host

用于独立开发和验证 AI POS 编译期第三方 package 的 Android/iOS Flutter 宿主。启动后先显示宿主页，点击 `Open example plugin` 会 push 全屏插件 Shell；第三方页面没有宿主标题栏，但始终保留右上角关闭胶囊，点击后返回宿主页。

从 `ai-pos-plugin` 根目录执行 `make verify` 可验证公共 API、运行时、testkit、示例插件和本宿主。业务接入规则见根目录 `README.md` 与 `integrations/README.md`。

开发插件时只依赖 `ai_pos_plugin_api`。用 `AiPosPluginContractHarness` 验证初始化、协作取消、超时和幂等释放，用 `FakeAiPosPluginPageContext` 验证退出结果；测试 package 不需要也不应依赖宿主 runtime。
