# 第三方组件与许可 / Third-party components

Orange 本身以 MIT 许可发布（见 LICENSE），并基于 Aerial 修改。安装包里还带着下面这些组件；每一行的许可全文都在对应项目的仓库里。装好后的电视上也能在「设置 → 关于 → 开源许可」里读到本文件。

- AndroidX Compose（ui / foundation / animation，BOM 2025.11.01）1.9.5 — Apache-2.0 — 界面
- androidx.activity:activity-compose 1.10.1 — Apache-2.0 — 界面宿主
- androidx.lifecycle:lifecycle-viewmodel-compose 2.9.2 — Apache-2.0 — 状态
- androidx.core:core-ktx 1.16.0 — Apache-2.0 — 兼容工具
- androidx.profileinstaller 1.4.0 — Apache-2.0 — Baseline Profile 安装
- androidx.media3（exoplayer / datasource / database）1.8.1 — Apache-2.0 — 航拍影片播放
- Kotlin 标准库（kotlin-stdlib、kotlinx-coroutines）随 Kotlin 插件 — Apache-2.0 — 运行时
- org.nanohttpd:nanohttpd 2.3.1 — BSD-3-Clause — 手机整理页的局域网服务
- com.google.zxing:core 3.5.3（Lite 用 3.3.0）— Apache-2.0 — 二维码
- com.android.tools:desugar_jdk_libs 2.1.5 — GPL-2.0-only WITH Classpath-exception-2.0 — Java 8 API 在 Android 5 上的兼容层
- Inter 字体 — SIL Open Font License 1.1，全文见 FONT-LICENSE-OFL.txt — 界面字体
- GeoNames 中国城市表 — CC BY 4.0 — 天气城市名（assets/cities-cn.tsv）
- Open-Meteo 天气数据 — CC BY 4.0 — 天气（运行时请求，不随包分发）

仅用于开发与测试、不进入发布包的：JUnit 4.13.2（EPL-1.0）、Robolectric 4.17（MIT）。

## 上游

Orange 是 Aerial 的修改版（https://github.com/pengchujin/aerial-tv），上游以 MIT 发布，Copyright (c) 2026 pengchujin。上游的版权声明与许可全文保留在 LICENSE 中，未作删改；Orange 的修改部分另有版权行。

航拍影片的版权归 Apple，由 Apple 的服务器直接播放，不随本应用分发。每日精选壁纸来自必应（Bing）。

## Third-party components (English)

Orange is released under the MIT licence (see LICENSE) and is a modified version of Aerial. The APK bundles the components listed above; every licence is available in the corresponding project's repository, and the TV shows this file under Settings → About → Open-source licences.

Aerial films belong to Apple and stream from Apple's servers; they are not distributed with this app. The photo of the day comes from Bing.
