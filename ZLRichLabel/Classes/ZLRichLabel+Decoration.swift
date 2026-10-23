//
//  ZLRichLabel+Decoration.swift
//  ZLRichLabel
//
//  文字装饰：胶囊背景（圆角背景 / 边框 / 内边距）与渐变文字，由 label 自己绘制。
//
//  用法：给一段文字加上属性即可（规则 handler、tagStyles、style 中都可以用）
//
//  ```swift
//  ctx.addAttributes([.zlBackground: ZLTextBackground(fillColor: .systemBlue.withAlphaComponent(0.12))])
//  label.tagStyles = ["code": [.zlBackground: ZLTextBackground.code]]
//  ctx.addAttributes([.zlGradient: ZLTextGradient(colors: [.systemPink, .systemOrange])])
//  ```
//
//  实现：
//  - 胶囊背景用 kern 在文字两侧预留内边距（只改属性，不插入字符，展示文字 / 原文 / 点击 / 选中的下标都不变），
//    在 TTT 绘制文字之前按每一行画出圆角背景和边框；跨行时每行一段
//  - 渐变文字：原文字颜色设为透明，TTT 绘制之后用字形作为裁剪区域填充渐变；跨行时每行一段
//

import UIKit
import CoreText

// MARK: - 属性

public extension NSAttributedString.Key {
    /// 胶囊背景，值为 `ZLTextBackground`
    static let zlBackground = NSAttributedString.Key("ZLRichTextBackground")
    /// 渐变文字，值为 `ZLTextGradient`
    static let zlGradient = NSAttributedString.Key("ZLRichTextGradient")
}

/// 胶囊背景：圆角背景、边框、内边距
///
/// - 水平内边距和 `margin` 会占用排版空间（不会和相邻文字重叠）
/// - 垂直内边距只影响绘制，不改变行高；较大时请配合 `lineSpacing` 使用，避免与上下行重叠
@objcMembers
public final class ZLTextBackground: NSObject {
    /// 填充色，nil 时不填充
    public var fillColor: UIColor?
    /// 边框颜色，nil 时没有边框
    public var strokeColor: UIColor?
    /// 边框宽度
    public var lineWidth: CGFloat
    /// 圆角；小于 0 时为高度的一半（两端是半圆的胶囊）
    public var cornerRadius: CGFloat
    /// 内边距：文字到背景边缘的距离
    public var padding: UIEdgeInsets
    /// 背景外侧与相邻文字的水平间距
    public var margin: CGFloat

    public init(fillColor: UIColor? = nil,
                strokeColor: UIColor? = nil,
                lineWidth: CGFloat = 1,
                cornerRadius: CGFloat = -1,
                padding: UIEdgeInsets = UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6),
                margin: CGFloat = 2) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.margin = margin
        super.init()
    }

    /// Objective-C 便捷方法
    @objc(backgroundWithFillColor:strokeColor:cornerRadius:)
    public static func background(fillColor: UIColor?, strokeColor: UIColor?, cornerRadius: CGFloat) -> ZLTextBackground {
        return ZLTextBackground(fillColor: fillColor, strokeColor: strokeColor, cornerRadius: cornerRadius)
    }

    /// 预设：话题胶囊（浅色填充，两端半圆）
    public static func capsule(_ color: UIColor) -> ZLTextBackground {
        return ZLTextBackground(fillColor: color.withAlphaComponent(0.12), cornerRadius: -1)
    }

    /// 预设：行内代码（灰色背景 + 细边框 + 小圆角）
    public static var code: ZLTextBackground {
        return ZLTextBackground(fillColor: UIColor.secondarySystemFill, strokeColor: UIColor.separator,
                                lineWidth: 0.5, cornerRadius: 4,
                                padding: UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4), margin: 1)
    }
}

/// 渐变文字
@objcMembers
public final class ZLTextGradient: NSObject {
    /// 渐变颜色（至少 2 个）
    public var colors: [UIColor]
    /// 每个颜色的位置（0~1），nil 时均匀分布
    public var locations: [CGFloat]?
    /// 起点 / 终点（单位坐标，相对每一行这段文字的矩形），默认从左到右
    public var startPoint: CGPoint
    public var endPoint: CGPoint

    public init(colors: [UIColor], locations: [CGFloat]? = nil,
                startPoint: CGPoint = CGPoint(x: 0, y: 0.5), endPoint: CGPoint = CGPoint(x: 1, y: 0.5)) {
        self.colors = colors
        self.locations = locations
        self.startPoint = startPoint
        self.endPoint = endPoint
        super.init()
    }

    /// Objective-C 便捷方法：从左到右的渐变
    @objc(gradientWithColors:)
    public static func gradient(colors: [UIColor]) -> ZLTextGradient {
        return ZLTextGradient(colors: colors)
    }
}

// MARK: - 内部：每一处装饰

/// 一处装饰（同一个属性值在一个命中 / 一段普通文字里的连续范围）
final class ZLDecorationOccurrence: NSObject {
    let range: NSRange
    let background: ZLTextBackground?
    let gradient: ZLTextGradient?

    init(range: NSRange, background: ZLTextBackground?, gradient: ZLTextGradient?) {
        self.range = range
        self.background = background
        self.gradient = gradient
        super.init()
    }
}

extension ZLRichLabel {

    /// Objective-C 使用：胶囊背景属性名（等同于 Swift 的 `.zlBackground`），值为 `ZLTextBackground`
    @objc public static let textBackgroundAttributeName: NSAttributedString.Key = .zlBackground
    /// Objective-C 使用：渐变文字属性名（等同于 Swift 的 `.zlGradient`），值为 `ZLTextGradient`
    @objc public static let textGradientAttributeName: NSAttributedString.Key = .zlGradient

    static let backgroundOccurrenceKey = NSAttributedString.Key("ZLRichLabelBackgroundOccurrence")
    static let gradientOccurrenceKey = NSAttributedString.Key("ZLRichLabelGradientOccurrence")

    /// 渲染时调用：给每一处装饰编号、用 kern 预留胶囊的水平内边距、隐藏渐变文字的原颜色。
    /// `boundaries` 为各命中的范围：相邻命中即使使用同一个属性值也是两个独立的胶囊
    func prepareDecorations(in text: NSMutableAttributedString, boundaries: [NSRange]) {
        hasTextBackgrounds = false
        hasTextGradients = false
        let full = NSRange(location: 0, length: text.length)
        guard full.length > 0 else { return }

        var cuts = Set<Int>()
        for range in boundaries {
            cuts.insert(range.location)
            cuts.insert(NSMaxRange(range))
        }
        func split(_ range: NSRange) -> [NSRange] {
            let inner = cuts.filter { $0 > range.location && $0 < NSMaxRange(range) }.sorted()
            var result: [NSRange] = []
            var start = range.location
            for cut in inner + [NSMaxRange(range)] {
                result.append(NSRange(location: start, length: cut - start))
                start = cut
            }
            return result
        }

        var backgrounds: [(NSRange, ZLTextBackground)] = []
        text.enumerateAttribute(.zlBackground, in: full, options: []) { value, range, _ in
            guard let background = value as? ZLTextBackground else { return }
            split(range).forEach { backgrounds.append(($0, background)) }
        }
        var gradients: [(NSRange, ZLTextGradient)] = []
        text.enumerateAttribute(.zlGradient, in: full, options: []) { value, range, _ in
            guard let gradient = value as? ZLTextGradient, gradient.colors.count > 0 else { return }
            split(range).forEach { gradients.append(($0, gradient)) }
        }

        let string = text.string as NSString
        for (range, background) in backgrounds {
            hasTextBackgrounds = true
            text.addAttribute(ZLRichLabel.backgroundOccurrenceKey,
                              value: ZLDecorationOccurrence(range: range, background: background, gradient: nil),
                              range: range)
            // 后侧：加在最后一个字符上
            let last = NSMaxRange(range) - 1
            addKern(background.padding.right + background.margin, at: last, in: text)
            // 前侧：加在前一个字符上；位于段落开头时用首行缩进
            let previous = range.location - 1
            let leading = background.padding.left + background.margin
            if previous >= 0, let scalar = UnicodeScalar(string.character(at: previous)),
               !CharacterSet.newlines.contains(scalar) {
                addKern(leading, at: previous, in: text)
            } else {
                let paragraphRange = string.paragraphRange(for: NSRange(location: range.location, length: 0))
                let current = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                let style = (current?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                style.firstLineHeadIndent += leading
                text.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            }
        }
        for (range, gradient) in gradients {
            hasTextGradients = true
            text.addAttribute(ZLRichLabel.gradientOccurrenceKey,
                              value: ZLDecorationOccurrence(range: range, background: nil, gradient: gradient),
                              range: range)
            text.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
        }
    }

    private func addKern(_ value: CGFloat, at index: Int, in text: NSMutableAttributedString) {
        guard value != 0, index >= 0, index < text.length else { return }
        let current = (text.attribute(.kern, at: index, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
        text.addAttribute(.kern, value: current + Double(value), range: NSRange(location: index, length: 1))
    }

    // MARK: 绘制

    /// 由 `drawText(in:)` 调用：文字之前画胶囊背景，文字之后画渐变
    func drawDecoratedText(in rect: CGRect, drawText: (CGRect) -> Void) {
        let lines = (hasTextBackgrounds || hasTextGradients) ? decorationLines() : []
        if hasTextBackgrounds, let context = UIGraphicsGetCurrentContext() {
            drawBackgrounds(lines, in: context)
        }
        drawText(rect)
        if hasTextGradients, let context = UIGraphicsGetCurrentContext() {
            drawGradients(lines, in: context)
        }
    }

    /// 绘制用的行（与 TTT 一致：最后一行按截断后的内容）
    struct DecorationLine {
        let line: CTLine
        /// 行内字符下标相对整个文本的偏移（截断行的字符串是从行首开始的子串）
        let stringOffset: Int
        let originX: CGFloat
        let baselineY: CGFloat
    }

    /// 一行中属于同一处装饰的一段
    struct DecorationSegment {
        let occurrence: ZLDecorationOccurrence
        var runs: [CTRun]
        var minX: CGFloat
        var maxX: CGFloat
        var ascent: CGFloat
        var descent: CGFloat
        var range: NSRange
        var isRightToLeft: Bool
        /// 段内某个 run 的属性（按下高亮可能临时替换了装饰属性）
        var attributes: NSDictionary
    }

    func decorationLines() -> [DecorationLine] {
        guard let attr = attributedText, attr.length > 0, bounds.width > 0 else { return [] }
        let textRect = self.textRect(forBounds: bounds, limitedToNumberOfLines: numberOfLines)
        let (lines, origins) = frameLines(for: attr, in: textRect)
        guard !lines.isEmpty else { return [] }
        let count = numberOfLines > 0 ? min(numberOfLines, lines.count) : lines.count
        let truncates = lineBreakMode == .byTruncatingHead || lineBreakMode == .byTruncatingMiddle
            || lineBreakMode == .byTruncatingTail
        let fontDescender = (font ?? UIFont.systemFont(ofSize: 17)).descender
        let width = Double(textRect.width)

        var result: [DecorationLine] = []
        for i in 0..<count {
            var line = lines[i]
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, nil, &descent, nil)
            let baselineY = textRect.minY + textRect.height - (origins[i].y - descent - fontDescender)
            var offset = 0
            if i == count - 1, truncates, let truncated = truncatedLine(for: line, in: attr, lineCount: count, width: width) {
                line = truncated.line
                offset = CTLineGetStringRange(lines[i]).location
            }
            let penOffset = CGFloat(CTLineGetPenOffsetForFlush(line, flushFactor, width))
            result.append(DecorationLine(line: line, stringOffset: offset,
                                         originX: textInsets.left + penOffset, baselineY: baselineY))
        }
        return result
    }

    /// 按装饰把一行中的 run 分段
    func segments(in line: DecorationLine, key: NSAttributedString.Key) -> [DecorationSegment] {
        guard let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] else { return [] }
        var result: [DecorationSegment] = []
        for run in runs {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            guard let occurrence = attrs[key.rawValue] as? ZLDecorationOccurrence else { continue }
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil))
            let minX = positions.map { $0.x }.min() ?? 0
            let cf = CTRunGetStringRange(run)
            let range = NSRange(location: cf.location + line.stringOffset, length: cf.length)
            let rtl = CTRunGetStatus(run).contains(.rightToLeft)

            if let index = result.firstIndex(where: { $0.occurrence === occurrence }) {
                result[index].runs.append(run)
                result[index].minX = min(result[index].minX, minX)
                result[index].maxX = max(result[index].maxX, minX + width)
                result[index].ascent = max(result[index].ascent, ascent)
                result[index].descent = max(result[index].descent, descent)
                result[index].range = NSUnionRange(result[index].range, range)
            } else {
                result.append(DecorationSegment(occurrence: occurrence, runs: [run], minX: minX, maxX: minX + width,
                                                ascent: ascent, descent: descent, range: range,
                                                isRightToLeft: rtl, attributes: attrs))
            }
        }
        return result
    }

    private func drawBackgrounds(_ lines: [DecorationLine], in context: CGContext) {
        for line in lines {
            for segment in segments(in: line, key: ZLRichLabel.backgroundOccurrenceKey) {
                // 按下高亮可以替换 .zlBackground（例如换成更深的颜色）
                let style = (segment.attributes[NSAttributedString.Key.zlBackground.rawValue] as? ZLTextBackground)
                    ?? segment.occurrence.background
                guard let background = style else { continue }
                let occurrence = segment.occurrence.range
                let containsLast = NSLocationInRange(NSMaxRange(occurrence) - 1, segment.range)
                let padding = background.padding

                // 最后一个字符的 kern 包含在 run 宽度里，它可能不只是自己的 padding.right + margin：
                // 紧挨着的下一个胶囊的 padding.left + margin、原文自带的 kern 也加在这个字符上。
                // 所以按实际 kern 算出文字结束的位置，再加上自己的 padding.right
                var left = segment.minX - padding.left
                var right = segment.maxX + padding.right
                if containsLast {
                    let last = NSMaxRange(occurrence) - 1
                    let text = attributedText
                    let kern = (last >= 0 && last < (text?.length ?? 0)
                        ? text?.attribute(.kern, at: last, effectiveRange: nil) as? NSNumber : nil)
                        .map { CGFloat($0.doubleValue) } ?? 0
                    if segment.isRightToLeft {
                        left = segment.minX + kern - padding.right
                    } else {
                        right = segment.maxX - kern + padding.right
                    }
                }
                var frame = CGRect(x: line.originX + left,
                                   y: line.baselineY - segment.ascent - padding.top,
                                   width: right - left,
                                   height: segment.ascent + segment.descent + padding.top + padding.bottom)
                // 位于折行开头 / 结尾时不超出 label
                frame = frame.intersection(bounds)
                guard !frame.isNull, frame.width > 0, frame.height > 0 else { continue }

                let inset = (background.strokeColor == nil ? 0 : background.lineWidth / 2)
                let pathRect = frame.insetBy(dx: inset, dy: inset)
                let radius = background.cornerRadius < 0 ? pathRect.height / 2 : min(background.cornerRadius, pathRect.height / 2)
                let path = UIBezierPath(roundedRect: pathRect, cornerRadius: radius)
                context.saveGState()
                if let fill = background.fillColor?.resolvedColor(with: traitCollection) {
                    context.setFillColor(fill.cgColor)
                    context.addPath(path.cgPath)
                    context.fillPath()
                }
                if let stroke = background.strokeColor?.resolvedColor(with: traitCollection), background.lineWidth > 0 {
                    context.setStrokeColor(stroke.cgColor)
                    context.setLineWidth(background.lineWidth)
                    context.addPath(path.cgPath)
                    context.strokePath()
                }
                context.restoreGState()
            }
        }
    }

    private func drawGradients(_ lines: [DecorationLine], in context: CGContext) {
        for line in lines {
            for segment in segments(in: line, key: ZLRichLabel.gradientOccurrenceKey) {
                guard let gradient = segment.occurrence.gradient else { continue }
                let colors = gradient.colors.map { $0.resolvedColor(with: traitCollection).cgColor }
                let cgColors = (colors.count == 1 ? colors + colors : colors) as CFArray
                let locations = gradient.locations.flatMap { $0.count == colors.count ? $0 : nil }
                guard let cgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors,
                                                  locations: locations) else { continue }

                // 文字矩形（label 坐标系）
                let rect = CGRect(x: line.originX + segment.minX, y: line.baselineY - segment.ascent,
                                  width: segment.maxX - segment.minX, height: segment.ascent + segment.descent)
                // 字形轮廓作为裁剪区域：CoreText 坐标（基线为原点、y 向上）→ label 坐标
                let toLabel = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: line.originX, ty: line.baselineY)
                let clip = CGMutablePath()
                for run in segment.runs {
                    let attrs = CTRunGetAttributes(run) as NSDictionary
                    guard attrs[ZLRichLabel.attachmentKey.rawValue] == nil,
                          let fontValue = attrs[kCTFontAttributeName as String] else { continue }
                    let font = fontValue as! CTFont // swiftlint:disable:this force_cast
                    let count = CTRunGetGlyphCount(run)
                    var glyphs = [CGGlyph](repeating: 0, count: count)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                    CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                    for i in 0..<count {
                        var transform = CGAffineTransform(translationX: positions[i].x, y: positions[i].y)
                        if let path = CTFontCreatePathForGlyph(font, glyphs[i], &transform) {
                            clip.addPath(path, transform: toLabel)
                        }
                    }
                }
                guard !clip.isEmpty else { continue }
                func point(_ unit: CGPoint) -> CGPoint {
                    return CGPoint(x: rect.minX + unit.x * rect.width, y: rect.minY + unit.y * rect.height)
                }
                context.saveGState()
                context.addPath(clip)
                context.clip()
                context.drawLinearGradient(cgGradient, start: point(gradient.startPoint), end: point(gradient.endPoint),
                                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                context.restoreGState()
            }
        }
    }
}
