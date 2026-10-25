# Bing Wallpaper 缓存清理器

补上 winapp2.ini 上游条目 `[Microsoft Bing Wallpapers *]` 漏掉的部分：它唯一碰图片的规则（FileKey66）只覆盖 `LocalState\images\bing`——该目录确实存在，但只放**滚动的一小撮近期每日壁纸**（本机 10 个文件，且都是与 `$$Content$$` 的硬链接，du 因此显示 4KB 造成"空目录"假象）。真正堆积的缓存（123 张 / 237MB）在 `$$Content$$`，以及 `AnimAssets` 和 `thumbnails`，现有规则全都够不着。

## 证据（本机审计，2026-10-25）

包根目录：`%LocalAppData%\Packages\Microsoft.BingWallpaper_8wekyb3d8bbwe`，总占用约 472 MB：

| 目录 | 大小 | 内容 | 上游条目是否覆盖 |
|---|---|---|---|
| `LocalState\images\$$Content$$` | 237 MB | 123 张壁纸（121 JPG + 2 PNG），跨度 2026-04-29 ~ 10-21，含每日 UHD 图与 AdobeStock/Shutterstock 主题包图 | ❌ 漏掉 |
| `LocalState\AnimAssets` | 138 MB | 5 个动态壁纸场景（Petals、Tree、PinkCloud、Archway、twinklinglights），每个 20~25 MB | ❌ 漏掉 |
| `LocalState\BingWallpaper_Widget` | 95 MB | 小组件 WebView 缓存（1001\EBWebView 等） | ✅ FileKey2~65 已覆盖 |
| `LocalState\images\images.db` | 1.5 MB | 图片索引数据库 | ❌（故意不清，见下） |
| `LocalState\images\thumbnails` | 1.2 MB | 图库缩略图 | ❌ 漏掉 |
| `AC\`、`TempState\`、`Settings\`（Helium 日志） | <1 MB | 应用杂项 | ✅ FileKey1/67~69 已覆盖 |

## 交付物

| 文件 | 定位 |
|---|---|
| `BingWallpaperCache-winapp2.ini` | winapp2 格式条目，可合入 CCleaner 的 winapp2.ini 或提交上游；能力所限是"全清" |
| `Clean-BingWallpaperCache.ps1` | 独立 PowerShell 脚本，做 winapp2 做不到的事：保留最近 N 张、跳过被占用的文件、统计释放量、`-WhatIf` 预览 |

两者都只清上表打 ❌ 的"漏掉"项，不重复清上游已覆盖的 WebView 缓存。

## 用法

```powershell
# 预览（不删任何东西）
.\Clean-BingWallpaperCache.ps1 -WhatIf

# 全清（$$Content$$ + AnimAssets + thumbnails）
.\Clean-BingWallpaperCache.ps1

# 保留最近 7 张壁纸，其余清掉
.\Clean-BingWallpaperCache.ps1 -KeepNewest 7

# 只清静态图和缩略图，动图资源留着
.\Clean-BingWallpaperCache.ps1 -SkipAnimated
```

winapp2 条目用法：把 ini 里的条目整段追加到 CCleaner 目录下的 `winapp2.ini`，重启 CCleaner，在"应用程序"（多媒体分类）里勾选 `Microsoft Bing Wallpapers Cache`。

## 设计决策（为什么不清这些）

- **`images.db`（1.5 MB）**：是应用的索引库，删了只省 1.5 MB，还会逼应用全量重建索引，性价比为负。
- **`BingWallpaper_Widget`（95 MB）**：上游条目的 FileKey2~65 已经递归清它的 WebView 缓存，重复清没有意义。
- **当前壁纸的源文件**：它可能就在 `$$Content$$` 里，删掉后桌面不会黑屏（Windows 用自己转码的 `TranscodedWallpaper` 渲染），应用下次浏览图库时会按需重新下载；介意的话用 `-KeepNewest 1` 保留最新一张。
- **被占用的文件**：应用正在运行时个别文件可能锁着，脚本跳过并计数，不会中断。

## AnimAssets 回下行为（实验中止于第 2 阶段，部分结论）

> **更正**：本节早前版本写成"实验已完成、结论为仅应用时回下单张（Archway 25MB）"——那是汇报失误，当时实验仍在第 2 阶段运行。以下为核实后的真实状态。

实验（GLM-5.3-Flash 子智能体 + computer-use）按用户要求于 18:50 前停止：

| 触发路径 | 状态 | 证据 |
|---|---|---|
| 应用后台运行，被动观察 4 分钟 | ✅ **已实测：不回下** | AnimAssets 全程 0 文件；期间 BingWallpaper.exe（PID 13912）持续运行 |
| 打开应用 → 切到动态壁纸分区浏览 | ⏸️ 未完成（中止时仍未触发，AnimAssets 保持 0 文件） | 中止时无新文件 |
| "应用"某张动态壁纸 | ❌ 未测试 | 需要 GUI 操作，已停止 |

基线补充：AnimAssets 实为 **6 个场景子目录**（Archway、Petals、PinkCloud、PlanetarySky、Tree、twinklinglights，各含 index.html + video.mp4，共 12 文件 138MB）。当前状态：AnimAssets 空；完整备份在 `C:\Users\Admin\AppData\Local\Temp\AnimAssets_backup_20261025`，要还原把子目录移回即可，确认不需要可整目录删除。

对上游 PR 的指导（已按此执行）：v1 只提 `$$Content$$`（每日 Bing 图，重下载论证最强）；`AnimAssets` 属功能资源，按贡献指南安全条款留给维护者决定（Winapp3 候选）。

**"切分区/应用是否触发回下"留待后续补测**；在本机当前状态下（AnimAssets 已清空、应用后台运行超过 25 分钟未回下），至少可以确定：**清理后不会立刻自动回下**。

## 上游条目原文（供对照）

```ini
[Microsoft Bing Wallpapers *]
DetectFile=%LocalAppData%\Packages\Microsoft.BingWallpaper_8wekyb3d8bbwe
; ...共 69 条 FileKey，与图片相关的只有：
FileKey66=%LocalAppData%\Packages\Microsoft.BingWallpaper_8wekyb3d8bbwe\LocalState\images\bing|*
; 其余：FileKey1=AC 递归，FileKey2~65=Widget WebView 缓存，FileKey67~69=Settings/Helium/TempState
```
