# CineVault

CineVault 是一款基于 Flutter 的桌面影片库管理应用，用于整理本地影片、同步 TMDB 资料、管理播放进度，并通过可配置的 AI 服务辅助归类。

## 功能

- 通过 TMDB 搜索影片，导入标题、简介、上映日期、片长、类型、导演、制作公司、发行公司、系列、演员、剧照和相关影片。
- 本地影片库支持收藏、播放记录、自定义标签、导入导出和批量资料更新。
- 竖版影片卡片使用 TMDB 海报；详情页优先展示 TMDB 横版海报，并在标题区、顶部预览和资料刷新流程中保持一致。
- 扫描本地视频文件，按 TMDB ID 或标题匹配影片条目。
- 内置桌面播放器，支持本地字幕管理。
- AI 设置支持填写远程大模型 API，无需下载本地模型即可使用翻译和影片标签分类能力。

## TMDB 配置

在设置页打开 `TMDB 配置`，填写以下任意一种凭据：

- TMDB Read Access Token
- TMDB API Key

默认接口地址：

```text
https://api.themoviedb.org/3
```

## 开发

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Dart 包名为 `cine_vault`，应用显示名称为 `CineVault`。
