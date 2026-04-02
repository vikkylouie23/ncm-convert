# NCM 本地转换工具

这是一个轻量化的本地转换工具：

- 支持多选、试听、单个下载、全部下载、ZIP 打包
- macOS 桌面包使用原生 `AppKit + WKWebView` 壳，而不是 Electron
- 解密引擎按需加载，桌面包里的大静态资源会在构建时压缩存储

## 启动

```bash
npm install
npm run dev
```

默认会启动一个本地开发服务器，终端里会显示访问地址。

## 构建桌面 App

```bash
npm install
npm run build:app
```

完成后会在 `release/` 下生成 macOS `.app`。

## 说明

- 结果格式取决于原始音频，不会强制二次转码成 MP3。
- 核心解密逻辑来自本地化后的 `public/vendor/decrypt.js`。
- `public/static/kgm.mask` 也已本地化，便于兼容 KGM/VPR 相关流程。
