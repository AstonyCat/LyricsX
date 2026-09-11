import AppKit
import SnapKit

class PreferenceDisplayViewController: PreferenceViewController, FontSelectTextFieldDelegate {
    @IBOutlet var karaokeFontSelectField: FontSelectTextField!
    @IBOutlet var hudFontSelectField: FontSelectTextField!

    @IBOutlet var fontFallbackLabel: NSTextField!
    @IBOutlet var removeFontFallbackButton: NSButton!

    override func viewDidLoad() {
        karaokeFontSelectField.selectedFont = defaults.desktopLyricsFont
        karaokeFontSelectField.fontChangeDelegate = self
        hudFontSelectField.selectedFont = defaults.lyricsWindowFont
        hudFontSelectField.fontChangeDelegate = self
        updateScreenFontFallback()
        setUpLyricsLayerControls()
        super.viewDidLoad()
    }

    // MARK: - Lyrics layer controls

    // Per-layer show/size controls are built in code rather than in the storyboard:
    // the Display pane positions its controls with absolute frames plus a web of
    // constraints, and hand-authoring that XML is fragile. Both font-select outlets
    // are direct subviews of their tab's content view, so their superviews are the
    // per-tab anchors.
    private func setUpLyricsLayerControls() {
        // Karaoke tab (DesktopLyrics*): the only free space is the upper-left
        // quadrant, left of the mode checkboxes and above the "Disable lyrics
        // when:" label. Compact, hard-height rows keep the group's bottom edge
        // ~13pt above that label even if text metrics grow. Window tab
        // (LyricsWindow*): open space below the highlight color well.
        if let karaokeTabContentView = karaokeFontSelectField.superview {
            installLyricsLayerControls(keyPrefix: "DesktopLyrics", in: karaokeTabContentView, topInset: 12, leadingInset: 20, compact: true)
        }
        if let windowTabContentView = hudFontSelectField.superview {
            installLyricsLayerControls(keyPrefix: "LyricsWindow", in: windowTabContentView, topInset: 140, leadingInset: 173, compact: false)
        }
    }

    private func installLyricsLayerControls(keyPrefix: String, in containerView: NSView, topInset: CGFloat, leadingInset: CGFloat, compact: Bool) {
        let group = Self.makeLyricsLayerControls(keyPrefix: keyPrefix, compact: compact)
        containerView.addSubview(group)
        group.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(topInset)
            make.leading.equalToSuperview().offset(leadingInset)
        }
    }

    private static func makeLyricsLayerControls(keyPrefix: String, compact: Bool) -> NSStackView {
        let rowHeight: CGFloat = compact ? 20 : 22
        let rowSpacing: CGFloat = compact ? 1 : 6

        let group = NSStackView()
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = rowSpacing

        for spec in lyricsLayerSpecs(keyPrefix: keyPrefix) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8

            let title = NSLocalizedString(spec.titleKey, comment: "Checkbox toggling a lyrics layer on the Display preferences pane.")
            let checkbox = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            checkbox.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values.\(spec.showKey)")
            row.addArrangedSubview(checkbox)
            checkbox.snp.makeConstraints { make in
                make.width.equalTo(132)
            }

            if let sizeKey = spec.sizeKey {
                let sizeField = NSTextField()
                sizeField.controlSize = compact ? .small : .regular
                sizeField.formatter = lyricsFontSizeFormatter
                sizeField.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values.\(sizeKey)")
                row.addArrangedSubview(sizeField)
                sizeField.snp.makeConstraints { make in
                    make.width.equalTo(56)
                    make.height.equalTo(rowHeight)
                }
            }

            group.addArrangedSubview(row)
            // Hard-pin row heights so the group's total height is fixed: larger
            // text metrics must not grow the Karaoke group into the label below
            // (a taller checkbox simply centers within, and can overflow, its
            // row instead of pushing rows apart).
            row.snp.makeConstraints { make in
                make.height.equalTo(rowHeight)
            }
        }

        return group
    }

    private struct LyricsLayerSpec {
        let titleKey: String
        let showKey: String
        let sizeKey: String?
    }

    private static func lyricsLayerSpecs(keyPrefix: String) -> [LyricsLayerSpec] {
        // The original-lyrics row intentionally has no size field: the tab's
        // existing FontSelectTextField already owns the original font size
        // (DesktopLyricsFontSize / LyricsWindowFontSize), and a second writer
        // would race it.
        [
            LyricsLayerSpec(titleKey: "Show furigana", showKey: "\(keyPrefix)ShowFurigana", sizeKey: "\(keyPrefix)FuriganaFontSize"),
            LyricsLayerSpec(titleKey: "Show original", showKey: "\(keyPrefix)ShowOriginal", sizeKey: nil),
            LyricsLayerSpec(titleKey: "Show romaji", showKey: "\(keyPrefix)ShowRomaji", sizeKey: "\(keyPrefix)RomajiFontSize"),
            LyricsLayerSpec(titleKey: "Show translation", showKey: "\(keyPrefix)ShowTranslation", sizeKey: "\(keyPrefix)TranslationFontSize"),
        ]
    }

    private static let lyricsFontSizeFormatter: NumberFormatter = {
        // UI-level guard against out-of-range sizes; the model layer clamps again,
        // so a `defaults write` cannot smuggle bad values past rendering.
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 6
        formatter.maximum = 120
        return formatter
    }()

    func updateScreenFontFallback() {
        guard let fallback = defaults[.desktopLyricsFontNameFallback].first else {
            fontFallbackLabel.isHidden = true
            removeFontFallbackButton.isHidden = true
            return
        }
        fontFallbackLabel.isHidden = false
        removeFontFallbackButton.isHidden = false
        let format = NSLocalizedString("Font Fallback: %@", comment: "")
        fontFallbackLabel.stringValue = String(format: format, arguments: [fallback])
    }

    @IBAction func removeFontFallbackAction(_ sender: Any) {
        defaults[.desktopLyricsFontNameFallback].removeAll()
        updateScreenFontFallback()
    }

    func fontChanged(from oldFont: NSFont, to newFont: NSFont, sender: FontSelectTextField) {
        if sender === karaokeFontSelectField {
            defaults[.desktopLyricsFontName] = newFont.fontName
            defaults[.desktopLyricsFontSize] = Int(newFont.pointSize)
            if (oldFont.familyName != nil && oldFont.familyName != newFont.familyName)
                || oldFont.fontName != newFont.fontName {
                // guarantee different font family of font fallback
                var fallback = defaults[.desktopLyricsFontNameFallback]
                if let index = fallback.firstIndex(of: newFont.fontName) {
                    fallback.remove(at: index)
                }
                fallback.insert(oldFont.fontName, at: 0)
                defaults[.desktopLyricsFontNameFallback] = Array(fallback.prefix(fontNameFallbackCountMax))
                updateScreenFontFallback()
            }
        } else if sender === hudFontSelectField {
            defaults[.lyricsWindowFontName] = newFont.fontName
            defaults[.lyricsWindowFontSize] = Int(newFont.pointSize)
        }
    }
}

class AlphaColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        NSColorPanel.shared.showsAlpha = true
        super.activate(exclusive)
    }

    override func deactivate() {
        super.deactivate()
        NSColorPanel.shared.showsAlpha = false
    }
}
