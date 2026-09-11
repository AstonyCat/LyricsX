# 歌词四层独立显示与字号控制

## 目标

让歌词的四个层级 —— 日文注音（振假名）、日语原文、罗马音、翻译 —— 各自拥有独立的显示开关与字号设置。桌面卡拉OK歌词与歌词窗口两套界面完全独立配置。

同时为歌词窗口补上注音与罗马音渲染（目前完全没有），并修掉歌词窗口只显示中文翻译的限制。

## 现状

| 层 | 桌面卡拉OK歌词 | 歌词窗口 |
|---|---|---|
| 注音 | `CTRubyAnnotation`，倍数硬编码 `0.5` | 不存在 |
| 原文 | 可配字号 `DesktopLyricsFontSize` | 可配字号 `LyricsWindowFontSize` |
| 罗马音 | 手动绘制，倍数硬编码 `0.3` | 不存在 |
| 翻译 | 第二个 `KaraokeLabel`，与原文共用字体 | 拼进同一字符串，与原文共用字体 |

两边渲染机制不同，这是设计的主要约束：

- 桌面歌词：`KaraokeLabel` 继承 `NSTextField`，但 `draw(_:)` 完全自绘 —— 走 Core Text（`CTFrameDraw`），罗马音再叠一层 `CTLineDraw`。加参数很直接。
- 歌词窗口：`ScrollLyricsView` 包一个 `NSTextView`，所有歌词拼成一个大字符串，整段套一个 font。`ranges: [(TimeInterval, NSRange)]` 这张表供高亮、滚动定位、双击跳转三处使用。

另外两处既有行为：

- `ScrollLyricsView.swift:69` 的 `languageCode?.hasPrefix("zh") == true` 让非中文翻译在歌词窗口里不显示。
- `PreferBilingualLyrics` 是当前唯一的翻译开关，两个界面共用，默认值按系统语言是否中文决定（`AppDelegate.swift:275`）。

## 设置模型

每个界面 8 项设置：4 个显示开关 + 4 个字号（绝对 pt）。两个界面共 16 项。

其中原文字号复用既有键（桌面 `DesktopLyricsFontSize`、窗口 `LyricsWindowFontSize`），所以新增的键是 14 个。

```
// 桌面卡拉OK歌词
DesktopLyricsShowFurigana      Bool   ← 迁移自 DesktopLyricsEnableFurigana
DesktopLyricsShowOriginal      Bool   true
DesktopLyricsShowRomaji        Bool   ← 迁移自 DesktopLyricsEnableRomajin
DesktopLyricsShowTranslation   Bool   ← 迁移自 PreferBilingualLyrics
DesktopLyricsFuriganaFontSize  Int    12
DesktopLyricsRomajiFontSize    Int    8
DesktopLyricsTranslationFontSize Int  19

// 歌词窗口
LyricsWindowShowFurigana       Bool   false
LyricsWindowShowOriginal       Bool   true
LyricsWindowShowRomaji         Bool   false
LyricsWindowShowTranslation    Bool   ← 迁移自 PreferBilingualLyrics
LyricsWindowFuriganaFontSize   Int    9
LyricsWindowRomajiFontSize     Int    7
LyricsWindowTranslationFontSize Int   11
```

字号取值范围 6–120 pt，超出时钳制。

顺带修一个既有的类型不一致：`LyricsWindowFontSize` 在 `UserDefaults.plist` 里注册成 `<string>13</string>`，但 `Global.swift` 声明是 `Key<Int>`。新键统一注册为 `<integer>`，这个旧键也改成 `<integer>13</integer>`。

### 旧键迁移

`UserDefaultsMigrator` 已有一次性迁移的模式（`Migration.SandboxToNonSandbox.v1`），沿用同样的写法加 `Migration.LyricsLayerSettings.v1`：

- `DesktopLyricsEnableFurigana` → `DesktopLyricsShowFurigana`
- `DesktopLyricsEnableRomajin` → `DesktopLyricsShowRomaji`
- `PreferBilingualLyrics` → `DesktopLyricsShowTranslation` + `LyricsWindowShowTranslation`

`PreferBilingualLyrics` 拆成两个键后不再被读取，连同两个旧的 Enable 键一起从 `Global.swift`、`UserDefaults.plist` 和 storyboard 里删掉。迁移只在旧键有显式值时覆盖新键的默认值。

`DesktopLyricsOneLineMode` 保持不变。它与四层开关是不同维度的东西（控制第二行显示翻译还是下一句歌词），不参与本次改动。

## 桌面卡拉OK歌词

`KaraokeLabel` 三个新属性，全部 `@objc dynamic` 以便走既有的 KVO 绑定链：

```swift
@objc dynamic var furiganaFontSize: CGFloat = 12
@objc dynamic var romajiFontSize: CGFloat = 8
@objc dynamic var drawOriginal = true
```

注音的绝对 pt 在渲染时换算成倍数，因为 `CTRubyAnnotation` 只接受 `ctRubySizeFactor`：

```swift
// KaraokeLabel.swift:84
let factor = furiganaFontSize / (font?.pointSize ?? 24)
var attr: [CFAttributedString.Key: Any] = [.ctRubySizeFactor: factor]
```

罗马音把 `drawRomajiAnnotations` 里硬编码的 `fontSize * 0.3` 换成 `romajiFontSize`（`KaraokeLabel.swift:343`）。既有的「太宽就按 0.9 逐步缩小」逻辑保留 —— 那是防止罗马音超出汉字宽度，与字号设置不冲突。

翻译作为独立 label，需要与原文不同的字号。`KaraokeLyricsView.lyricsLabel` 现在把 `font` 无条件绑到所有 label 上（`KaraokeLyricsView.swift:79`），改成按角色取字号：翻译行用 `translationFont`，其余用 `font`。`updateFontSize()` 里的间距与圆角继续按原文字号算。

### 隐藏原文

原文隐藏时，注音失去宿主 —— ruby 注释是挂在原文字符上的，原文不画注音也就没有了。这是选择「原文可隐藏」时接受的语义。罗马音则改为独立成行绘制：`attrString` 用罗马音文本替代原文文本，`drawRomajiAnnotations` 跳过。

卡拉OK进度动画（`setProgressAnimation`）依赖原文的 `CTLine` 几何。原文隐藏时进度条无处可画，跳过动画调用（`KaraokeLyricsController.swift:153`）。

## 歌词窗口

每句歌词从最多 2 行变成最多 4 行，每行一个字号。注音整行排布，不逐字对齐到汉字上方 —— `NSTextView` 做不到精确 ruby 对齐，而为此把整个视图改成 Core Text 自绘会牵连高亮、滚动、双击定位、渐变遮罩四处逻辑，不值得。

```
  たか      まど        ← 注音行
  高いあの窓で          ← 原文
  takai ano mado de    ← 罗马音
  在那高处的窗边         ← 翻译
```

注音行与罗马音行的文本用 `CFExtension.swift` 里既有的 `currentFuriganaAnnotation` / `currentRomanjiAnnotation` 生成。这两个方法操作 `NSString`、与渲染无关，可以直接复用。注音行按 token 位置插空格粗略对位，罗马音行用空格连接。

### ranges 表

当前 `ranges` 每项是 `(行起始时间, 整句的 NSRange)`，`NSRange` 覆盖原文+翻译。四行之后仍是「一句一项，`NSRange` 覆盖该句所有可见行」，所以高亮、滚动、双击三处的逻辑不用改 —— 它们只关心「一句」的整体范围。

字号不再全局统一，所以 `updateFont()` 不能再对 `fullRange` 刷单一 font（`ScrollLyricsView.swift:213-217`）。改为在 `setupTextContents` 里逐行按角色 `addAttribute(.font:)`，并记录每行的角色与范围，供字号变化时重新应用。

### 翻译语种限制

删掉 `languageCode?.hasPrefix("zh") == true` 这个条件（`ScrollLyricsView.swift:69`）。中文转换（简繁）仍然只在 `languageCode` 是中文时执行，那是 `ChineseConverter` 的正确用法；非中文翻译直接原样显示。

## 偏好界面

四层控件集中到「显示」面板，每层一行：复选框 + 字号 `NSTextField`（`NSNumberFormatter`，6–120）。桌面歌词与歌词窗口各一组。

```
桌面歌词
  [✓] 注音      [12] pt
  [✓] 原文      [24] pt
  [✓] 罗马音    [ 8] pt
  [✓] 翻译      [19] pt

歌词窗口
  [ ] 注音      [ 9] pt
  [✓] 原文      [13] pt
  [ ] 罗马音    [ 7] pt
  [✓] 翻译      [11] pt
```

全部走 storyboard 的 `NSUserDefaultsController` 绑定（`values.<Key>`），与既有控件一致，`PreferenceDisplayViewController` 不需要新增 IBOutlet。原文字号与既有的 `FontSelectTextField` 共享同一个键，两处会互相反映。

「通用」面板里现有的两个注音/罗马音复选框（storyboard 第 1531、1544 行）删除，另有一处 `DesktopLyricsEnableFurigana` 绑定在第 2654 行，一并清理。

新增文案走 `Preferences.xcstrings`。

## 边界情况

- **非日语歌词**：注音与罗马音只在 `dominantLanguage == "ja"` 时生成，既有判断保留（`KaraokeLabel.swift:69-70`）。开关打开但歌词非日语时，这两行不出现。
- **无翻译**：翻译开关打开但该句没有 translation attachment 时，翻译行不出现，不留空行。
- **四层全关**：桌面歌词整体隐藏（走既有的 `shouldHideAll` 路径）；歌词窗口显示空内容。
- **注音/罗马音无结果**：某句提取不到假名或罗马字时（纯假名句、纯符号句）该行不出现。

## 测试

`LyricsXPackage` 有个空的 `LyricsXFoundationTests` 目标，但 Xcode scheme 未配置测试，跑不起来。四层渲染逻辑也都耦合在 `NSView` 子类里，单元测试需要先做一轮解耦 —— 超出本次范围。

验证方式：

1. `xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build` 通过。
2. `swiftlint` 无新增告警。
3. 手动验证：放一首日文歌（有翻译），逐个切换 8 个开关、调整 8 个字号，确认桌面歌词与歌词窗口各自独立生效；确认卡拉OK进度动画在原文显示时正常、隐藏时不崩；确认非中文翻译在歌词窗口里显示；确认从旧版本升级后原有的注音/罗马音/双语设置被正确迁移。

手动验证这条得由你来做 —— 我无法在这个环境里观察菜单栏应用的实际渲染效果。

## 改动文件

| 文件 | 改动 |
|---|---|
| `Utility/Global.swift` | 加 14 个键，删 3 个旧键 |
| `Supporting Files/UserDefaults.plist` | 注册默认值 |
| `Component/UserDefaultsMigrator.swift` | 加旧键迁移 |
| `View/KaraokeLabel.swift` | 注音/罗马音字号参数化，原文可隐藏 |
| `View/KaraokeLyricsView.swift` | 翻译行独立字号 |
| `Controller/KaraokeLyricsController.swift` | 绑定新键，进度动画条件 |
| `View/ScrollLyricsView.swift` | 四行渲染，逐行字号，删语种限制 |
| `LyricsHUD/LyricsHUDViewController.swift` | 绑定新键 |
| `Base.lproj/Preferences.storyboard` | 显示面板加控件，通用面板删旧控件 |
| `mul.lproj/Preferences.xcstrings` | 新增文案 |

