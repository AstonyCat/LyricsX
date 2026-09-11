import AppKit
import LyricsXFoundation
import OpenCC

protocol ScrollLyricsViewDelegate: AnyObject {
    func doubleClickLyricsLine(at position: TimeInterval)
    func scrollWheelDidStartScroll()
    func scrollWheelDidEndScroll()
}

class ScrollLyricsView: NSScrollView {
    weak var delegate: ScrollLyricsViewDelegate?

    private var textView: NSTextView {
        // swiftlint:disable:next force_cast
        return documentView as! NSTextView
    }

    var fadeStripWidth: CGFloat = 24

    @objc dynamic var textColor = #colorLiteral(red: 0.7540688515, green: 0.7540867925, blue: 0.7540771365, alpha: 1) {
        didSet {
            DispatchQueue.main.async {
                let range = self.textView.string.fullRange
                self.textView.textStorage?.addAttribute(.foregroundColor, value: self.textColor, range: range)
                if let highlightedRange = self.highlightedRange {
                    self.textView.textStorage?.addAttribute(.foregroundColor, value: self.highlightColor, range: highlightedRange)
                }
            }
        }
    }

    @objc dynamic var highlightColor = #colorLiteral(red: 0.8866666667, green: 1, blue: 0.8, alpha: 1) {
        didSet {
            guard let highlightedRange = self.highlightedRange else { return }
            DispatchQueue.main.async {
                self.textView.textStorage?.addAttribute(.foregroundColor, value: self.highlightColor, range: highlightedRange)
            }
        }
    }

    @objc dynamic var fontName = "Helvetica" {
        didSet { updateFont() }
    }

    @objc dynamic var fontSize: CGFloat = 12 {
        didSet { updateFont() }
    }

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

    private enum LyricsLineRole {
        case furigana, original, romaji, translation
    }

    private var ranges: [(TimeInterval, NSRange)] = []
    private var roleRanges: [(LyricsLineRole, NSRange)] = []
    private var highlightedRange: NSRange?
    private var currentLyrics: Lyrics?

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

    override func layout() {
        super.layout()
        updateFadeEdgeMask()
        updateEdgeInset()
    }

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount == 2 else {
            super.mouseUp(with: event)
            return
        }

        let clickPoint = textView.convert(event.locationInWindow, from: nil)
        let clickRange = ranges.filter { _, range in
            let bounding = textView.layoutManager!.boundingRect(forGlyphRange: range, in: textView.textContainer!)
            return bounding.contains(clickPoint)
        }
        if let (position, _) = clickRange.first {
            delegate?.doubleClickLyricsLine(at: position)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        switch event.momentumPhase {
        case .began:
            delegate?.scrollWheelDidStartScroll()
        case .ended,
             .cancelled:
            delegate?.scrollWheelDidEndScroll()
        default:
            break
        }
    }

    // overriding scrollwheel method breaks trackpad responsive scrolling ability
    override class var isCompatibleWithResponsiveScrolling: Bool {
        return true
    }

    private func updateFadeEdgeMask() {
        let location = fadeStripWidth / frame.height
        wantsLayer = true
        layer?.mask = CAGradientLayer().then {
            $0.frame = bounds
            $0.colors = [#colorLiteral(red: 0, green: 0, blue: 0, alpha: 0), #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1), #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1), #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0)] as [CGColor]
            $0.locations = [0, location as NSNumber, (1 - location) as NSNumber, 1]
            $0.startPoint = .zero
            $0.endPoint = CGPoint(x: 0, y: 1)
        }
    }

    private func updateEdgeInset() {
        guard !ranges.isEmpty else {
            return
        }

        let bounding1 = textView.layoutManager!.boundingRect(forGlyphRange: ranges.first!.1, in: textView.textContainer!)
        let topInset = frame.height / 2 - bounding1.height / 2
        let bounding2 = textView.layoutManager!.boundingRect(forGlyphRange: ranges.last!.1, in: textView.textContainer!)
        let bottomInset = frame.height / 2 - bounding2.height / 2
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
    }

    func highlight(position: TimeInterval) {
        guard !ranges.isEmpty else {
            return
        }

        var left = ranges.startIndex
        var right = ranges.endIndex - 1
        while left <= right {
            let mid = (left + right) / 2
            if ranges[mid].0 <= position {
                left = mid + 1
            } else {
                right = mid - 1
            }
        }
        let range = ranges[right.clamped(to: ranges.indices)].1

        if highlightedRange == range {
            return
        }

        highlightedRange.map { textView.textStorage?.addAttribute(.foregroundColor, value: textColor, range: $0) }
        textView.textStorage?.addAttribute(.foregroundColor, value: highlightColor, range: range)

        highlightedRange = range
    }

    func scroll(position: TimeInterval) {
        guard !ranges.isEmpty else {
            return
        }

        var left = ranges.startIndex
        var right = ranges.endIndex - 1
        while left <= right {
            let mid = (left + right) / 2
            if ranges[mid].0 <= position {
                left = mid + 1
            } else {
                right = mid - 1
            }
        }
        let range = ranges[right.clamped(to: ranges.indices)].1

        let bounding = textView.layoutManager!.boundingRect(forGlyphRange: range, in: textView.textContainer!)

        let point = NSPoint(x: 0, y: bounding.midY - frame.height / 2)
        textView.scroll(point)
    }

    func updateFont() {
        applyFonts()
    }

    private func applyFonts() {
        guard let textStorage = textView.textStorage else { return }
        // 行与行、句与句之间的换行不属于任何 role 区间，若不先铺一层基础字体，
        // 它们会一直留着 storyboard 的字体，让空行间距不随用户字号缩放。
        let fullRange = NSRange(location: 0, length: textStorage.length)
        if let baseFont = NSFont(name: fontName, size: fontSize) ?? NSFont(name: "Helvetica", size: fontSize) {
            textStorage.addAttribute(.font, value: baseFont, range: fullRange)
        }
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
}
