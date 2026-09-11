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
