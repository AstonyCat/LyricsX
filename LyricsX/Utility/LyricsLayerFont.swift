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
