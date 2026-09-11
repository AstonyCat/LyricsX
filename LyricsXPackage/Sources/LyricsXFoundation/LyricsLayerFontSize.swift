/// 歌词各层字号的合法区间（pt）。
public let lyricsFontSizeRange: ClosedRange<Int> = 6...120

/// 把 UserDefaults 里可能被手工改坏的字号钳制回合法区间。
public func clampLyricsFontSize(_ value: Int) -> Double {
    Double(min(max(value, lyricsFontSizeRange.lowerBound), lyricsFontSizeRange.upperBound))
}
