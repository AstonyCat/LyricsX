# 歌词四层独立显示与字号控制 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让歌词的四个层级（日文注音、日语原文、罗马音、翻译）在桌面卡拉OK歌词与歌词窗口两套界面上各自拥有独立的显示开关与绝对 pt 字号设置。

**Architecture:** 新增 14 个 UserDefaults 键（每界面 4 个开关 + 3 个新字号，原文字号复用既有键），通过既有的 KVO 绑定链（`bind(_:withDefaultName:)`）送进视图层。桌面歌词走 Core Text 自绘，注音的绝对 pt 在渲染时换算成 `ctRubySizeFactor`；歌词窗口把每句从最多 2 行扩成最多 4 行纯文本，逐行按角色设字体。旧键经 `UserDefaultsMigrator` 一次性迁移后删除。

**Tech Stack:** Swift 5（项目设置）/ AppKit / Core Text / GenericID（`UserDefaults.DefaultsKey`）/ SnapKit / Xcode storyboard 绑定 / swift-testing（`LyricsXFoundationTests`）

**Spec:** `docs/superpowers/specs/2026-09-11-lyrics-layer-controls-design.md`

## Global Constraints

- 平台 macOS 11+，语言 Swift 5（项目设置），不引入新依赖。
- SwiftLint `line_length: 150`；SwiftFormat 4 空格缩进、LF 换行。改完跑 `swiftlint` 不得有新增告警。
- 字号取值范围 6–120 pt，超出时钳制。
- 所有新增 UserDefaults 字号键在 `UserDefaults.plist` 中注册为 `<integer>`。
- 视图层新增的可绑定属性必须是 `@objc dynamic`，否则 KVO 绑定不生效。
- 新增界面文案走 `LyricsX/mul.lproj/Preferences.xcstrings`，不硬编码中文。
- 每个任务结束时 Debug 构建必须通过：
  `xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build`
- `DesktopLyricsOneLineMode` 语义不变，不参与本次改动。

---

## 文件结构

| 文件 | 责任 |
|---|---|
| `LyricsX/Utility/Global.swift` | 14 个新键声明，删 3 个旧键 |
| `LyricsX/Supporting Files/UserDefaults.plist` | 默认值注册 |
| `LyricsX/Component/UserDefaultsMigrator.swift` | 旧键一次性迁移 |
| `LyricsX/Utility/LyricsLayerFont.swift`（新建） | 四层字号读取与钳制，两界面各一组 |
| `LyricsX/Utility/CFExtension.swift` | 加整行注音/罗马音文本生成（歌词窗口用） |
| `LyricsX/View/KaraokeLabel.swift` | 注音/罗马音字号参数化，原文可隐藏 |
| `LyricsX/View/KaraokeLyricsView.swift` | 翻译行独立字号 |
| `LyricsX/Controller/KaraokeLyricsController.swift` | 绑定新键，进度动画条件 |
| `LyricsX/View/ScrollLyricsView.swift` | 四行渲染，逐行字号，删语种限制 |
| `LyricsX/LyricsHUD/LyricsHUDViewController.swift` | 绑定新键 |
| `LyricsX/Base.lproj/Preferences.storyboard` | 显示面板加控件，通用面板删旧控件 |
| `LyricsX/mul.lproj/Preferences.xcstrings` | 新增文案 |
| `LyricsXPackage/Tests/LyricsXFoundationTests/` | 纯逻辑单元测试（字号钳制、注音行生成） |

新建 `LyricsLayerFont.swift` 是因为字号读取+钳制逻辑会被 5 个调用点复用（两个视图、两个控制器、偏好面板），塞进 `Extension.swift` 会让那个文件继续膨胀。

### 可测与不可测

四层渲染耦合在 `NSView` 子类里，无法在包测试中实例化。但两块纯逻辑可以测，计划里为它们写真正的 TDD 循环：

1. 字号钳制（Task 2）—— 纯函数。
2. 歌词窗口的注音行/罗马音行文本生成（Task 7）—— 输入字符串，输出字符串。

这两块放进 `LyricsXFoundation` 包（无 AppKit 依赖），用 `swift test --package-path LyricsXPackage` 跑。其余任务用 `xcodebuild` 构建 + 手动验证清单收尾。

---

### Task 1: 字号钳制纯函数（TDD）

放进 `LyricsXFoundation` 包，因为它是本次唯一能被单元测试覆盖的数值逻辑，且被 5 个调用点复用。

**Files:**
- Create: `LyricsXPackage/Sources/LyricsXFoundation/LyricsLayerFontSize.swift`
- Test: `LyricsXPackage/Tests/LyricsXFoundationTests/LyricsLayerFontSizeTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `public func clampLyricsFontSize(_ value: Int) -> Double`，以及 `public let lyricsFontSizeRange: ClosedRange<Int>`（值为 `6...120`）。后续任务用它把 UserDefaults 里的 `Int` 转成绘制用的尺寸。

返回 `Double` 而非 `CGFloat`，因为包不依赖 CoreGraphics；调用方在 app 目标里用 `CGFloat(...)` 包一层。

- [ ] **Step 1: 写失败的测试**

创建 `LyricsXPackage/Tests/LyricsXFoundationTests/LyricsLayerFontSizeTests.swift`：

```swift
import Testing
@testable import LyricsXFoundation

@Test func clampKeepsValueInsideRange() {
    #expect(clampLyricsFontSize(24) == 24)
    #expect(clampLyricsFontSize(6) == 6)
    #expect(clampLyricsFontSize(120) == 120)
}

@Test func clampRaisesValuesBelowMinimum() {
    #expect(clampLyricsFontSize(5) == 6)
    #expect(clampLyricsFontSize(0) == 6)
    #expect(clampLyricsFontSize(-10) == 6)
}

@Test func clampLowersValuesAboveMaximum() {
    #expect(clampLyricsFontSize(121) == 120)
    #expect(clampLyricsFontSize(9999) == 120)
}

@Test func rangeMatchesSpec() {
    #expect(lyricsFontSizeRange == 6...120)
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --package-path LyricsXPackage`
Expected: FAIL，报 `cannot find 'clampLyricsFontSize' in scope`

- [ ] **Step 3: 写最小实现**

创建 `LyricsXPackage/Sources/LyricsXFoundation/LyricsLayerFontSize.swift`：

```swift
/// 歌词各层字号的合法区间（pt）。
public let lyricsFontSizeRange: ClosedRange<Int> = 6...120

/// 把 UserDefaults 里可能被手工改坏的字号钳制回合法区间。
public func clampLyricsFontSize(_ value: Int) -> Double {
    Double(min(max(value, lyricsFontSizeRange.lowerBound), lyricsFontSizeRange.upperBound))
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --package-path LyricsXPackage`
Expected: PASS，4 个测试全绿

- [ ] **Step 5: 提交**

```bash
git add LyricsXPackage/Sources/LyricsXFoundation/LyricsLayerFontSize.swift \
        LyricsXPackage/Tests/LyricsXFoundationTests/LyricsLayerFontSizeTests.swift
git commit -m "feat: add lyrics layer font size clamping"
```

---

### Task 2: 新增 UserDefaults 键与默认值

**Files:**
- Modify: `LyricsX/Utility/Global.swift:104-130`（Display 段内）
- Modify: `LyricsX/Supporting Files/UserDefaults.plist`

**Interfaces:**
- Consumes: 无
- Produces: 14 个 `UserDefaults.DefaultsKey`。后续任务通过 `defaults[.desktopLyricsShowFurigana]` 等读取，或用 `bind(_:withDefaultName:)` 绑定。名称与类型：

```
desktopLyricsShowFurigana        Key<Bool>   "DesktopLyricsShowFurigana"
desktopLyricsShowOriginal        Key<Bool>   "DesktopLyricsShowOriginal"
desktopLyricsShowRomaji          Key<Bool>   "DesktopLyricsShowRomaji"
desktopLyricsShowTranslation     Key<Bool>   "DesktopLyricsShowTranslation"
desktopLyricsFuriganaFontSize    Key<Int>    "DesktopLyricsFuriganaFontSize"
desktopLyricsRomajiFontSize      Key<Int>    "DesktopLyricsRomajiFontSize"
desktopLyricsTranslationFontSize Key<Int>    "DesktopLyricsTranslationFontSize"
lyricsWindowShowFurigana         Key<Bool>   "LyricsWindowShowFurigana"
lyricsWindowShowOriginal         Key<Bool>   "LyricsWindowShowOriginal"
lyricsWindowShowRomaji           Key<Bool>   "LyricsWindowShowRomaji"
lyricsWindowShowTranslation      Key<Bool>   "LyricsWindowShowTranslation"
lyricsWindowFuriganaFontSize     Key<Int>    "LyricsWindowFuriganaFontSize"
lyricsWindowRomajiFontSize       Key<Int>    "LyricsWindowRomajiFontSize"
lyricsWindowTranslationFontSize  Key<Int>    "LyricsWindowTranslationFontSize"
```

旧键 `desktopLyricsEnableFurigana` / `desktopLyricsEnableRomajin` / `preferBilingualLyrics` 本任务**保留不动** —— Task 3 的迁移代码要读它们，删除放在 Task 11。

- [ ] **Step 1: 加新键声明**

在 `LyricsX/Utility/Global.swift` 的 `desktopLyricsEnableRomajin` 那一行之后插入。保持既有的分组空行风格：

```swift
    static let desktopLyricsShowFurigana = Key<Bool>("DesktopLyricsShowFurigana")
    static let desktopLyricsShowOriginal = Key<Bool>("DesktopLyricsShowOriginal")
    static let desktopLyricsShowRomaji = Key<Bool>("DesktopLyricsShowRomaji")
    static let desktopLyricsShowTranslation = Key<Bool>("DesktopLyricsShowTranslation")

    static let desktopLyricsFuriganaFontSize = Key<Int>("DesktopLyricsFuriganaFontSize")
    static let desktopLyricsRomajiFontSize = Key<Int>("DesktopLyricsRomajiFontSize")
    static let desktopLyricsTranslationFontSize = Key<Int>("DesktopLyricsTranslationFontSize")

    static let lyricsWindowShowFurigana = Key<Bool>("LyricsWindowShowFurigana")
    static let lyricsWindowShowOriginal = Key<Bool>("LyricsWindowShowOriginal")
    static let lyricsWindowShowRomaji = Key<Bool>("LyricsWindowShowRomaji")
    static let lyricsWindowShowTranslation = Key<Bool>("LyricsWindowShowTranslation")

    static let lyricsWindowFuriganaFontSize = Key<Int>("LyricsWindowFuriganaFontSize")
    static let lyricsWindowRomajiFontSize = Key<Int>("LyricsWindowRomajiFontSize")
    static let lyricsWindowTranslationFontSize = Key<Int>("LyricsWindowTranslationFontSize")
```

- [ ] **Step 2: 注册默认值**

在 `LyricsX/Supporting Files/UserDefaults.plist` 里加以下条目（该文件是按 key 字母序还是按功能分组不强制，插在 `DesktopLyricsEnableFurigana` 附近即可）。注意 `LyricsWindowFontSize` 原本是 `<string>13</string>`，本步顺带改成 `<integer>13</integer>`：

```xml
	<key>DesktopLyricsShowFurigana</key>
	<false/>
	<key>DesktopLyricsShowOriginal</key>
	<true/>
	<key>DesktopLyricsShowRomaji</key>
	<false/>
	<key>DesktopLyricsShowTranslation</key>
	<true/>
	<key>DesktopLyricsFuriganaFontSize</key>
	<integer>12</integer>
	<key>DesktopLyricsRomajiFontSize</key>
	<integer>8</integer>
	<key>DesktopLyricsTranslationFontSize</key>
	<integer>19</integer>
	<key>LyricsWindowShowFurigana</key>
	<false/>
	<key>LyricsWindowShowOriginal</key>
	<true/>
	<key>LyricsWindowShowRomaji</key>
	<false/>
	<key>LyricsWindowShowTranslation</key>
	<true/>
	<key>LyricsWindowFuriganaFontSize</key>
	<integer>9</integer>
	<key>LyricsWindowRomajiFontSize</key>
	<integer>7</integer>
	<key>LyricsWindowTranslationFontSize</key>
	<integer>11</integer>
```

`DesktopLyricsShowTranslation` 与 `LyricsWindowShowTranslation` 在 plist 里注册为 `true`，但 `AppDelegate.registerUserDefaults()` 里的 `.preferBilingualLyrics: isZh` 那行保持不动（Task 11 才删）。二者不冲突：plist 先注册，代码里的 `register(defaults:)` 覆盖的是另一个键。

- [ ] **Step 3: 验证 plist 语法与构建**

```bash
plutil -lint "LyricsX/Supporting Files/UserDefaults.plist"
xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build 2>&1 | tail -5
```

Expected: `OK`，且构建输出含 `** BUILD SUCCEEDED **`

- [ ] **Step 4: 提交**

```bash
git add LyricsX/Utility/Global.swift "LyricsX/Supporting Files/UserDefaults.plist"
git commit -m "feat: add per-layer lyrics visibility and font size defaults keys"
```

---

### Task 3: 旧键迁移

**Files:**
- Modify: `LyricsX/Component/UserDefaultsMigrator.swift`（在 `migrateFromSandboxIfNeeded()` 之后加新方法）
- Modify: `LyricsX/Component/AppDelegate.swift:33` 附近（调用新方法）

**Interfaces:**
- Consumes: Task 2 的 14 个键
- Produces: `func migrateLyricsLayerSettingsIfNeeded()`，由 `AppDelegate.applicationDidFinishLaunching` 在 `registerUserDefaults()` **之后**调用。

调用顺序很关键：迁移要读旧键的**显式值**，而 `registerUserDefaults()` 只是注册默认值（不写入用户域），所以先后都不影响 `object(forKey:)` 返回 nil 的判断。但迁移**写入**新键必须在 `registerUserDefaults()` 之后不成立 —— 注册的默认值不会覆盖已写入的用户值，所以两种顺序都安全。为可读性统一放在 `registerUserDefaults()` 之后。

- [ ] **Step 1: 加迁移方法**

在 `UserDefaultsMigrator.swift` 的 `migrateFromSandboxIfNeeded()` 方法之后插入。`migrationCompletionKey` 已存在，再加一个常量：

```swift
    private static let layerSettingsCompletionKey = "Migration.LyricsLayerSettings.v1"

    /// 把旧的单开关设置迁到分层设置。旧键只在用户显式设过时才有值，
    /// 没设过就让新键保持 plist 注册的默认值。
    func migrateLyricsLayerSettingsIfNeeded() {
        guard !userDefaults.bool(forKey: Self.layerSettingsCompletionKey) else { return }

        let moves: [(old: String, new: [String])] = [
            ("DesktopLyricsEnableFurigana", ["DesktopLyricsShowFurigana"]),
            ("DesktopLyricsEnableRomajin", ["DesktopLyricsShowRomaji"]),
            ("PreferBilingualLyrics", ["DesktopLyricsShowTranslation", "LyricsWindowShowTranslation"]),
        ]

        var migratedCount = 0
        for (old, newKeys) in moves {
            guard let value = userDefaults.object(forKey: old) as? Bool else { continue }
            for newKey in newKeys {
                userDefaults.set(value, forKey: newKey)
                migratedCount += 1
            }
        }

        userDefaults.set(true, forKey: Self.layerSettingsCompletionKey)
        #log(.info, "Migrated \(migratedCount, privacy: .public) lyrics layer settings from legacy keys")
    }
```

用字符串字面量而不是 `DefaultsKey`，因为旧键在 Task 11 会从 `Global.swift` 删掉，迁移代码得在那之后仍然编译得过。

- [ ] **Step 2: 在启动流程里调用**

`AppDelegate.swift` 第 33 行是 `registerUserDefaults()`。在它下一行加：

```swift
        UserDefaultsMigrator.shared.migrateLyricsLayerSettingsIfNeeded()
```

- [ ] **Step 3: 构建**

Run: `xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 手动验证迁移**

模拟一个「老用户」：写入旧键，清掉完成标记与新键，然后启动 app 检查新键是否被写对。

```bash
# 造旧状态
defaults write com.JH.LyricsX DesktopLyricsEnableFurigana -bool true
defaults write com.JH.LyricsX DesktopLyricsEnableRomajin -bool true
defaults write com.JH.LyricsX PreferBilingualLyrics -bool false
defaults delete com.JH.LyricsX Migration.LyricsLayerSettings.v1 2>/dev/null
defaults delete com.JH.LyricsX DesktopLyricsShowFurigana 2>/dev/null
defaults delete com.JH.LyricsX DesktopLyricsShowTranslation 2>/dev/null
defaults delete com.JH.LyricsX LyricsWindowShowTranslation 2>/dev/null
```

启动 Debug 构建产物一次后退出，然后：

```bash
defaults read com.JH.LyricsX DesktopLyricsShowFurigana      # 期望 1
defaults read com.JH.LyricsX DesktopLyricsShowRomaji        # 期望 1
defaults read com.JH.LyricsX DesktopLyricsShowTranslation   # 期望 0
defaults read com.JH.LyricsX LyricsWindowShowTranslation    # 期望 0
defaults read com.JH.LyricsX Migration.LyricsLayerSettings.v1  # 期望 1
```

再启动一次，确认不会重复迁移（把 `DesktopLyricsShowFurigana` 改成 0 后重启，应保持 0）。

- [ ] **Step 5: 提交**

```bash
git add LyricsX/Component/UserDefaultsMigrator.swift LyricsX/Component/AppDelegate.swift
git commit -m "feat: migrate legacy furigana/romaji/bilingual settings to per-layer keys"
```

---

### Task 4: 四层字号读取入口

把「读键 → 钳制 → 造 NSFont」收在一处，供两个视图、两个控制器、偏好面板共用。

**Files:**
- Create: `LyricsX/Utility/LyricsLayerFont.swift`
- Modify: `LyricsX.xcodeproj/project.pbxproj`（新文件加入 LyricsX target）

**Interfaces:**
- Consumes: Task 1 的 `clampLyricsFontSize(_:)`；Task 2 的字号键；既有的 `defaults.desktopLyricsFont` / `defaults.lyricsWindowFont`（`Utility/Extension.swift:70-85`）
- Produces: `UserDefaults` 上 6 个计算属性，全部返回已钳制的 `CGFloat`：

```
desktopFuriganaSize, desktopRomajiSize, desktopTranslationSize
windowFuriganaSize, windowRomajiSize, windowTranslationSize
```

外加一个造字体的方法 `desktopLyricsFont(size:) -> NSFont`，复用既有字体名与 fallback 设置、只换字号 —— Task 8 用它给桌面歌词的翻译行造字体。

歌词窗口不需要对应方法：`ScrollLyricsView` 内部已持有 `fontName`，Task 10 在那里直接 `NSFont(name:size:)`。

属性名故意不与 `DefaultsKey` 同名（键叫 `desktopLyricsFuriganaFontSize`，属性叫 `desktopFuriganaSize`），避免 `self[.x]` 与 `self.x` 在同一 extension 里混淆。

`func desktopLyricsFont(size:)` 与既有的 `var desktopLyricsFont`（`Utility/Extension.swift:70`）同名 —— Swift 允许属性与方法同名，调用处靠有无参数区分，不会冲突。`NSFont(name:size:fallback:)` 是既有的便利构造器（`Utility/Extension.swift:59`），不需要新写。

- [ ] **Step 1: 创建文件**

```swift
import AppKit
import LyricsXFoundation

/// 歌词各层的字号读取。所有值都经过 `clampLyricsFontSize` 钳制，
/// 因为 UserDefaults 可能被 `defaults write` 改成越界值。
extension UserDefaults {
    var desktopFuriganaSize: CGFloat { CGFloat(clampLyricsFontSize(self[.desktopLyricsFuriganaFontSize])) }
    var desktopRomajiSize: CGFloat { CGFloat(clampLyricsFontSize(self[.desktopLyricsRomajiFontSize])) }
    var desktopTranslationSize: CGFloat { CGFloat(clampLyricsFontSize(self[.desktopLyricsTranslationFontSize])) }

    var windowFuriganaSize: CGFloat { CGFloat(clampLyricsFontSize(self[.lyricsWindowFuriganaFontSize])) }
    var windowRomajiSize: CGFloat { CGFloat(clampLyricsFontSize(self[.lyricsWindowRomajiFontSize])) }
    var windowTranslationSize: CGFloat { CGFloat(clampLyricsFontSize(self[.lyricsWindowTranslationFontSize])) }

    /// 桌面歌词字体，沿用既有字体名与 fallback，只替换字号。
    func desktopLyricsFont(size: CGFloat) -> NSFont {
        NSFont(
            name: self[.desktopLyricsFontName],
            size: size,
            fallback: self[.desktopLyricsFontNameFallback]
        ) ?? .systemFont(ofSize: size)
    }
}
```

- [ ] **Step 2: 把文件加入 target**

用 Xcode 打开项目、拖入文件是最稳的做法（`project.pbxproj` 手改容易写坏）。若在无 GUI 环境，用 `ruby -e` 配合 `xcodeproj` gem，或直接在 Xcode 里 File → Add Files to "LyricsX"。

确认方式：`grep -c LyricsLayerFont LyricsX.xcodeproj/project.pbxproj` 应 ≥ 2（一条 PBXBuildFile、一条 PBXFileReference）。

- [ ] **Step 3: 构建**

Run: `xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

若报 `cannot find 'clampLyricsFontSize' in scope`，说明 `LyricsXFoundation` 没把新符号导出 —— 检查 Task 1 的文件是否放在 `Sources/LyricsXFoundation/` 下且声明为 `public`。

- [ ] **Step 4: 提交**

```bash
git add LyricsX/Utility/LyricsLayerFont.swift LyricsX.xcodeproj/project.pbxproj
git commit -m "feat: add per-layer lyrics font size accessors"
```

---

### Task 5: KaraokeLabel 注音与罗马音字号参数化

**Files:**
- Modify: `LyricsX/View/KaraokeLabel.swift:14-26`（加属性）、`:84`（注音倍数）、`:284`、`:343`（罗马音字号）

**Interfaces:**
- Consumes: 无（属性由 Task 6 的 `KaraokeLyricsView` 绑定进来）
- Produces: `KaraokeLabel` 上两个新的 `@objc dynamic var furiganaFontSize: CGFloat` 与 `romajiFontSize: CGFloat`，单位是绝对 pt。Task 6 绑定它们。

注音必须换算成倍数，因为 `CTRubyAnnotation` 只接受 `ctRubySizeFactor`（相对值），没有绝对字号入口。

- [ ] **Step 1: 加两个属性**

在 `drawRomajin` 属性（第 21-26 行）之后插入。两者都要 `clearCache()`，因为改字号必须重新排版：

```swift
    @objc dynamic var furiganaFontSize: CGFloat = 12 {
        didSet {
            clearCache()
            invalidateIntrinsicContentSize()
        }
    }

    @objc dynamic var romajiFontSize: CGFloat = 8 {
        didSet {
            clearCache()
            invalidateIntrinsicContentSize()
        }
    }
```

- [ ] **Step 2: 注音倍数改为按绝对 pt 换算**

第 84 行现在是：

```swift
                var attr: [CFAttributedString.Key: Any] = [.ctRubySizeFactor: 0.5]
```

改成：

```swift
                let rubySizeFactor = furiganaFontSize / (font?.pointSize ?? 24)
                var attr: [CFAttributedString.Key: Any] = [.ctRubySizeFactor: rubySizeFactor]
```

- [ ] **Step 3: 罗马音字号改为绝对 pt**

第 284 行与第 343 行是同一段逻辑的两份拷贝（主循环 + 处理剩余 annotation 的收尾循环），两处都改。原文：

```swift
                        var rubyFontSize = fontSize * 0.3
```

改成：

```swift
                        var rubyFontSize = romajiFontSize
```

第 343 行缩进较浅，原文是：

```swift
                var rubyFontSize = fontSize * 0.3
```

改成：

```swift
                var rubyFontSize = romajiFontSize
```

两处的 `while rubyWidth > maxWidth * 0.8, rubyFontSize > 1` 自动缩小逻辑**保留** —— 那是防止罗马音超出汉字宽度导致重叠，与用户设定的字号不冲突（设太大时仍会被压回可容纳的宽度）。

第 309 行的 `y: glyphBounds.minY - fontSize * 0.2` 是罗马音的垂直偏移，按原文字号算是对的（决定罗马音离原文多远），不改。

- [ ] **Step 4: 构建**

Run: `xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
git add LyricsX/View/KaraokeLabel.swift
git commit -m "feat: parameterize furigana and romaji font sizes in KaraokeLabel"
```

---

### Task 6: KaraokeLabel 支持隐藏原文

隐藏原文时罗马音要顶上来单独成行。实现方式是替换 `attrString` 的文本内容：原文字符换成罗马音字符，然后走同一套 Core Text 排版。这样罗马音自然继承居中、阴影、竖排等既有行为，不需要另写一条绘制路径。

注音在这个模式下消失 —— ruby 注释挂在原文字符上，原文字符不在了，注释也就没有宿主。这是设计阶段确认过的语义。

**Files:**
- Modify: `LyricsX/View/KaraokeLabel.swift:14-26`（加属性）、`:63-96`（`attrString`）、`:251`（`drawRomajiAnnotations` 守卫）
- Modify: `LyricsX/View/KaraokeLyricsView.swift:137-139`（四层全关时整体隐藏）

**Interfaces:**
- Consumes: Task 5 的 `romajiFontSize`
- Produces: `KaraokeLabel` 上三个成员：
  - `@objc dynamic var drawOriginal: Bool`（默认 `true`），Task 7 绑定它
  - `var isDrawingRomajiInline: Bool`（只读，`!drawOriginal && drawRomajin`），Task 8 用它判断是否跳过进度动画
  - `var hasVisibleContent: Bool`（只读），本任务 Step 4 自用

- [ ] **Step 1: 加属性**

紧跟 Task 5 加的 `romajiFontSize` 之后：

```swift
    @objc dynamic var drawOriginal = true {
        didSet {
            clearCache()
            invalidateIntrinsicContentSize()
        }
    }

    /// 原文被隐藏且罗马音开启时，罗马音替代原文单独成行。
    /// 此模式下没有原文字形，卡拉OK进度动画无处可画。
    var isDrawingRomajiInline: Bool {
        !drawOriginal && drawRomajin
    }
```

- [ ] **Step 2: 改 attrString**

第 63-96 行整段替换。改动点：`shouldDrawFurigana` 多一个 `drawOriginal` 条件；原文隐藏时用罗马音文本重建字符串：

```swift
    private var attrString: NSAttributedString {
        if let attrString = _attrString {
            return attrString
        }
        let attrString = NSMutableAttributedString(attributedString: attributedStringValue)
        let string = attrString.string as NSString
        // 原文隐藏时注音失去宿主字形，只能一起消失。
        let shouldDrawFurigana = drawFurigana && drawOriginal && string.dominantLanguage == "ja"
        let shouldDrawRomajin = drawRomajin && string.dominantLanguage == "ja"
        let tokenizer = CFStringTokenizer.create(string: .from(string))
        romajinAnnotations = []
        for tokenType in IteratorSequence(tokenizer) where tokenType.contains(.isCJWordMask) {
            if isVertical, drawOriginal {
                let tokenRange = tokenizer.currentTokenRange()
                let attr: [NSAttributedString.Key: Any] = [
                    .verticalGlyphForm: true,
                    .baselineOffset: (font?.pointSize ?? 24) * 0.25,
                ]
                attrString.addAttributes(attr, range: tokenRange.asNS)
            }
            if shouldDrawRomajin, let (romajin, range) = tokenizer.currentRomanjiAnnotation(in: string) {
                romajinAnnotations.append((romajin as String, range))
            }
            guard shouldDrawFurigana else { continue }
            if let (furigana, range) = tokenizer.currentFuriganaAnnotation(in: string) {
                var attr: [CFAttributedString.Key: Any] = [.ctRubySizeFactor: furiganaFontSize / (font?.pointSize ?? 24)]
                attr[.ctForegroundColor] = textColor
                let annotation = CTRubyAnnotation.create(furigana, attributes: attr)
                attrString.addAttribute(.cf(.ctRubyAnnotation), value: annotation, range: range)
            }
        }
        let result: NSMutableAttributedString
        if drawOriginal {
            result = attrString
        } else if shouldDrawRomajin {
            // 罗马音顶替原文成行，沿用原文的字体名与颜色，只换字号。
            let romaji = romajinAnnotations.map(\.0).joined(separator: " ")
            let font = font.map { NSFontManager.shared.convert($0, toSize: romajiFontSize) }
                ?? .systemFont(ofSize: romajiFontSize)
            result = NSMutableAttributedString(string: romaji, attributes: [.font: font])
        } else {
            result = NSMutableAttributedString(string: "")
        }
        textColor?.do { result.addAttributes([.foregroundColor: $0], range: result.fullRange) }
        _attrString = result
        return result
    }
```

注意 `currentRomanjiAnnotation` 的调用被移到 `guard shouldDrawFurigana` **之前** —— 原代码里它在 guard 之后，意味着关掉注音时罗马音也收集不到。这是既有的 bug，本任务顺带修掉（原文显示模式下开罗马音、关注音，之前罗马音不出现）。

- [ ] **Step 3: 罗马音叠加绘制在内联模式下跳过**

第 251 行的守卫：

```swift
        guard drawRomajin, !romajinAnnotations.isEmpty else { return }
```

改成：

```swift
        // 内联模式下罗马音已经是正文，不需要再叠一层注释。
        guard drawRomajin, drawOriginal, !romajinAnnotations.isEmpty else { return }
```

- [ ] **Step 4: 桌面歌词四层全关时整体隐藏**

关掉原文又关掉罗马音时，`attrString` 是空串，但 `KaraokeLyricsView.displayLrc` 判断的是传入的 `firstLine`（非空），于是会留下一个空 label 和它的背景框。

给 `KaraokeLabel` 加一个供视图层查询的属性（紧跟 `isDrawingRomajiInline`）：

```swift
    /// 四层全关时没有任何可绘制内容，视图层据此整体隐藏。
    var hasVisibleContent: Bool {
        drawOriginal || (drawRomajin && !romajinAnnotations.isEmpty)
    }
```

`romajinAnnotations` 在 `attrString` 求值时才填充，所以读 `hasVisibleContent` 前必须先触发一次排版。`KaraokeLyricsView.displayLrc` 里的 `layoutSubtreeIfNeeded()`（第 136 行）已经保证了这点 —— 判断放在动画块之后。

在 `KaraokeLyricsView.displayLrc` 的 `completionHandler`（第 137-139 行）里，把原本只有 `self.mouseTest()` 的闭包改成：

```swift
        }, completionHandler: {
            if let line1 = self.displayLine1, !line1.hasVisibleContent, self.displayLine2 == nil {
                self.isHidden = true
            }
            self.mouseTest()
        })
```

只在「第一行无内容且没有翻译行」时整体隐藏 —— 翻译行还在的话仍要显示。

- [ ] **Step 5: 构建**

Run: `xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

`fullRange` 定义在 `Utility/StdExtension.swift:46-50` 的 `NSAttributedString` 扩展上，`NSMutableAttributedString` 继承可用。`.do {}` 来自 `Utility/Then.swift:13`。

- [ ] **Step 6: 提交**

```bash
git add LyricsX/View/KaraokeLabel.swift LyricsX/View/KaraokeLyricsView.swift
git commit -m "feat: support hiding original text in desktop lyrics"
```

---

### Task 7: KaraokeLyricsView 翻译行独立字号

现在 `lyricsLabel(_:)` 把 `font` 无条件绑到每个 label（`KaraokeLyricsView.swift:79`），所以两行必然同字号。改成按角色分配：第一行用 `font`，第二行是翻译时用 `translationFont`。

第二行也可能是「下一句歌词」（`DesktopLyricsOneLineMode` 关闭且无翻译时），那种情况仍用原文字号 —— 它是原文，不是翻译。所以 `displayLrc` 需要知道第二行的角色。

**Files:**
- Modify: `LyricsX/View/KaraokeLyricsView.swift:16-19`（属性）、`:70-88`（`lyricsLabel`）、`:90`（`displayLrc` 签名）、`:103`、`:109`（两处 `lyricsLabel` 调用）
- Modify: `LyricsX/Controller/KaraokeLyricsController.swift:152`（调用处传角色）

Task 6 已经改过 `displayLrc` 的 `completionHandler`，本任务改的是它的签名与内部两处 `lyricsLabel` 调用，互不重叠。按 Task 6 → Task 7 的顺序做，行号才对得上。

**Interfaces:**
- Consumes: Task 5、6 的 `KaraokeLabel` 属性
- Produces:
  - `KaraokeLyricsView` 新属性，全部 `@objc dynamic`：`drawOriginal: Bool`、`furiganaFontSize: CGFloat`、`romajiFontSize: CGFloat`、`translationFont: NSFont`
  - `displayLrc` 签名变为 `func displayLrc(_ firstLine: String, secondLine: String = "", secondLineIsTranslation: Bool = false)`。Task 8 的控制器按此调用。

- [ ] **Step 1: 加属性并透传给 label**

第 16-19 行现在是：

```swift
    @objc dynamic var drawFurigana = false
    @objc dynamic var drawRomajin = false

    @objc dynamic var font = NSFont.labelFont(ofSize: 24) { didSet { updateFontSize() } }
```

改成：

```swift
    @objc dynamic var drawFurigana = false
    @objc dynamic var drawRomajin = false
    @objc dynamic var drawOriginal = true
    @objc dynamic var furiganaFontSize: CGFloat = 12
    @objc dynamic var romajiFontSize: CGFloat = 8

    @objc dynamic var font = NSFont.labelFont(ofSize: 24) {
        didSet {
            updateFontSize()
            refreshLabelFonts()
        }
    }

    @objc dynamic var translationFont = NSFont.labelFont(ofSize: 19) {
        didSet { refreshLabelFonts() }
    }
```

`translationFont` 不触发 `updateFontSize()` —— 那个方法算的是容器内边距、间距、圆角，全部按原文字号来，翻译字号不参与。

`refreshLabelFonts()` 在 Step 2 里定义，作用是字号偏好变化时把在场的 label 按角色刷一遍。

- [ ] **Step 2: lyricsLabel 按角色设字体**

label 会在原文行与翻译行之间被回收复用，所以字体不能用绑定 —— 绑定建立后没法干净地按角色切换（同一 binding name 重绑需要先 `unbind`，项目里没有这个先例，容易踩 AppKit 的坑）。改成：label 记住自己的角色，字体由视图层显式赋值。

先给 `KaraokeLabel` 加一个非绑定的普通属性（放在 Task 6 加的 `isDrawingRomajiInline` 之后）：

```swift
    /// 该 label 当前承载的是翻译还是原文，决定用哪个字号。
    var isTranslationLine = false
```

然后第 70-88 行的 `lyricsLabel` 改成：

```swift
    private func lyricsLabel(_ content: String, isTranslation: Bool) -> KaraokeLabel {
        if let view = stackView.subviews.lazy.compactMap({ $0 as? KaraokeLabel }).first(where: { !stackView.arrangedSubviews.contains($0) }) {
            view.alphaValue = 0
            view.stringValue = content
            view.removeProgressAnimation()
            view.removeFromSuperview()
            view.isTranslationLine = isTranslation
            view.font = isTranslation ? translationFont : font
            return view
        }
        return KaraokeLabel(labelWithString: content).then {
            $0.isTranslationLine = isTranslation
            $0.font = isTranslation ? translationFont : font
            $0.bind(\.textColor, to: self, withKeyPath: \.textColor)
            $0.bind(\.progressColor, to: self, withKeyPath: \.progressColor)
            $0.bind(\._shadowColor, to: self, withKeyPath: \.shadowColor)
            $0.bind(\.isVertical, to: self, withKeyPath: \.isVertical)
            $0.bind(\.drawFurigana, to: self, withKeyPath: \.drawFurigana)
            $0.bind(\.drawRomajin, to: self, withKeyPath: \.drawRomajin)
            $0.bind(\.drawOriginal, to: self, withKeyPath: \.drawOriginal)
            $0.bind(\.furiganaFontSize, to: self, withKeyPath: \.furiganaFontSize)
            $0.bind(\.romajiFontSize, to: self, withKeyPath: \.romajiFontSize)
            $0.alphaValue = 0
        }
    }
```

原来第 79 行的 `$0.bind(\.font, to: self, withKeyPath: \.font)` 被删掉，改为显式赋值。

最后加上 Step 1 引用的刷新方法。放在 `updateFontSize()` 之后：

```swift
    /// 字号偏好变化时把在场的 label 按角色刷一遍，否则当前那句不会更新。
    private func refreshLabelFonts() {
        for label in stackView.arrangedSubviews.compactMap({ $0 as? KaraokeLabel }) {
            label.font = label.isTranslationLine ? translationFont : font
        }
    }
```

- [ ] **Step 3: displayLrc 传递角色**

第 90 行签名改为：

```swift
    func displayLrc(_ firstLine: String, secondLine: String = "", secondLineIsTranslation: Bool = false) {
```

第 103 行 `let label = lyricsLabel(firstLine)` 改为：

```swift
            let label = lyricsLabel(firstLine, isTranslation: false)
```

第 109 行 `let label = lyricsLabel(secondLine)` 改为：

```swift
            let label = lyricsLabel(secondLine, isTranslation: secondLineIsTranslation)
```

第 99-101 行有个复用既有 label 的分支（`toBeHide[index].stringValue == firstLine`），它跳过 `lyricsLabel` 所以不重绑字体 —— 那条分支只在第一行内容没变时走，角色也没变，安全。

- [ ] **Step 4: 控制器传参**

`KaraokeLyricsController.swift:152` 现在是：

```swift
            self.lyricsView.displayLrc(firstLine, secondLine: secondLine)
```

改成（`secondLineIsTranslation` 是该方法里第 128 行已有的局部变量）：

```swift
            self.lyricsView.displayLrc(firstLine, secondLine: secondLine, secondLineIsTranslation: secondLineIsTranslation)
```

第 116 行的 `displayLrc("", secondLine: "")` 与第 35、37 行的 `displayLrc("LyricsX")` / `displayLrc("")` 用默认参数，不用改。

- [ ] **Step 5: 构建**

Run: `xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 提交**

```bash
git add LyricsX/View/KaraokeLyricsView.swift LyricsX/Controller/KaraokeLyricsController.swift
git commit -m "feat: give translation line its own font size in desktop lyrics"
```

---

### Task 8: 桌面歌词绑定新键

**Files:**
- Modify: `LyricsX/Controller/KaraokeLyricsController.swift:53`（Combine 订阅的键）、`:65-92`（绑定与 observe）、`:129-137`（翻译开关）、`:153`（进度动画条件）

**Interfaces:**
- Consumes: Task 2 的键、Task 4 的字号入口、Task 6 的 `isDrawingRomajiInline`、Task 7 的 `displayLrc` 新签名
- Produces: 无（末端接线）

字号键是 `Key<Int>`，视图属性是 `CGFloat`，两者类型不匹配。`bind(_:withDefaultName:)` 要求类型一致，所以这里不用绑定，改用 `observeDefaults` 手动赋值 —— 顺便能套上 Task 4 的钳制。项目里 `desktopLyricsFontSize` 已经是这个模式（第 86-92 行）。

- [ ] **Step 1: 布尔开关走绑定**

第 71-72 行现在是：

```swift
        lyricsView.bind(\.drawFurigana, withDefaultName: .desktopLyricsEnableFurigana, options: [.nullPlaceholder: false])
        lyricsView.bind(\.drawRomajin, withDefaultName: .desktopLyricsEnableRomajin, options: [.nullPlaceholder: false])
```

改成：

```swift
        lyricsView.bind(\.drawFurigana, withDefaultName: .desktopLyricsShowFurigana, options: [.nullPlaceholder: false])
        lyricsView.bind(\.drawRomajin, withDefaultName: .desktopLyricsShowRomaji, options: [.nullPlaceholder: false])
        lyricsView.bind(\.drawOriginal, withDefaultName: .desktopLyricsShowOriginal, options: [.nullPlaceholder: true])
```

- [ ] **Step 2: 字号走 observeDefaults**

第 86-92 行现在是：

```swift
        observeDefaults(keys: [
            .desktopLyricsFontName,
            .desktopLyricsFontSize,
            .desktopLyricsFontNameFallback,
        ], options: [.initial]) { [unowned self] in
            self.lyricsView.font = defaults.desktopLyricsFont
        }
```

改成（把三个新字号一起纳入同一个观察块，字体名变化时它们也要跟着重建）：

```swift
        observeDefaults(keys: [
            .desktopLyricsFontName,
            .desktopLyricsFontSize,
            .desktopLyricsFontNameFallback,
            .desktopLyricsFuriganaFontSize,
            .desktopLyricsRomajiFontSize,
            .desktopLyricsTranslationFontSize,
        ], options: [.initial]) { [unowned self] in
            self.lyricsView.font = defaults.desktopLyricsFont
            self.lyricsView.translationFont = defaults.desktopLyricsFont(size: defaults.desktopTranslationSize)
            self.lyricsView.furiganaFontSize = defaults.desktopFuriganaSize
            self.lyricsView.romajiFontSize = defaults.desktopRomajiSize
        }
```

- [ ] **Step 3: 翻译开关换键**

第 53 行的 Combine 订阅：

```swift
            defaults.publisher(for: [.preferBilingualLyrics, .desktopLyricsOneLineMode])
```

改成：

```swift
            defaults.publisher(for: [.desktopLyricsShowTranslation, .desktopLyricsOneLineMode])
```

第 131 行：

```swift
        } else if defaults[.preferBilingualLyrics],
```

改成：

```swift
        } else if defaults[.desktopLyricsShowTranslation],
```

- [ ] **Step 4: 进度动画在内联罗马音模式下跳过**

第 153-162 行现在是：

```swift
            if let upperTextField = self.lyricsView.displayLine1,
               let timetag = lrc.attachments.timetag {
```

改成（`isDrawingRomajiInline` 为真时原文字形不存在，进度层无处可画）：

```swift
            if let upperTextField = self.lyricsView.displayLine1,
               !upperTextField.isDrawingRomajiInline,
               let timetag = lrc.attachments.timetag {
```

- [ ] **Step 5: 构建**

Run: `xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 手动验证桌面歌词**

播放一首日文歌（有翻译，例如任意日语流行曲），用 `defaults write` 逐项切换后观察桌面歌词浮层：

```bash
defaults write com.JH.LyricsX DesktopLyricsShowFurigana -bool true
defaults write com.JH.LyricsX DesktopLyricsShowRomaji -bool true
defaults write com.JH.LyricsX DesktopLyricsFuriganaFontSize -int 20   # 注音明显变大
defaults write com.JH.LyricsX DesktopLyricsRomajiFontSize -int 16     # 罗马音明显变大
defaults write com.JH.LyricsX DesktopLyricsTranslationFontSize -int 30 # 翻译明显变大
defaults write com.JH.LyricsX DesktopLyricsShowOriginal -bool false   # 原文消失，罗马音成行
defaults write com.JH.LyricsX DesktopLyricsShowTranslation -bool false # 翻译行消失
```

逐条确认：改字号立即生效不需重启；关原文时罗马音顶上来且不崩溃；开原文时卡拉OK进度动画正常走。

- [ ] **Step 7: 提交**

```bash
git add LyricsX/Controller/KaraokeLyricsController.swift
git commit -m "feat: wire per-layer settings into desktop karaoke lyrics"
```

---

### Task 9: 歌词窗口的注音行与罗马音行生成（TDD）

歌词窗口没有 ruby 支持，注音要独立成行。这块是纯字符串逻辑，放进包里做 TDD。

下面的实现与预期输出都已在本机实测验证过（`swift test`），不是推测值。

**Files:**
- Create: `LyricsXPackage/Sources/LyricsXFoundation/LyricsAnnotationLines.swift`
- Test: `LyricsXPackage/Tests/LyricsXFoundationTests/LyricsAnnotationLinesTests.swift`

**Interfaces:**
- Consumes: `SwiftCF`（经 LyricsKit 传递依赖，包里可直接 `import SwiftCF`，已验证）
- Produces:
  - `public struct LyricsAnnotationLines: Equatable { public let furigana: String; public let romaji: String }`
  - `public func lyricsAnnotationLines(for content: String) -> LyricsAnnotationLines`

非日语输入返回两个空串。Task 10 的 `ScrollLyricsView` 调用它。

对齐精度：注音行用全角空格（U+3000）按宿主字形的列位置排布，做不到逐字精确对齐 —— 注音比宿主窄、字号又更小，纯文本无法补偿。设计文档已确认接受这个精度。

- [ ] **Step 1: 写失败的测试**

创建 `LyricsXPackage/Tests/LyricsXFoundationTests/LyricsAnnotationLinesTests.swift`。期望值均为实测输出：

```swift
import Testing
@testable import LyricsXFoundation

@Test func generatesFuriganaAndRomajiForJapanese() {
    let result = lyricsAnnotationLines(for: "高いあの窓で")
    #expect(result.furigana == "たか　　　まど")
    #expect(result.romaji == "takai ano mado de")
}

@Test func alignsFuriganaToHostColumns() {
    let result = lyricsAnnotationLines(for: "君の名は")
    #expect(result.furigana == "きみ　な")
    #expect(result.romaji == "kimi no na ha")
}

@Test func kanaOnlyLineHasNoFuriganaButHasRomaji() {
    let result = lyricsAnnotationLines(for: "こんにちは")
    #expect(result.furigana.isEmpty)
    #expect(result.romaji == "kon'nichiha")
}

@Test func nonJapaneseLinesProduceNothing() {
    // 中文汉字落在 CJK 统一汉字区，若不按语种拦截会生成乱码注音。
    let chinese = lyricsAnnotationLines(for: "在那高处的窗边")
    #expect(chinese.furigana.isEmpty)
    #expect(chinese.romaji.isEmpty)

    let english = lyricsAnnotationLines(for: "Hello world")
    #expect(english.furigana.isEmpty)
    #expect(english.romaji.isEmpty)
}

@Test func emptyInputIsSafe() {
    let result = lyricsAnnotationLines(for: "")
    #expect(result.furigana.isEmpty)
    #expect(result.romaji.isEmpty)
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --package-path LyricsXPackage`
Expected: FAIL，报 `cannot find 'lyricsAnnotationLines' in scope`

- [ ] **Step 3: 写实现**

创建 `LyricsXPackage/Sources/LyricsXFoundation/LyricsAnnotationLines.swift`：

```swift
import Foundation
import SwiftCF

/// 一句歌词衍生出的注音行与罗马音行文本，供歌词窗口独立成行渲染。
public struct LyricsAnnotationLines: Equatable {
    public let furigana: String
    public let romaji: String

    public init(furigana: String, romaji: String) {
        self.furigana = furigana
        self.romaji = romaji
    }

    public static let empty = LyricsAnnotationLines(furigana: "", romaji: "")
}

private let ideographicSpace = "\u{3000}"
private let kanjiSet = CharacterSet(charactersIn: "\u{4e00}" ..< "\u{9fc0}")

/// 非日语输入返回空 —— 中文汉字同样落在 CJK 统一汉字区，
/// 不按语种拦截会把中文歌词注成乱码假名。
public func lyricsAnnotationLines(for content: String) -> LyricsAnnotationLines {
    let ns = content as NSString
    guard ns.length > 0,
          CFStringTokenizer.bestLanguage(for: .from(ns))?.asSwift() == "ja" else {
        return .empty
    }

    let tokenizer = CFStringTokenizer.create(string: .from(ns))
    var furiganaParts: [(text: String, range: NSRange)] = []
    var romajiParts: [String] = []

    for tokenType in IteratorSequence(tokenizer) where tokenType.contains(.isCJWordMask) {
        let range = tokenizer.currentTokenRange().asNS
        let tokenStr = ns.substring(with: range)
        guard let latin = tokenizer.currentTokenAttribute(.latinTranscription)?.asNS() else { continue }
        romajiParts.append(latin as String)

        guard tokenStr.unicodeScalars.contains(where: kanjiSet.contains),
              let hiragana = latin.applyingTransform(.latinToHiragana, reverse: false),
              let (toAnnotate, inAnnotation) = rangeOfUncommonContent(tokenStr, hiragana) else { continue }
        var hostRange = NSRange(toAnnotate, in: tokenStr)
        hostRange.location += range.location
        furiganaParts.append((String(hiragana[inAnnotation]), hostRange))
    }

    return LyricsAnnotationLines(
        furigana: assembleFuriganaLine(furiganaParts),
        romaji: romajiParts.joined(separator: " ")
    )
}

private func assembleFuriganaLine(_ parts: [(text: String, range: NSRange)]) -> String {
    var line = ""
    var column = 0
    for (text, range) in parts {
        if range.location > column {
            line += String(repeating: ideographicSpace, count: range.location - column)
        }
        line += text
        // 按宿主字形推进列号，而不是按注音长度 —— 注音通常比宿主宽，
        // 用注音长度会把后续汉字的列位置吃掉（"君の名は" 会挤成 "きみな"）。
        column = max(range.location + range.length, column + 1)
    }
    return line
}

/// 找出汉字词与其假名读音的差异区间，用来只标注需要注音的部分
/// （"高い" 的读音是 "たかい"，只需在 "高" 上标 "たか"）。
private func rangeOfUncommonContent(_ s1: String, _ s2: String) -> (Range<String.Index>, Range<String.Index>)? {
    guard s1 != s2, !s1.isEmpty, !s2.isEmpty else { return nil }
    var (l1, l2) = (s1.startIndex, s2.startIndex)
    while s1[l1] == s2[l2] {
        guard let n1 = s1.index(l1, offsetBy: 1, limitedBy: s1.endIndex),
              let n2 = s2.index(l2, offsetBy: 1, limitedBy: s2.endIndex) else { break }
        (l1, l2) = (n1, n2)
    }
    var (r1, r2) = (s1.endIndex, s2.endIndex)
    repeat {
        guard let n1 = s1.index(r1, offsetBy: -1, limitedBy: s1.startIndex),
              let n2 = s2.index(r2, offsetBy: -1, limitedBy: s2.startIndex) else { break }
        (r1, r2) = (n1, n2)
    } while s1[r1] == s2[r2]
    return ((l1 ... r1).relative(to: s1.indices), (l2 ... r2).relative(to: s2.indices))
}
```

`rangeOfUncommonContent` 与 app 目标 `Utility/CFExtension.swift:46` 的同名私有函数逻辑一致。两份拷贝是有意的：app 那份服务 Core Text ruby（操作 `NSString`），这份服务纯文本行（操作 `String`）且要能在包里被测试。合并需要把 app 那套渲染逻辑也搬进包，超出本次范围。

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --package-path LyricsXPackage`
Expected: PASS，Task 1 的 4 个 + 本任务的 5 个共 9 个测试全绿

- [ ] **Step 5: 提交**

```bash
git add LyricsXPackage/Sources/LyricsXFoundation/LyricsAnnotationLines.swift \
        LyricsXPackage/Tests/LyricsXFoundationTests/LyricsAnnotationLinesTests.swift
git commit -m "feat: generate standalone furigana and romaji lines for lyrics window"
```

---

### Task 10: 歌词窗口四行渲染

每句从最多 2 行扩成最多 4 行，逐行按角色设字体。`ranges` 表的语义不变（一句一项，`NSRange` 覆盖该句所有可见行），所以高亮、滚动、双击定位三处逻辑完全不用改。

**Files:**
- Modify: `LyricsX/View/ScrollLyricsView.swift:42-51`（属性）、`:53-96`（`setupTextContents`）、`:213-217`（`updateFont`）

**Interfaces:**
- Consumes: Task 9 的 `lyricsAnnotationLines(for:)`、Task 4 的 `windowFuriganaSize` 等
- Produces: `ScrollLyricsView` 新属性 `@objc dynamic var showFurigana/showOriginal/showRomaji/showTranslation: Bool`、`@objc dynamic var furiganaFontSize/romajiFontSize/translationFontSize: CGFloat`。Task 11 的 HUD 控制器绑定它们。

- [ ] **Step 1: 加属性**

第 42-51 行现在是 `fontName` / `fontSize` 两个属性加两个私有变量。在 `fontSize` 之后插入：

```swift
    @objc dynamic var showFurigana = false {
        didSet { rebuildContents() }
    }

    @objc dynamic var showOriginal = true {
        didSet { rebuildContents() }
    }

    @objc dynamic var showRomaji = false {
        didSet { rebuildContents() }
    }

    @objc dynamic var showTranslation = true {
        didSet { rebuildContents() }
    }

    @objc dynamic var furiganaFontSize: CGFloat = 9 {
        didSet { updateFont() }
    }

    @objc dynamic var romajiFontSize: CGFloat = 7 {
        didSet { updateFont() }
    }

    @objc dynamic var translationFontSize: CGFloat = 11 {
        didSet { updateFont() }
    }
```

开关变化要重建文本（行数变了），字号变化只需重刷字体属性。

同时把私有状态从两个变量扩成三个 —— 需要记住每行的角色，字号变化时才能按角色重新应用字体：

```swift
    private enum LyricsLineRole {
        case furigana, original, romaji, translation
    }

    private var ranges: [(TimeInterval, NSRange)] = []
    private var roleRanges: [(LyricsLineRole, NSRange)] = []
    private var highlightedRange: NSRange?
    private var currentLyrics: Lyrics?
```

- [ ] **Step 2: 重写 setupTextContents**

第 53-96 行整段替换。保存 `lyrics` 供 `rebuildContents()` 用；按四层拼行；同时记录 `roleRanges`：

```swift
    func setupTextContents(lyrics: Lyrics?) {
        currentLyrics = lyrics
        guard let lyrics = lyrics else {
            ranges = []
            roleRanges = []
            textView.string = ""
            highlightedRange = nil
            return
        }

        var lrcContent = ""
        var newRanges: [(TimeInterval, NSRange)] = []
        var newRoleRanges: [(LyricsLineRole, NSRange)] = []
        let enabledLrc = lyrics.lines.filter { $0.enabled && !$0.content.isEmpty }
        let languageCode = lyrics.metadata.translationLanguages.first

        for line in enabledLrc {
            let lineStart = lrcContent.utf16.count
            var pieces: [(LyricsLineRole, String)] = []

            let annotations = (showFurigana || showRomaji) ? lyricsAnnotationLines(for: line.content) : .empty
            if showFurigana, !annotations.furigana.isEmpty {
                pieces.append((.furigana, annotations.furigana))
            }
            if showOriginal {
                pieces.append((.original, line.content))
            }
            if showRomaji, !annotations.romaji.isEmpty {
                pieces.append((.romaji, annotations.romaji))
            }
            if showTranslation, var trans = line.attachments[.translation(languageCode: languageCode)] {
                if languageCode?.hasPrefix("zh") == true, let converter = ChineseConverter.shared {
                    trans = converter.convert(trans)
                }
                pieces.append((.translation, trans))
            }

            for (offset, piece) in pieces.enumerated() {
                if offset > 0 {
                    lrcContent += "\n"
                }
                let start = lrcContent.utf16.count
                lrcContent += piece.1
                newRoleRanges.append((piece.0, NSRange(location: start, length: piece.1.utf16.count)))
            }

            // 整句范围覆盖它的所有可见行，高亮/滚动/双击定位据此工作。
            newRanges.append((line.position, NSRange(location: lineStart, length: lrcContent.utf16.count - lineStart)))
            if line != enabledLrc.last {
                lrcContent += "\n\n"
            }
        }
        ranges = newRanges
        roleRanges = newRoleRanges
        textView.string = lrcContent
        highlightedRange = nil

        let style = NSMutableParagraphStyle().with {
            $0.alignment = .center
        }
        textView.textStorage?.addAttributes([
            .foregroundColor: textColor,
            .paragraphStyle: style,
        ], range: textView.string.fullRange)
        applyFonts()
        needsLayout = true
    }

    private func rebuildContents() {
        setupTextContents(lyrics: currentLyrics)
    }
```

四层全关时 `pieces` 为空，该句不产生任何文本，`newRanges` 里那一项长度为 0 —— `highlight` 与 `scroll` 用 `boundingRect(forGlyphRange:)` 处理零长范围不会崩，只是定位落在行首。

翻译的中文转换条件保留 `languageCode?.hasPrefix("zh")`，但**外层的语种限制已删除** —— 现在任何语种的翻译都会显示，只有中文翻译才走简繁转换。这修掉了设计文档指出的既有限制。

- [ ] **Step 3: 逐行按角色设字体**

第 213-217 行的 `updateFont()` 现在对 `fullRange` 刷单一字体，改成按角色分配：

```swift
    func updateFont() {
        applyFonts()
    }

    private func applyFonts() {
        guard let textStorage = textView.textStorage else { return }
        for (role, range) in roleRanges {
            let size: CGFloat
            switch role {
            case .furigana: size = furiganaFontSize
            case .original: size = fontSize
            case .romaji: size = romajiFontSize
            case .translation: size = translationFontSize
            }
            guard let font = NSFont(name: fontName, size: size) ?? NSFont(name: "Helvetica", size: size) else { continue }
            textStorage.addAttribute(.font, value: font, range: range)
        }
    }
```

`updateFont()` 保留为公开方法 —— `fontName` 与 `fontSize` 的 `didSet` 已经在调它（第 43、47 行），不改那两处。

- [ ] **Step 4: 构建**

Run: `xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

若报 `cannot find 'lyricsAnnotationLines' in scope`，确认文件顶部有 `import LyricsXFoundation`（第 2 行已有）。

- [ ] **Step 5: 提交**

```bash
git add LyricsX/View/ScrollLyricsView.swift
git commit -m "feat: render four lyrics layers in lyrics window"
```

---

### Task 11: 歌词窗口绑定新键

**Files:**
- Modify: `LyricsX/LyricsHUD/LyricsHUDViewController.swift:45-56`

**Interfaces:**
- Consumes: Task 2 的键、Task 4 的字号入口、Task 10 的 `ScrollLyricsView` 属性
- Produces: 无（末端接线）

- [ ] **Step 1: 加开关绑定与字号观察**

在第 48 行 `bind(\.highlightColor, ...)` 之后插入四个开关绑定：

```swift
        lyricsScrollView.bind(\.showFurigana, withDefaultName: .lyricsWindowShowFurigana, options: [.nullPlaceholder: false])
        lyricsScrollView.bind(\.showOriginal, withDefaultName: .lyricsWindowShowOriginal, options: [.nullPlaceholder: true])
        lyricsScrollView.bind(\.showRomaji, withDefaultName: .lyricsWindowShowRomaji, options: [.nullPlaceholder: false])
        lyricsScrollView.bind(\.showTranslation, withDefaultName: .lyricsWindowShowTranslation, options: [.nullPlaceholder: true])
```

字号键是 `Key<Int>`、属性是 `CGFloat`，类型不匹配，用 `observeDefaults` 手动赋值并套上钳制。在第 50-56 行那个 `observeDefaults(key: .lyricsWindowFontSize, ...)` 块**之后**插入：

```swift
        observeDefaults(keys: [
            .lyricsWindowFuriganaFontSize,
            .lyricsWindowRomajiFontSize,
            .lyricsWindowTranslationFontSize,
        ], options: [.initial]) { [unowned self] in
            self.lyricsScrollView.furiganaFontSize = defaults.windowFuriganaSize
            self.lyricsScrollView.romajiFontSize = defaults.windowRomajiSize
            self.lyricsScrollView.translationFontSize = defaults.windowTranslationSize
        }
```

- [ ] **Step 2: 构建**

Run: `xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 手动验证歌词窗口**

播放日文歌，从菜单栏打开歌词窗口（或用 `ShortcutShowLyricsWindow` 快捷键），逐项切换：

```bash
defaults write com.JH.LyricsX LyricsWindowShowFurigana -bool true    # 注音行出现在原文上方
defaults write com.JH.LyricsX LyricsWindowShowRomaji -bool true      # 罗马音行出现在原文下方
defaults write com.JH.LyricsX LyricsWindowFuriganaFontSize -int 16   # 注音行变大
defaults write com.JH.LyricsX LyricsWindowTranslationFontSize -int 22 # 翻译行变大
defaults write com.JH.LyricsX LyricsWindowShowOriginal -bool false   # 原文行消失
defaults write com.JH.LyricsX LyricsWindowShowTranslation -bool false # 翻译行消失
```

重点确认三件事：切换开关后行数变化且滚动位置仍能跟上播放进度；双击某句能跳转到对应时间；换一首**非中文翻译**的歌（例如日文歌配英文翻译），确认翻译行现在会显示（这是本次顺带修的既有限制）。

- [ ] **Step 4: 提交**

```bash
git add LyricsX/LyricsHUD/LyricsHUDViewController.swift
git commit -m "feat: wire per-layer settings into lyrics window"
```

---

### Task 12: 偏好界面控件

「显示」面板已经是 tabView 结构，恰好对应两套设置：

- `tabViewItem label="Karaoke"`（identifier 1, id `aUg-eg-K5C`，view id `mfE-32-ATy`）→ 桌面歌词四层
- `tabViewItem label="Window"`（identifier 2, id `LbQ-p9-Zti`）→ 歌词窗口四层

两个 tab 共用 `userDefaultsController` id `Nm6-oq-wpY`（`representsSharedInstance="YES"`，位于第 1047 行）。所有绑定的 `destination` 都用它。

**这一步用 Xcode Interface Builder 做，不要手写 XML。** storyboard 的 `<rect>` frame 值、gridView 行列引用、约束 id 之间互相牵连，手写极易产出打不开的文件。

**Files:**
- Modify: `LyricsX/Base.lproj/Preferences.storyboard`
- Modify: `LyricsX/mul.lproj/Preferences.xcstrings`（Xcode 会在构建时补齐新文案条目）

**Interfaces:**
- Consumes: Task 2 的 14 个键
- Produces: 无（`PreferenceDisplayViewController` 不需要新 IBOutlet，全走绑定）

- [ ] **Step 1: Karaoke tab 加四层控件**

在 Xcode 里打开 `Preferences.storyboard` → Display 场景 → Karaoke tab。加 4 组「复选框 + 字号输入框」。

每个复选框：Bind → Value → Shared User Defaults Controller，Model Key Path 填对应键名：

| 复选框标题 | Model Key Path |
|---|---|
| `Show furigana` | `values.DesktopLyricsShowFurigana` |
| `Show original` | `values.DesktopLyricsShowOriginal` |
| `Show romaji` | `values.DesktopLyricsShowRomaji` |
| `Show translation` | `values.DesktopLyricsShowTranslation` |

每个字号输入框（`NSTextField`）：Bind → Value 到同一个 controller：

| 输入框 | Model Key Path |
|---|---|
| 注音字号 | `values.DesktopLyricsFuriganaFontSize` |
| 罗马音字号 | `values.DesktopLyricsRomajiFontSize` |
| 翻译字号 | `values.DesktopLyricsTranslationFontSize` |

原文字号**不加新控件** —— 该 tab 已有 `karaokeFontSelectField`（`FontSelectTextField`）在管 `DesktopLyricsFontSize`，再加一个会造成两个控件写同一个键。

每个字号输入框挂一个 `NSNumberFormatter`：Behavior 设为 Decimal、Minimum `6`、Maximum `120`、Allows Floats 关闭。这样 UI 层就拦住越界值，Task 1 的钳制是第二道防线（防 `defaults write` 绕过 UI）。

- [ ] **Step 2: Window tab 加四层控件**

同样 4 组控件，键名换成 window 那套：

| 复选框标题 | Model Key Path |
|---|---|
| `Show furigana` | `values.LyricsWindowShowFurigana` |
| `Show original` | `values.LyricsWindowShowOriginal` |
| `Show romaji` | `values.LyricsWindowShowRomaji` |
| `Show translation` | `values.LyricsWindowShowTranslation` |

| 输入框 | Model Key Path |
|---|---|
| 注音字号 | `values.LyricsWindowFuriganaFontSize` |
| 罗马音字号 | `values.LyricsWindowRomajiFontSize` |
| 翻译字号 | `values.LyricsWindowTranslationFontSize` |

原文字号同理不加 —— 已有 `hudFontSelectField` 管 `LyricsWindowFontSize`。

- [ ] **Step 3: 删除「通用」面板的旧控件**

三处引用旧键的控件要删（Xcode 里选中控件删除即可，别手改 XML）：

| 位置 | 控件 | 旧键 |
|---|---|---|
| 第 1531 行附近 | 复选框 `Automatically generate furigana for Japanese lyrics` | `DesktopLyricsEnableFurigana` |
| 第 1544 行附近 | 复选框 `Automatically generate romajin for Japanese lyrics` | `DesktopLyricsEnableRomajin` |
| 第 2654 行附近 | 「General (Deprecated)」场景里的同名复选框 | `DesktopLyricsEnableFurigana` |

另外第 543、2157 行有两个绑定 `PreferBilingualLyrics` 的控件，同样删除。

删完自查，以下命令应无输出：

```bash
grep -n "DesktopLyricsEnableFurigana\|DesktopLyricsEnableRomajin\|PreferBilingualLyrics" LyricsX/Base.lproj/Preferences.storyboard
```

- [ ] **Step 4: 构建并确认 storyboard 未损坏**

```bash
xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`。storyboard 写坏时报错形如 `Interface Builder encountered an error communicating with the iOS Simulator` 或 `Illegal Configuration`。

启动 app 打开偏好 → 显示，确认两个 tab 的控件都在、勾选与输入立即反映到歌词显示。

- [ ] **Step 5: 提交**

```bash
git add LyricsX/Base.lproj/Preferences.storyboard LyricsX/mul.lproj/Preferences.xcstrings
git commit -m "feat: add per-layer lyrics controls to Display preferences"
```

---

### Task 13: 删除旧键并整体验证

旧键的最后一批引用清掉。放在最后是因为 Task 3 的迁移代码需要它们存在过 —— 迁移用的是字符串字面量，所以删掉 `DefaultsKey` 声明不影响迁移。

**Files:**
- Modify: `LyricsX/Utility/Global.swift`（删 3 个键声明）
- Modify: `LyricsX/Supporting Files/UserDefaults.plist`（删旧键默认值）
- Modify: `LyricsX/Component/AppDelegate.swift:275`（删 `.preferBilingualLyrics: isZh`）

**Interfaces:**
- Consumes: 前 12 个任务
- Produces: 无

- [ ] **Step 1: 确认没有残留引用**

```bash
grep -rn "preferBilingualLyrics\|desktopLyricsEnableFurigana\|desktopLyricsEnableRomajin" LyricsX/ --include="*.swift"
```

期望只剩 `Global.swift` 里的 3 行声明。若 `KaraokeLyricsController.swift` 或 `ScrollLyricsView.swift` 还有引用，说明 Task 8 或 Task 10 漏改了，先补上。

- [ ] **Step 2: 删除键声明**

从 `LyricsX/Utility/Global.swift` 删这三行：

```swift
    static let preferBilingualLyrics = Key<Bool>("PreferBilingualLyrics")
    static let desktopLyricsEnableFurigana = Key<Bool>("DesktopLyricsEnableFurigana")
    static let desktopLyricsEnableRomajin = Key<Bool>("DesktopLyricsEnableRomajin")
```

- [ ] **Step 3: 删除默认值注册**

`AppDelegate.swift:275` 删这一行：

```swift
            .preferBilingualLyrics: isZh,
```

删掉后 `isZh` 仍被第 276 行的 `.chineseConversionIndex: isHant ? 2 : 0` 间接用到（`isHant` 依赖 `isZh`），所以 `isZh` 变量本身**不要删**。

`UserDefaults.plist` 里删 `DesktopLyricsEnableFurigana` 及其 `<false/>`（若存在 `DesktopLyricsEnableRomajin` / `PreferBilingualLyrics` 条目也一并删）。

注意：删掉这些注册**不影响**老用户 —— 他们的显式值已在 Task 3 迁移进新键，之后旧键无人读取。

- [ ] **Step 4: 全量验证**

```bash
swift test --package-path LyricsXPackage
xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build 2>&1 | tail -5
swiftlint
plutil -lint "LyricsX/Supporting Files/UserDefaults.plist"
```

Expected: 测试 9 个全绿；`** BUILD SUCCEEDED **`；swiftlint 无新增告警；plist `OK`。

- [ ] **Step 5: 端到端手动验证**

这一步必须人工完成 —— 菜单栏应用的渲染效果无法用命令行断言。

准备一首日文歌（带翻译），播放后逐项确认：

**桌面歌词**
- 四个开关各自独立生效，互不影响
- 三个字号改动立即可见，不需重启
- 关闭原文时罗马音顶上来成行，不崩溃
- 显示原文时卡拉OK进度动画正常
- 换一首中文歌，确认不出现乱码注音（中文汉字不应被注上假名）

**歌词窗口**
- 四个开关与三个字号同上，且与桌面歌词的设置互不干扰
- 切换开关后滚动仍跟得上播放进度
- 双击某句能跳转到对应时间点
- 非中文翻译（如日文歌配英文翻译）现在会显示

**迁移**
- 按 Task 3 Step 4 的脚本造一次「老用户」状态，确认设置被正确带过来

- [ ] **Step 6: 提交**

```bash
git add LyricsX/Utility/Global.swift LyricsX/Component/AppDelegate.swift "LyricsX/Supporting Files/UserDefaults.plist"
git commit -m "refactor: remove legacy furigana/romaji/bilingual defaults keys"
```

---

## 任务依赖

```
Task 1 (字号钳制) ─┐
                   ├→ Task 4 (字号入口) ─┬→ Task 8 (桌面接线) ─┐
Task 2 (键) ───────┘                     └→ Task 11 (窗口接线) ┤
   │                                                            │
   ├→ Task 3 (迁移)                                             │
   │                                                            ├→ Task 13 (清理+验证)
Task 5 (注音/罗马音字号) → Task 6 (隐藏原文) → Task 7 (翻译字号) ┤
                                                                │
Task 9 (注音行生成) → Task 10 (窗口四行) ───────────────────────┤
                                                                │
Task 12 (偏好界面) ─────────────────────────────────────────────┘
```

Task 5→6→7 必须按序（都改同一个文件的相邻区域）。Task 9 与 Task 1/2 之间没有依赖，可以先做。Task 12 依赖 Task 2 的键名，但与其他视图改动互不干扰。

