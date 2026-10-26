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
//    在绘制文字之前按每一行画出圆角背景和边框；跨行时每行一段。
//    kern 总是加宽字形右侧，所以按「视觉位置」加：右侧加在胶囊内视觉上最右的字符上，左侧加在胶囊左边紧挨着的字符上，
//    从右到左（阿拉伯语 / 希伯来语）和双向混排时同样正确
//  - 渐变文字：原文字颜色设为透明，文字绘制之后用字形作为裁剪区域填充渐变；跨行时每行一段
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

/// 一个段落中字符的视觉顺序（从左到右）：整段排成一行后按字形位置得到（双向文本的重排在这里体现）。
/// 用于按视觉位置给胶囊预留内边距：kern 总是加宽字形右侧
struct ZLVisualOrder {
    let isRightToLeft: Bool
    /// 从左到右的字符下标（整个文本中的下标，同一字符的多个字形只记一次）
    private(set) var order: [Int] = []
    /// 字符 → 在 order 中的位置
    private var position: [Int: Int] = [:]

    init(text: NSAttributedString, paragraph: NSRange, isRightToLeft: Bool) {
        self.isRightToLeft = isRightToLeft
        guard paragraph.length > 0 else { return }
        let line = CTLineCreateWithAttributedString(text.attributedSubstring(from: paragraph))
        var glyphs: [(x: CGFloat, index: Int)] = []
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            for i in 0..<count { glyphs.append((positions[i].x, indices[i] + paragraph.location)) }
        }
        // 稳定排序：位置相同的字形（组合符号等）保持原有顺序
        for glyph in glyphs.enumerated().sorted(by: { ($0.element.x, $0.offset) < ($1.element.x, $1.offset) }).map({ $0.element })
        where position[glyph.index] == nil {
            position[glyph.index] = order.count
            order.append(glyph.index)
        }
    }

    /// 一段文字的视觉边缘：视觉上最右的字符，以及左边紧挨着的字符（没有时为 nil）
    func edges(of range: NSRange) -> (right: Int, leftNeighbor: Int?)? {
        var minPosition = Int.max
        var maxPosition = Int.min
        for index in range.location..<NSMaxRange(range) {
            guard let p = position[index] else { continue }
            minPosition = min(minPosition, p)
            maxPosition = max(maxPosition, p)
        }
        guard maxPosition >= 0, minPosition != Int.max else { return nil }
        let neighbor = minPosition > 0 ? order[minPosition - 1] : nil
        // 左边的字符在胶囊内（胶囊被其它方向的文字隔开，极少见）：视为没有
        if let n = neighbor, NSLocationInRange(n, range) { return (order[maxPosition], nil) }
        return (order[maxPosition], neighbor)
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
        // 每个段落的视觉顺序（加 kern 之前计算；kern 不改变顺序）
        var orders: [Int: ZLVisualOrder] = [:]
        func visualOrder(at location: Int) -> ZLVisualOrder {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            if let order = orders[paragraph.location] { return order }
            let style = text.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            let order = ZLVisualOrder(text: text, paragraph: paragraph,
                                      isRightToLeft: isRightToLeftParagraph(style, in: text, at: paragraph.location))
            orders[paragraph.location] = order
            return order
        }
        func isNewline(_ index: Int) -> Bool {
            guard let scalar = UnicodeScalar(string.character(at: index)) else { return false }
            return CharacterSet.newlines.contains(scalar)
        }

        for (range, background) in backgrounds {
            hasTextBackgrounds = true
            text.addAttribute(ZLRichLabel.backgroundOccurrenceKey,
                              value: ZLDecorationOccurrence(range: range, background: background, gradient: nil),
                              range: range)
            let order = visualOrder(at: range.location)
            let edges = order.edges(of: range)
            // 右侧：加在胶囊内视觉上最右的字符上（kern 加宽字形右侧）
            if let right = edges?.right ?? Optional(NSMaxRange(range) - 1) {
                addKern(background.padding.right + background.margin, at: right, in: text)
            }
            // 左侧：加在胶囊左边紧挨着的字符上
            let leading = background.padding.left + background.margin
            if let neighbor = edges?.leftNeighbor, !isNewline(neighbor) {
                addKern(leading, at: neighbor, in: text)
            } else if !order.isRightToLeft {
                // 从左到右的段落中位于最左（段落开头）：用首行缩进
                let paragraphRange = string.paragraphRange(for: NSRange(location: range.location, length: 0))
                let current = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                let style = (current?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                style.firstLineHeadIndent += leading
                text.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            }
            // 从右到左的段落中位于最左（段落末尾）：左边是行尾的空白，背景直接画在空白里，不需要预留
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

    /// 绘制用的行（与基类绘制一致：最后一行按截断后的内容）
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
        /// 文字视觉上的右边界（不含最右字符上的 kern，即预留的内边距 / 间距）
        var inkMaxX: CGFloat
        var isRightToLeft: Bool
        /// 段内某个 run 的属性（按下高亮可能临时替换了装饰属性）
        var attributes: NSDictionary
        /// `.baselineOffset`（向上为正）：CoreText 会把字形整体上移，但 run 的 ascent / descent 不包含它，
        /// 背景和渐变区域需要跟着移动，否则文字在胶囊里偏上 / 偏下
        var baselineOffset: CGFloat = 0
    }

    func decorationLines() -> [DecorationLine] {
        guard let attr = attributedText, attr.length > 0, bounds.width > 0 else { return [] }
        let textRect = self.textRect(forBounds: bounds, limitedToNumberOfLines: numberOfLines)
        let (lines, origins) = frameLines(for: attr, in: textRect)
        guard !lines.isEmpty else { return [] }
        let count = numberOfLines > 0 ? min(numberOfLines, lines.count) : lines.count
        let truncates = lineBreakMode == .byTruncatingHead || lineBreakMode == .byTruncatingMiddle
            || lineBreakMode == .byTruncatingTail

        var result: [DecorationLine] = []
        for i in 0..<count {
            var line = lines[i]
            let baselineY = textRect.minY + textRect.height - origins[i].y
            var offset = 0
            let box = lineBox(for: lines[i], in: attr, width: textRect.width)
            if i == count - 1, truncates,
               let truncated = truncatedLine(for: line, in: attr, lineCount: count, width: Double(box.width)) {
                line = truncated.line
                offset = CTLineGetStringRange(lines[i]).location
            }
            let penOffset = lineOffsetX(original: lines[i], drawn: line, in: attr, width: textRect.width)
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
            var advances = [CGSize](repeating: .zero, count: glyphCount)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            var indices = [CFIndex](repeating: 0, count: glyphCount)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil))
            let minX = positions.map { $0.x }.min() ?? 0
            let cf = CTRunGetStringRange(run)
            let range = NSRange(location: cf.location + line.stringOffset, length: cf.length)
            let rtl = CTRunGetStatus(run).contains(.rightToLeft)
            let baselineOffset = CGFloat((attrs[NSAttributedString.Key.baselineOffset.rawValue] as? NSNumber)?.doubleValue ?? 0)
            // 每个字符的字形右边界减去它的 kern：kern 加宽的是字形右侧
            var clusterMax: [CFIndex: CGFloat] = [:]
            for i in 0..<glyphCount {
                clusterMax[indices[i]] = max(clusterMax[indices[i]] ?? -.greatestFiniteMagnitude, positions[i].x + advances[i].width)
            }
            let inkMaxX = clusterMax.map { index, maxX in maxX - kern(atLineIndex: index, in: line) }.max() ?? (minX + width)

            if let index = result.firstIndex(where: { $0.occurrence === occurrence }) {
                result[index].runs.append(run)
                result[index].minX = min(result[index].minX, minX)
                result[index].maxX = max(result[index].maxX, minX + width)
                result[index].inkMaxX = max(result[index].inkMaxX, inkMaxX)
                result[index].ascent = max(result[index].ascent, ascent)
                result[index].descent = max(result[index].descent, descent)
                result[index].range = NSUnionRange(result[index].range, range)
            } else {
                result.append(DecorationSegment(occurrence: occurrence, runs: [run], minX: minX, maxX: minX + width,
                                                ascent: ascent, descent: descent, range: range, inkMaxX: inkMaxX,
                                                isRightToLeft: rtl, attributes: attrs, baselineOffset: baselineOffset))
            }
        }
        return result
    }

    /// 行内某个字符（下标相对这一行的字符串）上的 kern；截断行末尾的截断符不在正文中，返回 0
    private func kern(atLineIndex index: CFIndex, in line: DecorationLine) -> CGFloat {
        let location = index + line.stringOffset
        guard let text = attributedText, location >= 0, location < text.length else { return 0 }
        // 只会查询带装饰的字符（截断符不带装饰），截断行的字符串是原文从行首开始的子串，加上偏移即为原文下标
        return CGFloat((text.attribute(.kern, at: location, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0)
    }

    private func drawBackgrounds(_ lines: [DecorationLine], in context: CGContext) {
        for line in lines {
            for segment in segments(in: line, key: ZLRichLabel.backgroundOccurrenceKey) {
                // 按下高亮可以替换 .zlBackground（例如换成更深的颜色）
                let style = (segment.attributes[NSAttributedString.Key.zlBackground.rawValue] as? ZLTextBackground)
                    ?? segment.occurrence.background
                guard let background = style else { continue }
                let padding = background.padding
                // 视觉最右字符上的 kern 可能不只是自己的 padding.right + margin（紧挨着的下一个胶囊的
                // padding.left + margin、原文自带的 kern 也在上面），所以用去掉 kern 的文字右边界再加上 padding.right
                let left = segment.minX - padding.left
                let right = segment.inkMaxX + padding.right
                var frame = CGRect(x: line.originX + left,
                                   y: line.baselineY - segment.baselineOffset - segment.ascent - padding.top,
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
                let rect = CGRect(x: line.originX + segment.minX, y: line.baselineY - segment.baselineOffset - segment.ascent,
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
