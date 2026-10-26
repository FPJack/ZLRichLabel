//
//  ZLAttributedLabel+Layout.swift
//  ZLRichLabel
//
//  ZLAttributedLabel 的排版：字号自适应、行与原点、textRect / sizeThatFits、字符定位、截断
//

import UIKit
import CoreText

extension ZLAttributedLabel {

    func fontScaleDidChange() {
        fontScaleCache = nil
        scaledLayoutCache = nil
        invalidateAccessibilityElements()
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// 当前尺寸下的字体缩放比例
    func currentFontScale() -> CGFloat {
        guard adjustsFontSizeToFitWidth, let text = storedText, text.length > 0 else { return 1 }
        let minimum = minimumScaleFactor > 0 ? min(minimumScaleFactor, 1) : 1
        guard minimum < 1 else { return 1 }
        let insetBounds = bounds.inset(by: textInsets)
        guard insetBounds.width > 0 else { return 1 }
        let lines = numberOfLines
        let key = FontScaleKey(width: insetBounds.width, height: insetBounds.height, numberOfLines: lines, minimum: minimum)
        if let cache = fontScaleCache, cache.key == key { return cache.scale }

        let fits: (CGFloat) -> Bool = { scale in
            ZLAttributedLabel.text(ZLAttributedLabel.scaledText(text, scale: scale),
                                   fitsWidth: key.width, height: key.height, lineLimit: lines)
        }
        var scale: CGFloat = 1
        if !fits(1) {
            if fits(minimum) {
                // 二分查找能放下的最大比例
                var low = minimum
                var high: CGFloat = 1
                for _ in 0..<10 {
                    let mid = (low + high) / 2
                    if fits(mid) { low = mid } else { high = mid }
                }
                scale = low
            } else {
                scale = minimum
            }
        }
        fontScaleCache = (key, scale)
        return scale
    }

    /// 文字是否能在给定尺寸内放下（单行按宽度；多行按行数与高度，高度 <= 0 时不限）
    static func text(_ text: NSAttributedString, fitsWidth width: CGFloat, height: CGFloat, lineLimit: Int) -> Bool {
        let maxValue: CGFloat = 100000
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        if lineLimit == 1 {
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: maxValue, height: maxValue), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            guard let line = (CTFrameGetLines(frame) as? [CTLine])?.first else { return true }
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)
            return CGFloat(lineWidth) <= width - 0.25   // 留一点余量：超出一点 CoreText 也会折行 / 截断
        }
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: maxValue), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
        if lineLimit > 0, lines.count > lineLimit { return false }
        guard height > 0 else { return true }
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: text.length), nil, CGSize(width: width, height: maxValue), nil)
        return ceil(size.height) <= height
    }

    /// 按比例缩小文字中的字体
    static func scaledText(_ text: NSAttributedString, scale: CGFloat) -> NSAttributedString {
        guard scale < 1, text.length > 0 else { return text }
        let mutable = NSMutableAttributedString(attributedString: text)
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length), options: []) { value, range, _ in
            guard let font = value as? UIFont else { return }
            mutable.addAttribute(.font, value: font.withSize(max(1, font.pointSize * scale)), range: range)
        }
        return mutable
    }

    /// 绘制 / 定位使用的文字：字号自适应缩小时为缩小后的副本（字符与下标不变）
    func displayText(for text: NSAttributedString) -> NSAttributedString {
        let scale = currentFontScale()
        guard scale < 1 else { return text }
        if let cache = scaledLayoutCache, cache.source === text, cache.scale == scale { return cache.layout.text }
        return ZLAttributedLabel.scaledText(text, scale: scale)
    }

    /// 绘制 / 定位使用的排版（`sizeThatFits` 等尺寸计算仍使用原字号的 `textLayout(for:)`）
    func displayLayout(for text: NSAttributedString) -> ZLTextLayout {
        let scale = currentFontScale()
        guard scale < 1 else { return textLayout(for: text) }
        if let cache = scaledLayoutCache, cache.source === text, cache.scale == scale { return cache.layout }
        let layout = ZLTextLayout(text: ZLAttributedLabel.scaledText(text, scale: scale))
        scaledLayoutCache = (text, scale, layout)
        return layout
    }

    /// 按 textRect 排版得到的所有行与原点（缓存，内容或区域不变时直接返回）
    func frameLines(for text: NSAttributedString, in textRect: CGRect) -> ([CTLine], [CGPoint]) {
        let layout = displayLayout(for: text)
        if layout.frameRect != textRect {
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(layout.framesetter, CFRange(location: 0, length: layout.text.length), path, nil)
            let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            if !lines.isEmpty {
                CTFrameGetLineOrigins(frame, CFRange(location: 0, length: lines.count), &origins)
            }
            layout.frameRect = textRect
            layout.frameLines = lines
            layout.frameOrigins = origins
        }
        return (layout.frameLines, layout.frameOrigins)
    }

    /// 文字在某个宽度下的总行数
    func lineCount(of text: NSAttributedString, width: CGFloat) -> Int {
        let layout = textLayout(for: text)
        if let count = layout.lineCounts[width] { return count }
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 100000), transform: nil)
        let frame = CTFramesetterCreateFrame(layout.framesetter, CFRange(location: 0, length: 0), path, nil)
        let count = (CTFrameGetLines(frame) as? [CTLine])?.count ?? 0
        layout.lineCounts[width] = count
        return count
    }

    /// 文字的书写方向：取第一个强方向字符（与 CoreText 的自然段落方向一致），没有强方向字符时为 nil
    static func detectRightToLeft(_ string: String) -> Bool? {
        for scalar in string.unicodeScalars {
            let v = scalar.value
            // Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan, Mandaic, Arabic Ext, 表现形式
            if (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
                || (0x10800...0x10FFF).contains(v) || (0x1E800...0x1EFFF).contains(v) {
                // 阿拉伯-印度数字（0660–0669、06F0–06F9）是弱方向字符，跳过
                if (0x0660...0x0669).contains(v) || (0x06F0...0x06F9).contains(v) { continue }
                return true
            }
            if CharacterSet.letters.contains(scalar) {
                return false
            }
        }
        return nil
    }

    /// 某个段落的书写方向是否为从右到左：段落样式指定时按样式，否则按内容（没有强方向字符时跟随界面方向）
    func isRightToLeftParagraph(_ style: NSParagraphStyle?, in text: NSAttributedString, at location: Int) -> Bool {
        switch style?.baseWritingDirection ?? .natural {
        case .rightToLeft: return true
        case .leftToRight: return false
        default:
            let string = text.string as NSString
            let paragraph = string.paragraphRange(for: NSRange(location: min(location, string.length), length: 0))
            return ZLAttributedLabel.detectRightToLeft(string.substring(with: paragraph))
                ?? (effectiveUserInterfaceLayoutDirection == .rightToLeft)
        }
    }

    /// 一行在 textRect 中可用的水平区域（相对 textRect 左边）：扣除段落样式的缩进
    /// （`firstLineHeadIndent` / `headIndent` / `tailIndent`，从右到左的段落中头部缩进在右侧）。
    /// `line` 须为 frameLines 返回的原始行（截断后的行字符下标从 0 开始，不能用来查段落）
    func lineBox(for line: CTLine, in text: NSAttributedString, width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let location = CTLineGetStringRange(line).location
        guard location >= 0, location < text.length,
              let style = text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        else { return (0, width) }
        let string = text.string as NSString
        let isFirstLine = string.paragraphRange(for: NSRange(location: location, length: 0)).location == location
        let head = isFirstLine ? style.firstLineHeadIndent : style.headIndent
        // tailIndent > 0：到头部边缘的距离（即行宽）；<= 0：到尾部边缘的距离
        let tail = style.tailIndent > 0 ? max(0, width - style.tailIndent) : -style.tailIndent
        guard head != 0 || tail != 0 else { return (0, width) }
        let rtl = isRightToLeftParagraph(style, in: text, at: location)
        let left = rtl ? tail : head
        let right = rtl ? head : tail
        return (left, max(0, width - left - right))
    }

    /// 某一行绘制时的水平起点（相对 textRect 左边）：段落缩进 + 对齐偏移。
    /// `original` 为 frameLines 返回的原始行，`drawn` 为实际绘制的行（截断时为截断后的行）
    func lineOffsetX(original: CTLine, drawn: CTLine, in text: NSAttributedString, width: CGFloat) -> CGFloat {
        let box = lineBox(for: original, in: text, width: width)
        return box.x + CGFloat(CTLineGetPenOffsetForFlush(drawn, flushFactor, Double(box.width)))
    }

    /// 水平对齐对应的 flush factor（`.natural` 按界面方向）
    var flushFactor: CGFloat {
        switch textAlignment {
        case .center: return 0.5
        case .right: return 1.0
        case .natural: return effectiveUserInterfaceLayoutDirection == .rightToLeft ? 1.0 : 0.0
        default: return 0.0
        }
    }

    /// 计算基线修正用的字体（与绘制一致）
    var baselineFont: UIFont {
        let base = font ?? UIFont.systemFont(ofSize: 17)
        let scale = currentFontScale()
        return scale < 1 ? base.withSize(max(1, base.pointSize * scale)) : base
    }

    open override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let insetBounds = bounds.inset(by: textInsets)
        guard let text = storedText, text.length > 0 else {
            return super.textRect(forBounds: insetBounds, limitedToNumberOfLines: numberOfLines)
        }
        var textRect = insetBounds
        // 高度至少两行，避免约束过小时 CTFramesetterSuggestFrameSizeWithConstraints 返回 0
        textRect.size.height = max(baselineFont.lineHeight * CGFloat(max(2, numberOfLines)), insetBounds.height)
        let layout = displayLayout(for: text)
        let key = ZLTextLayout.SizeKey(width: textRect.width, height: textRect.height, numberOfLines: -1)
        let textSize: CGSize
        if let cached = layout.suggestedSizes[key] {
            textSize = cached
        } else {
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
                layout.framesetter, CFRange(location: 0, length: text.length), nil, textRect.size, nil)
            textSize = CGSize(width: ceil(suggested.width), height: ceil(suggested.height))
            layout.suggestedSizes[key] = textSize
        }
        if textSize.height < insetBounds.height {
            switch verticalAlignment {
            case .center: textRect.origin.y += floor((insetBounds.height - textSize.height) / 2)
            case .bottom: textRect.origin.y += insetBounds.height - textSize.height
            case .top: break
            }
        }
        return textRect
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let text = storedText, text.length > 0 else {
            return CGSize(width: textInsets.left + textInsets.right, height: textInsets.top + textInsets.bottom)
        }
        let maxValue: CGFloat = 100000
        let horizontalInsets = textInsets.left + textInsets.right
        let verticalInsets = textInsets.top + textInsets.bottom
        var width = size.width - horizontalInsets
        if width <= 0 || width > maxValue { width = maxValue }

        let layout = textLayout(for: text)
        let lineLimit = numberOfLines(forTextWidth: width)
        let key = ZLTextLayout.SizeKey(width: width, height: 0, numberOfLines: lineLimit)
        if let cached = layout.sizes[key] {
            didHitSizeCache()
            return CGSize(width: cached.width + horizontalInsets, height: cached.height + verticalInsets)
        }
        var range = CFRange(location: 0, length: text.length)
        var constraints = CGSize(width: width, height: maxValue)
        if lineLimit == 1 {
            constraints = CGSize(width: maxValue, height: maxValue)
        } else if lineLimit > 0 {
            // 只计算前 lineLimit 行
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: maxValue), transform: nil)
            let frame = CTFramesetterCreateFrame(layout.framesetter, CFRange(location: 0, length: 0), path, nil)
            if let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty {
                layout.lineCounts[width] = lines.count
                let lineRange = CTLineGetStringRange(lines[min(lineLimit, lines.count) - 1])
                range = CFRange(location: 0, length: lineRange.location + lineRange.length)
            }
        }
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(layout.framesetter, range, nil, constraints, nil)
        let fitted = CGSize(width: ceil(suggested.width), height: ceil(suggested.height))
        layout.sizes[key] = fitted
        return CGSize(width: fitted.width + horizontalInsets, height: fitted.height + verticalInsets)
    }

    open override var intrinsicContentSize: CGSize {
        guard storedText != nil else { return super.intrinsicContentSize }
        var width: CGFloat = 0
        if preferredMaxLayoutWidth > 0 {
            width = preferredMaxLayoutWidth
        } else if numberOfLines != 1 {
            width = bounds.width
        }
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    /// 某个位置对应的字符下标，不在文字上时返回 `NSNotFound`（与绘制位置一致：对齐方式、内边距、行数限制）
    @objc(characterIndexAtPoint:)
    open func characterIndex(at point: CGPoint) -> Int {
        guard let text = storedText, text.length > 0, bounds.contains(point) else { return NSNotFound }
        let lineLimit = numberOfLines
        let textRect = self.textRect(forBounds: bounds, limitedToNumberOfLines: lineLimit)
        let (lines, origins) = frameLines(for: text, in: textRect)
        guard !lines.isEmpty else { return NSNotFound }
        let count = lineLimit > 0 ? min(lineLimit, lines.count) : lines.count

        for lineIndex in 0..<count {
            let line = lines[lineIndex]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let baselineY = textRect.minY + textRect.height - origins[lineIndex].y
            if point.y < baselineY - ascent { return NSNotFound }     // 在这一行上方（行间距）
            if point.y > baselineY + descent + leading { continue }  // 在这一行下方
            let penOffset = lineOffsetX(original: line, drawn: line, in: text, width: textRect.width)
            let x = point.x - textInsets.left - penOffset
            guard x >= 0, x <= lineWidth else { return NSNotFound }
            var index = CTLineGetStringIndexForPosition(line, CGPoint(x: x, y: 0))
            guard index != kCFNotFound else { return NSNotFound }
            // 返回的是离该位置最近的插入点：位置在字符左半边时插入点在字符后面，需要回退一位
            let lineRange = CTLineGetStringRange(line)
            if index > lineRange.location, CTLineGetOffsetForStringIndex(line, index, nil) > x { index -= 1 }
            return min(index, text.length - 1)
        }
        return NSNotFound
    }

    /// 一段文字在 label 中的外接矩形（跨行时为各行的并集），不可见时为 `.zero`
    @objc(boundingRectForCharacterRange:)
    open func boundingRect(forCharacterRange range: NSRange) -> CGRect {
        return lineRects(forCharacterRange: range).reduce(CGRect.null) { $0.union($1) }.nonNullOrZero
    }

    /// 一段文字在每一行中的矩形
    func lineRects(forCharacterRange range: NSRange) -> [CGRect] {
        guard let text = storedText, text.length > 0, range.length > 0, bounds.width > 0 else { return [] }
        let lineLimit = numberOfLines
        let textRect = self.textRect(forBounds: bounds, limitedToNumberOfLines: lineLimit)
        let (lines, origins) = frameLines(for: text, in: textRect)
        let count = lineLimit > 0 ? min(lineLimit, lines.count) : lines.count
        var rects: [CGRect] = []
        for i in 0..<count {
            let line = lines[i]
            let cf = CTLineGetStringRange(line)
            let overlap = NSIntersectionRange(range, NSRange(location: cf.location, length: cf.length))
            guard overlap.length > 0 else { continue }
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            let baselineY = textRect.minY + textRect.height - origins[i].y
            let penOffset = lineOffsetX(original: line, drawn: line, in: text, width: textRect.width)
            // 行尾空白可能超出排版宽度（伸进右内边距），不计入矩形
            let visibleWidth = lineWidth - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
            let x1 = min(CTLineGetOffsetForStringIndex(line, overlap.location, nil), visibleWidth)
            let x2 = min(CTLineGetOffsetForStringIndex(line, NSMaxRange(overlap), nil), visibleWidth)
            guard x1 != x2 else { continue }
            rects.append(CGRect(x: textInsets.left + penOffset + min(x1, x2), y: baselineY - ascent,
                                width: abs(x2 - x1), height: ascent + descent))
        }
        return rects
    }

    /// 最后一行的截断：在行尾拼接截断符后按宽度截断（与绘制一致）
    func truncatedLine(for line: CTLine, in text: NSAttributedString, lineCount: Int,
                       width: Double) -> (line: CTLine, string: NSAttributedString)? {
        // 字号自适应缩小时使用缩小后的文字（与 frameLines 返回的行一致）
        let scale = currentFontScale()
        let text = displayText(for: text)
        let lastRange = CTLineGetStringRange(line)
        guard !(lastRange.length == 0 && lastRange.location == 0),
              lastRange.location + lastRange.length < text.length else { return nil }

        let mode: NSLineBreakMode = lineCount != 1 ? .byTruncatingTail : lineBreakMode
        if lineCount == 1 {
            return singleLineTruncation(start: lastRange.location, in: text, mode: mode, width: width, scale: scale)
        }
        var position = lastRange.location
        let type: CTLineTruncationType
        switch mode {
        case .byTruncatingHead:
            type = .start
        case .byTruncatingMiddle:
            type = .middle
            position += lastRange.length / 2
        default:
            type = .end
            position += lastRange.length - 1
        }

        let token = attributedTruncationToken.map { ZLAttributedLabel.scaledText($0, scale: scale) }
            ?? NSAttributedString(string: "\u{2026}", attributes: text.attributes(at: max(0, position), effectiveRange: nil))
        let tokenLine = CTLineCreateWithAttributedString(token as CFAttributedString)

        let truncationString = NSMutableAttributedString(
            attributedString: text.attributedSubstring(from: NSRange(location: lastRange.location, length: lastRange.length)))
        if lastRange.length > 0 {
            let lastChar = (truncationString.string as NSString).character(at: lastRange.length - 1)
            if let scalar = UnicodeScalar(lastChar), CharacterSet.newlines.contains(scalar) {
                truncationString.deleteCharacters(in: NSRange(location: lastRange.length - 1, length: 1))
            }
        }
        // 先拼接截断符：内容刚好放下时 CoreText 不会自己添加
        truncationString.append(token)
        let truncationLine = CTLineCreateWithAttributedString(truncationString as CFAttributedString)
        let result = CTLineCreateTruncatedLine(truncationLine, width, type, tokenLine) ?? tokenLine
        return (result, truncationString)
    }

    /// 单行截断：按整个段落（不是按词换行后的第一行）截断，与 UILabel 一致可以截断到字符；
    /// 头部 / 中间截断显示段落的结尾。后面还有其他段落时尾部截断强制显示截断符
    private func singleLineTruncation(start: Int, in text: NSAttributedString, mode: NSLineBreakMode,
                                      width: Double, scale: CGFloat) -> (line: CTLine, string: NSAttributedString) {
        let ns = text.string as NSString
        var end = start
        var contentsEnd = start
        ns.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd,
                             for: NSRange(location: start, length: 0))
        let hasMoreText = end < ns.length
        let source = NSMutableAttributedString(
            attributedString: text.attributedSubstring(from: NSRange(location: start, length: max(0, contentsEnd - start))))

        let type: CTLineTruncationType
        let tokenPosition: Int
        switch mode {
        case .byTruncatingHead:
            type = .start
            tokenPosition = start
        case .byTruncatingMiddle:
            type = .middle
            tokenPosition = start + source.length / 2
        default:
            type = .end
            tokenPosition = max(start, contentsEnd - 1)
        }
        let token = attributedTruncationToken.map { ZLAttributedLabel.scaledText($0, scale: scale) }
            ?? NSAttributedString(string: "\u{2026}",
                                  attributes: text.attributes(at: min(max(0, tokenPosition), text.length - 1), effectiveRange: nil))
        let tokenLine = CTLineCreateWithAttributedString(token as CFAttributedString)
        // 段落放得下但后面还有内容：先拼接截断符（与多行时一致）
        if type == .end && hasMoreText { source.append(token) }
        let sourceLine = CTLineCreateWithAttributedString(source as CFAttributedString)
        let result = CTLineCreateTruncatedLine(sourceLine, width, type, tokenLine) ?? tokenLine
        return (result, source)
    }

    /// 是否截断最后一行
    var truncatesLastLine: Bool {
        return lineBreakMode == .byTruncatingHead || lineBreakMode == .byTruncatingMiddle
            || lineBreakMode == .byTruncatingTail
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        invalidateAccessibilityElements()
        // 多行时高度取决于宽度：宽度变化后重新计算（Auto Layout 自适应高度）
        if bounds.width != lastLayoutWidth {
            lastLayoutWidth = bounds.width
            if numberOfLines != 1 && preferredMaxLayoutWidth <= 0 { invalidateIntrinsicContentSize() }
        }
    }
}
