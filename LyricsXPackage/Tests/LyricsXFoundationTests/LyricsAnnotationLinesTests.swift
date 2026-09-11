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
