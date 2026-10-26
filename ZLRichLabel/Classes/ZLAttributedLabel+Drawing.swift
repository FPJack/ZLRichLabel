//
//  ZLAttributedLabel+Drawing.swift
//  ZLRichLabel
//
//  ZLAttributedLabel 的绘制：CoreText 绘制文字，补充绘制背景色与删除线
//

import UIKit
import CoreText

extension ZLAttributedLabel {

    // MARK: 绘制

    open override func draw(_ rect: CGRect) {
        drawText(in: bounds)
    }

    open override func drawText(in rect: CGRect) {
        guard let text = storedText, text.length > 0, let context = UIGraphicsGetCurrentContext() else { return }
        let rendered = renderedText(text)
        let insetRect = rect.inset(by: textInsets)
        let textRect = self.textRect(forBounds: rect, limitedToNumberOfLines: numberOfLines)

        context.saveGState()
        defer { context.restoreGState() }
        context.textMatrix = .identity
        // 翻转为 CoreText 坐标（左下角为原点），再移动到 textRect
        context.translateBy(x: 0, y: insetRect.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: insetRect.minX, y: insetRect.height - textRect.minY - textRect.height)

        if let shadowColor = shadowColor, !isHighlighted {
            context.setShadow(offset: shadowOffset, blur: shadowRadius, color: shadowColor.cgColor)
        }

        let lines = drawingLines(for: rendered, in: textRect)
        drawBackgrounds(lines, in: context)
        for item in lines {
            context.textPosition = item.position
            CTLineDraw(item.line, context)
        }
        drawStrikethroughs(lines, in: context)
    }

    /// 绘制时的文字：高亮文字颜色、失活链接样式
    private func renderedText(_ text: NSAttributedString) -> NSAttributedString {
        let highlightColor = isHighlighted ? highlightedTextColor : nil
        let dimmed = tintAdjustmentMode == .dimmed && !links.isEmpty
        guard highlightColor != nil || dimmed else { return text }
        let mutable = NSMutableAttributedString(attributedString: text)
        if dimmed {
            for link in links where NSMaxRange(link.range) <= mutable.length {
                if let attrs = link.inactiveAttributes ?? inactiveLinkAttributes, !attrs.isEmpty {
                    mutable.addAttributes(attrs, range: link.range)
                }
            }
        }
        if let color = highlightColor {
            mutable.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: mutable.length))
        }
        return mutable
    }

    private struct DrawingLine {
        let line: CTLine
        /// CoreText 坐标中的绘制起点（基线）
        let position: CGPoint
    }

    private func drawingLines(for text: NSAttributedString, in textRect: CGRect) -> [DrawingLine] {
        let lines: [CTLine]
        let origins: [CGPoint]
        if text === storedText {
            (lines, origins) = frameLines(for: text, in: textRect)
        } else {
            // 临时样式（高亮 / 失活）：不替换排版缓存
            let scaled = ZLAttributedLabel.scaledText(text, scale: currentFontScale())
            let framesetter = CTFramesetterCreateWithAttributedString(scaled as CFAttributedString)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: scaled.length),
                                                 CGPath(rect: textRect, transform: nil), nil)
            lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
            var buffer = [CGPoint](repeating: .zero, count: lines.count)
            if !lines.isEmpty { CTFrameGetLineOrigins(frame, CFRange(location: 0, length: lines.count), &buffer) }
            origins = buffer
        }
        let count = numberOfLines > 0 ? min(numberOfLines, lines.count) : lines.count
        let fontDescender = baselineFont.descender
        var result: [DrawingLine] = []
        for i in 0..<count {
            var line = lines[i]
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, nil, &descent, nil)
            let box = lineBox(for: lines[i], in: text, width: textRect.width)
            if i == count - 1, truncatesLastLine,
               let truncated = truncatedLine(for: line, in: text, lineCount: count, width: Double(box.width)) {
                line = truncated.line
            }
            let penOffset = lineOffsetX(original: lines[i], drawn: line, in: text, width: textRect.width)
            result.append(DrawingLine(line: line, position: CGPoint(x: penOffset, y: origins[i].y - descent - fontDescender)))
        }
        return result
    }

    /// `.backgroundColor`（CoreText 不绘制）
    private func drawBackgrounds(_ lines: [DrawingLine], in context: CGContext) {
        for item in lines {
            for run in (CTLineGetGlyphRuns(item.line) as? [CTRun]) ?? [] {
                let attrs = CTRunGetAttributes(run) as NSDictionary
                guard let color = attrs[NSAttributedString.Key.backgroundColor.rawValue] as? UIColor,
                      CTRunGetGlyphCount(run) > 0 else { continue }
                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil))
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: item.position.x + position.x, y: item.position.y - descent,
                                    width: width, height: ascent + descent))
            }
        }
    }

    /// `.strikethroughStyle`（CoreText 不绘制）
    private func drawStrikethroughs(_ lines: [DrawingLine], in context: CGContext) {
        for item in lines {
            for run in (CTLineGetGlyphRuns(item.line) as? [CTRun]) ?? [] {
                let attrs = CTRunGetAttributes(run) as NSDictionary
                guard let style = (attrs[NSAttributedString.Key.strikethroughStyle.rawValue] as? NSNumber)?.intValue,
                      style != 0, CTRunGetGlyphCount(run) > 0 else { continue }
                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
                let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil))
                let runFont = (attrs[NSAttributedString.Key.font.rawValue] as? UIFont) ?? baselineFont
                let color = (attrs[NSAttributedString.Key.strikethroughColor.rawValue] as? UIColor)
                    ?? (attrs[NSAttributedString.Key.foregroundColor.rawValue] as? UIColor)
                    ?? textColor ?? .black
                let thickness = max(CTFontGetUnderlineThickness(runFont as CTFont), 1 / max(contentScaleFactor, 1))
                let isDouble = style & NSUnderlineStyle.double.rawValue == NSUnderlineStyle.double.rawValue
                let y = item.position.y + runFont.xHeight / 2
                let x = item.position.x + position.x
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(thickness)
                for offset in isDouble ? [-thickness, thickness] : [0] {
                    context.move(to: CGPoint(x: x, y: y + offset))
                    context.addLine(to: CGPoint(x: x + width, y: y + offset))
                }
                context.strokePath()
            }
        }
    }
}
