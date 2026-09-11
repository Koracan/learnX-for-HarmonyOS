# 放弃 RN 运行时，改为 ArkTS 原生重写

参考实现是 React Native for OpenHarmony 应用；本工程已有可构建、可签名、可真机部署的原生骨架。我们决定**不使用 RNOH 混编**（不保留 RN 运行时），而是把每个功能以 ArkTS / ArkUI 原生重写，参考实现仅作为行为契约。

理由是混编保留的问题远多于它省下的工作：参考实现为让依赖在鸿蒙上工作，打了两个包的源码补丁（`react-native-file-viewer`、`react-native-share` 的 `file://` 路径处理）、被迫 `enableScreens(false)`、转场动画默认失效需手动开启、每个依赖都要手写 `harmony.alias` 与 TS path 映射。混编会把"移植"变成"长期维护 RN 生态在鸿蒙上的兼容层"。

**Considered Options**：RNOH 混编（保留 JS 层，只重写部分 UI）；逐文件机械翻译 `.tsx → .ets`。前者锁死在 RN 依赖的适配缺口上，后者在 ArkUI 里没有 `react-native-paper`/`reanimated`/`gesture-handler` 的对应物，只会得到既不像 RN 也不像鸿蒙的结果。
