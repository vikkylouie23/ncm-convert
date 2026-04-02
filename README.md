# NCM 本地转换工具

一个轻量化的本地音频解锁与导出工具，提供浏览器版开发体验，并打包成原生 macOS 桌面应用。

这个项目的目标很明确：

- 保留在线站点那类“选文件后直接转换”的使用方式
- 避免引入 Electron 这类重量级桌面壳
- 把文件选择、保存、批量下载这些桌面端链路做稳
- 让仓库本身足够简单，方便继续改 UI 或加格式支持

## 功能

- 支持多选文件并顺序转换
- 支持结果试听
- 支持单个保存
- 支持下载全部
- 支持打包 ZIP
- 支持自定义 macOS app 图标
- 桌面端使用原生保存面板，避免 `WKWebView` 对 `blob:` 下载支持不稳定的问题

## 当前实现

前端部分：

- `Vite` 提供开发与构建
- 页面逻辑在 `src/main.js`
- 页面样式在 `src/styles.css`
- 核心解密逻辑来自本地化后的 `public/vendor/decrypt.js`
- `public/static/kgm.mask` 用于兼容 KGM/VPR 相关流程

桌面端部分：

- 使用 `AppKit + WKWebView + Network` 自建原生 macOS 壳
- 不依赖 Electron
- 文件选择通过 `WKUIDelegate` 调起系统打开面板
- 文件保存通过本地 HTTP 接口转给原生壳，再调用 `NSSavePanel`
- 构建时会把 `.js`、`.css`、`.mask` 资源 gzip 压缩后再写进 app bundle，以减小最终体积

## 环境要求

开发 Web 版本：

- Node.js 18+
- npm

打包 macOS 桌面版：

- macOS 13+
- 系统自带 `swift`
- 系统自带 `swiftc`
- 系统自带 `sips`
- 系统自带 `iconutil`

## 快速开始

安装依赖：

```bash
npm install
```

启动开发服务器：

```bash
npm run dev
```

生产构建前端：

```bash
npm run build
```

构建 macOS 桌面 App：

```bash
npm run build:app
```

构建完成后会在 `release/` 目录下得到：

- `NCM Local Converter.app`
- `NCM Local Converter.app.zip`

## 可用脚本

| 命令 | 说明 |
| --- | --- |
| `npm run dev` | 启动本地开发服务器 |
| `npm run build` | 构建前端静态资源 |
| `npm run preview` | 本地预览构建产物 |
| `npm run build:web` | 等同于前端生产构建 |
| `npm run build:app` | 构建前端并打包原生 macOS App |

## 项目结构

```text
.
├── index.html
├── src/
│   ├── main.js
│   └── styles.css
├── public/
│   ├── vendor/
│   │   └── decrypt.js
│   └── static/
│       └── kgm.mask
├── native-macos/
│   ├── Info.plist
│   ├── LocalHTTPServer.swift
│   └── main.swift
├── scripts/
│   ├── build-macos-app.sh
│   └── generate-app-icon.swift
├── package.json
└── vite.config.js
```

## 工作流程

### Web 端

1. 用户选择待处理文件
2. 前端按需加载 `decrypt.js`
3. 解密结果在页面中生成试听和结果卡片
4. 单个下载、下载全部、ZIP 导出都复用统一保存逻辑

### macOS 桌面端

1. 原生壳启动本地 HTTP 服务
2. `WKWebView` 加载内置前端资源
3. 页面中的文件选择请求由 `WKUIDelegate` 转成系统打开面板
4. 页面中的保存请求通过 `POST /__save__` 发送给本地壳
5. 原生壳弹出 `NSSavePanel` 并把文件写到用户选择的位置

## 轻量化策略

- 用原生 `AppKit + WKWebView` 替换 Electron
- `decrypt.js` 改成按需加载，降低首屏解析成本
- ZIP 功能使用动态导入 `JSZip`
- 对音频这类本身已压缩内容，ZIP 默认使用 `STORE`，避免无意义二次压缩
- 构建时压缩包内静态资源，减小 `.app` 体积
- 清理旧的 Electron 发布目录，避免误判项目体积

## 已知说明

- 输出格式取决于原始音频，工具不会强制二次转码成 MP3
- 某些格式在上游解密逻辑中仍然是整文件处理，所以超大文件或超大批量任务时，内存峰值仍然主要取决于 `decrypt.js`
- ZIP 导出最终仍会在内存里生成一个 ZIP Blob，极大批量文件时内存占用会升高
- 当前桌面端打包脚本只覆盖 macOS
- 由于是未签名应用，首次打开时 macOS 可能会拦截；通常右键选择“打开”一次即可

## 常见问题

### 1. 点击 app 没反应或被系统拦截

这是未签名应用的正常现象。请在 Finder 中右键应用，选择“打开”。

### 2. 桌面端为什么不用浏览器默认下载

`WKWebView` 对 `blob:` 链接下载和 `<a download>` 的行为不够稳定，尤其是桌面壳场景。当前实现改为由原生壳统一弹保存面板，兼容性更高。

### 3. 为什么不直接用 Electron

这个项目主要是一个本地工具，桌面壳只需要：

- 打开前端页面
- 调起文件选择
- 调起文件保存

原生 `AppKit + WKWebView` 已经足够，包体也明显更小。

### 4. 支持哪些格式

当前接入的格式范围以 `decrypt.js` 和页面 `accept` 配置为准，覆盖常见的：

- `ncm`
- `uc`
- `qmc*`
- `kgm`
- `vpr`
- 以及部分相关变体格式

## 后续可继续改进的方向

- 增加真实样本文件的回归测试
- 增加转换完成后的批量保存目录模式
- 增加“自动清理已导出结果”选项，进一步降低长时间运行时的内存占用
- 增加更明确的错误提示和格式兼容说明

## License

当前仓库未单独附加开源许可证。若你准备公开分发，建议补充适合的 License，并确认第三方解密脚本的使用边界。
