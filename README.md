# Flux Translator

一个基于 Flutter 开发的 Windows 中英双向翻译工具，适合通过全局快捷键快速打开并完成短文本翻译。

## 功能

- 中英文自动识别并切换翻译方向。
- 支持全局快捷键唤起窗口，快捷键可在设置中自定义。
- 输入框按 `Enter` 立即翻译。
- 单词采用词典式结果：显示词性和常见释义；多个词性分行显示。
- 句子和短语采用普通上下文翻译，不附加词性。
- 支持 OpenAI 兼容 API，可配置 API Key、模型和 Chat Completions 地址。
- 可从配置的 API 地址读取模型列表并选择模型。
- 内置少量离线短语词典；完整句子建议使用 AI 服务。
- 支持系统、浅色和深色主题，以及半透明浮动窗口外观。
- 翻译结果可一键复制；网络或 API 出错时可直接重试。

## 运行环境

- Windows 10 或 Windows 11
- Flutter SDK
- Visual Studio 2022 或更新版本，并安装“使用 C++ 的桌面开发”工作负载和 Windows SDK

检查环境：

```powershell
flutter doctor
```

## 运行

在项目目录执行：

```powershell
flutter pub get
flutter run -d windows
```

## 构建发布版

```powershell
flutter build windows --release
```

生成的程序位于：

```text
build\windows\x64\runner\Release\quick_translate.exe
```

## AI 翻译设置

1. 在应用中打开“设置”。
2. 填写 OpenAI 兼容 API Key。
3. 填写 Chat Completions 地址，例如：

   ```text
   https://api.openai.com/v1/chat/completions
   ```

4. 点击“加载模型”，然后在列表中选择模型；也可以手动填写模型名称。
5. 在主界面的翻译服务选择器中选择“AI provider”。

模型列表功能会将常规的 `/chat/completions` 地址转换为 `/models` 地址，并使用当前 API Key 获取可用模型。

## 快捷键

默认快捷键为 `Ctrl + Alt + T`。在设置页点击“Global shortcut”控件后按下新的组合键即可保存并立即生效。快捷键只能在程序仍在运行时唤起或恢复窗口；程序完全退出后需要先重新启动。
