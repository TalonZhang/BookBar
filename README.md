# BookBar

BookBar 是一个 macOS 菜单栏电子书阅读器。点菜单栏的小书开始阅读，点弹窗外收起，下次接着读。

## 安装

从 [GitHub Releases](https://github.com/TalonZhang/BookBar/releases) 下载 `BookBar-macOS.zip`，解压后把 `BookBar.app` 拖到「应用程序」，双击打开，再点击菜单栏的小书图标。支持 macOS 13 或更新版本，兼容 Apple 芯片和 Intel Mac。

试用版采用临时签名，尚未经过 Apple 公证。首次启动时 macOS 可能拦截。请先确认压缩包来自本仓库，再参考 [Apple 的首次打开说明](https://support.apple.com/zh-cn/102445)。

## 阅读

- 书架支持批量导入 EPUB、TXT 和 PDF。按最近阅读排序，可点击顶部书名切换。
- 点击底部进度打开目录或跳转 PDF 页码。应用会保存每本书的阅读位置。
- 右上角可调字号、行距、配色和弹窗尺寸。半透配色会模糊背景，PDF 书页保留原版底色。
- 弹窗内可用 ⌘B 打开书架，⌘O 导入，⌘, 打开设置，⌘← / ⌘→ 切换章节或页码，⌘+ / ⌘− 调整字号。Esc 逐层返回。
- 书籍副本和阅读记录保存在本机。首次使用可直接打开内置试读。密码或 DRM 保护的书无法导入。

## 从源码构建

安装包含 Swift 6 或更新版本的 Xcode 命令行工具，然后在项目目录运行：

```sh
./scripts/build-app.sh
open "dist/BookBar.app"
```

用 `./scripts/build-app.sh --universal` 构建 Apple 芯片与 Intel 通用包。应用使用 AppKit、SwiftUI、WebKit、PDFKit 和系统 zlib，无第三方依赖。

## 许可证

[MIT](LICENSE)
