# 平台下限 API 23，版本号 2.0.0

`compatibleSdkVersion` 与 `targetSdkVersion` 保持 `6.1.0(23)`；`versionName` 取 `2.0.0`、`versionCode` 取 `2000000`（参考实现为 `1.1.0` / `1000042`）；`bundleName` `com.koracan.learnOH` 不变。

参考实现的产物下限是 `6.0.0(20)`（其 README 声称"HarmonyOS 5+"，与工程实际不符）。因为 bundleName 相同，这是一次同应用升级，抬高下限意味着 **HarmonyOS 5.x 与 6.0 的设备在应用市场看不到这次更新**，将永久停留在 RN 版 1.1.0。

**Status**: accepted —— 这是有意接受的产品后果（鸿蒙用户系统更新积极），换取直接用满 API 23 的能力、不必为 API 20 写降级分支。若日后要降低下限，代价是逐 API 排查与在 API 20 设备上重新验证，而不是一次机械改动。
