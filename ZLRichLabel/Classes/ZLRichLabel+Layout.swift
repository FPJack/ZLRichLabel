//
//  ZLRichLabel+Layout.swift
//  ZLRichLabel
//
//  ZLRichLabel 的布局：自适应高度、展开时的行数、RTL 对齐、内嵌 View 的位置
//

import UIKit
import CoreText

extension ZLRichLabel {

    open override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != richLastLayoutWidth {
            richLastLayoutWidth = bounds.width
            // 宽度变化后高度可能变化（Auto Layout 自适应高度）
            invalidateIntrinsicContentSize()
        }
        layoutAttachmentViews()
        layoutExpandToken()
        if hasSelection { updateSelectionAppearance() }
    }

    /// 支持 Auto Layout 自适应高度：宽度由约束决定，高度根据内容计算
    open override var intrinsicContentSize: CGSize {
        let width = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : bounds.width
        guard width > 0, attributedText != nil else { return super.intrinsicContentSize }
        let size = sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(size.height))
    }

    open override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        intrinsicSizeObserver?()
    }

    /// 展开时读取为 0（显示全部）；设置的值保存为收起时的行数（`collapsedNumberOfLines`）。
    /// 设置了 `collapseThreshold` 且内容（按当前宽度）不超过它时也读取为 0
    open override var numberOfLines: Int {
        get { return effectiveNumberOfLines(forTextWidth: bounds.width - textInsets.left - textInsets.right) }
        set {
            super.numberOfLines = newValue
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// `.natural` 默认按界面方向对齐，阿拉伯语 / 希伯来语等 RTL 文本在 LTR 界面中会错误地靠左。
    /// 这里把 `.natural` 按内容的书写方向解析为 `.left` / `.right`
    open override var textAlignment: NSTextAlignment {
        get {
            let value = super.textAlignment
            guard value == .natural else { return value }
            return isRightToLeft ? .right : .left
        }
        set {
            super.textAlignment = newValue
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// 与 ZLAttributedLabel 的绘制逻辑保持一致，计算自定义 View 的位置
    private func layoutAttachmentViews() {
        // 外部直接修改了 View 的尺寸（例如点击后展开）：先更新占位尺寸再布局
        let resized = externallyResizedAttachments()
        if !resized.isEmpty { applyAttachmentSizes(resized) }

        attachments.values.forEach { $0.view.isHidden = true }
        guard !attachments.isEmpty,
              let attr = attributedText, attr.length > 0,
              bounds.width > 0, bounds.height > 0 else { return }

        let textRect = self.textRect(forBounds: bounds, limitedToNumberOfLines: numberOfLines)
        let (lines, origins) = frameLines(for: attr, in: textRect)
        guard !lines.isEmpty else { return }

        let count = numberOfLines > 0 ? min(numberOfLines, lines.count) : lines.count

        let truncateLastLine = lineBreakMode == .byTruncatingHead
            || lineBreakMode == .byTruncatingMiddle
            || lineBreakMode == .byTruncatingTail
        let fontDescender = (font ?? UIFont.systemFont(ofSize: 17)).descender

        for lineIndex in 0..<count {
            var line = lines[lineIndex]
            var lineString: NSAttributedString = attr

            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, nil, &descent, nil)

            let box = lineBox(for: lines[lineIndex], in: attr, width: textRect.width)
            if lineIndex == count - 1 && truncateLastLine,
               let truncated = truncatedLine(for: line, in: attr, lineCount: count, width: Double(box.width)) {
                line = truncated.line
                lineString = truncated.string
            }

            let penOffset = lineOffsetX(original: lines[lineIndex], drawn: line, in: attr, width: textRect.width)
            let baselineCT = origins[lineIndex].y - descent - fontDescender
            let baselineY = textRect.minY + textRect.height - baselineCT
            let string = lineString.string as NSString

            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { continue }
            for run in runs {
                let attrs = CTRunGetAttributes(run) as NSDictionary
                guard let id = attrs[ZLRichLabel.attachmentKey.rawValue] as? Int,
                      let attachment = attachments[id] else { continue }
                let range = CTRunGetStringRange(run)
                guard range.location >= 0, range.location < string.length,
                      string.character(at: range.location) == ZLRichLabel.attachmentChar,
                      CTRunGetGlyphCount(run) > 0 else { continue }

                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)

                attachment.view.frame = CGRect(x: textInsets.left + penOffset + position.x,
                                               y: baselineY - attachment.ascent,
                                               width: attachment.size.width,
                                               height: attachment.size.height)
                attachment.appliedSize = attachment.view.bounds.size
                attachment.view.isHidden = false
            }
        }
    }
}
