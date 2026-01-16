## 如何调试
用 VS Code 打开项目目录，用 DevEco Studio 打开 `hamony` 文件夹。在项目目录中中执行

```
npm i
npm run codegen
```

在 DevEco Studio 中点击右上角的 `sync` 按钮，并在文件-项目结构中配置好 Signing Configs。连接到鸿蒙手机或平板。回到 VS Code，在项目目录中执行


```
hdc rport tcp:8081 tcp:8081
npm run start
```

在 DevEco Studio 中点击运行按钮，在鸿蒙设备上弹出窗口后，回到 VS Code，在之前执行 `npm run start` 的同一终端中按 r 重新加载项目。