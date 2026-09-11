# learnOH

HarmonyOS 原生（ArkTS / ArkUI）重写版本的 learnOH：原 [React Native for OpenHarmony](https://gitcode.com/openharmony-sig/ohos_react_native) 应用的功能迁移目标工程。

> 注意：本应用只适用于清华大学学生。
>
> Note: the App is for Tsinghua University students only.

本仓库前身是 learnOH 的 React Native for OpenHarmony 实现，上游项目为 [robertying/learnX](https://github.com/robertying/learnX)。

## 下载 Download

### HarmonyOS 5+

- [在 AppGallery 下载 Download from AppGallery](https://appgallery.huawei.com/app/detail?id=com.koracan.learnOH)

## 当前状态 Status

工程骨架已搭建完成，可通过命令行构建并签名，但**功能尚未移植**：`entry` 模块目前只有 DevEco 模板生成的 Hello World 页面。

- [x] 原生工程骨架（API 23 / HarmonyOS 6.1.0）
- [x] 复用原有应用签名（release 证书与 Profile 与原应用完全一致）
- [x] 命令行构建产出已签名产物
- [x] 真机部署验证（HUAWEI MatePad Air，已安装启动并正常渲染）
- [ ] 真实功能移植

## 环境要求 Requirements

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| DevEco Studio | 6.1.1（DS-243.24978.46.36.611290） | 提供 hvigor / ohpm / SDK |
| HarmonyOS SDK | API 23 / 6.1.0(23) | `targetSdkVersion` 与 `compatibleSdkVersion` |
| devecocli | 1.3.2 | 由 `mise.toml` 固定，`devecocli` 命令 |
| JDK | DevEco 自带 JBR | 签名工具依赖 |

## 目录结构 Layout

```
.
├── AppScope/                     # 应用级配置与图标（bundleName、versionCode 等）
├── entry/                        # 主 HAP 模块
│   └── src/main/
│       ├── ets/                  # ArkTS 源码（entryability / pages / ...）
│       ├── resources/            # 资源
│       └── module.json5          # 模块声明（abilities、权限、deviceTypes）
├── keys/                         # 签名材料（.gitignore 忽略，本机专用）
├── reference/learnOH-old/        # 原 RN for OpenHarmony 工程（忽略，移植参考）
├── build-profile.json5           # 签名配置与产物定义
├── oh-package.json5              # ohpm 依赖
└── mise.toml                     # 固定 devecocli 版本
```

应用标识与原应用保持一致：`com.koracan.learnOH`，版本 `1.1.0`（versionCode `1000042`），设备类型 `phone` / `tablet` / `2in1`。

## 构建 Build

```powershell
# 日常开发 / 装机调试（默认，使用 debug 签名）
devecocli build --product default --build-mode debug

# 发布产物（需先把 products[0].signingConfig 改成 "release"）
devecocli build --product default --build-mode release

# 产物位置
#   build/outputs/default/learnOH-default-signed.app
#   entry/build/default/outputs/default/entry-default-signed.hap
```

静态检查：

```powershell
devecocli check lint
```

## 部署 Run

```powershell
devecocli device list                  # 先确认唯一目标设备
devecocli run --device <name|serial>   # 构建、安装、启动
```

## 功能与许可 Features & License

功能范围与原应用一致（通知、课程文件、作业、归档、收藏、隐藏课程、暗黑模式、全局搜索、切换学期等），待移植。

以 MIT 许可证开源，但**不包含**下列情况：

- 您过去或者目前为清华大学信息化技术中心工作；
- 您的项目受到任何与清华大学有关的机构的经济资助。

如果上述任意条件成立，任何未经授权的对本项目中代码的使用将会被认为是侵权。上文中的“使用”包括对项目的源代码或衍生品制作拷贝、修改、重新分发，无论是否用作商业用途。

本项目中使用的开源项目则应用其自带的许可证。

## ICP 备案 ICP Filing

[京ICP备2026001019号-1A](https://beian.miit.gov.cn/)
