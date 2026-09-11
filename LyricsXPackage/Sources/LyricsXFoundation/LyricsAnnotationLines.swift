import Foundation
import SwiftCF

/// 一句歌词衍生出的注音行与罗马音行文本，供歌词窗口独立成行渲染。
public struct LyricsAnnotationLines: Equatable, Sendable {
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
