//
//  ZLRichLabel+Expand.swift
//  ZLRichLabel
//
//  ZLRichLabel 的展开 / 收起：实际行数、按钮样式、「展开」按钮的位置与点击
//

import UIKit
import CoreText

extension ZLRichLabel {

    // MARK: 展开 / 收起

    static let expandTokenKey = NSAttributedString.Key("ZLRichLabelExpandToken")

    /// 按钮富文本：先铺普通文本样式，再覆盖按钮自己的属性
    static func styledToken(_ token: NSAttributedString, baseStyle: ZLTextStyle) -> NSMutableAttributedString {
        let styled = NSMutableAttributedString(string: token.string, attributes: baseStyle)
        token.enumerateAttributes(in: NSRange(location: 0, length: token.length), options: []) { attrs, range, _ in
            styled.addAttributes(attrs, range: range)
        }
        return styled
    }

    /// 收起时的行数（即设置的 `numberOfLines`，展开时也不变）
    public var collapsedNumberOfLines: Int { return super.numberOfLines }

    /// 某个文字宽度下实际使用的行数：展开时为 0；设置了 `collapseThreshold` 且内容不超过它时为 0（完整显示）
    func effectiveNumberOfLines(forTextWidth width: CGFloat) -> Int {
        if isExpanded { return 0 }
        let collapsed = super.numberOfLines
        guard collapsed > 0, collapseThreshold > collapsed, width > 0,
              let attr = attributedText, attr.length > 0 else { return collapsed }
        return lineCount(of: attr, width: width) <= collapseThreshold ? 0 : collapsed
    }

    /// 切换展开状态并回调 `onExpandChanged`，与点击「展开 / 收起」的效果相同
    open func toggleExpanded() {
        isExpanded.toggle()
        onExpandChanged?(isExpanded)
    }

    @objc func handleExpandTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, !isExpanded, expandTokenRect.contains(gesture.location(in: self)) else { return }
        expandTokenTapped(wantsExpand: true)
    }

    /// 点击了「展开」（wantsExpand = true）或「收起」（false）按钮：
    /// 设置了 `onExpandTokenTap` 时交给外部处理，否则内部自动切换
    func expandTokenTapped(wantsExpand: Bool) {
        if let handler = onExpandTokenTap {
            handler(self, wantsExpand)
        } else {
            toggleExpanded()
        }
    }

    /// 计算是否被截断，以及「展开」按钮在 label 中的位置（与绘制的截断行一致）
    func layoutExpandToken() {
        isTruncated = false
        expandTokenRect = .zero
        let lineLimit = numberOfLines
        guard lineLimit > 0, let attr = attributedText, attr.length > 0, bounds.width > 0, bounds.height > 0 else { return }

        let textRect = self.textRect(forBounds: bounds, limitedToNumberOfLines: lineLimit)
        let (lines, origins) = frameLines(for: attr, in: textRect)
        guard !lines.isEmpty else { return }
        let count = min(lineLimit, lines.count)
        let lastLine = lines[count - 1]
        let lastRange = CTLineGetStringRange(lastLine)
        isTruncated = lastRange.location + lastRange.length < attr.length
        let box = lineBox(for: lastLine, in: attr, width: textRect.width)
        guard isTruncated, !isExpanded, expandToken != nil,
              let truncated = truncatedLine(for: lastLine, in: attr, lineCount: count, width: Double(box.width))
        else { return }

        let penOffset = lineOffsetX(original: lastLine, drawn: truncated.line, in: attr, width: textRect.width)
        let baselineY = textRect.minY + textRect.height - origins[count - 1].y

        var rect = CGRect.null
        for run in (CTLineGetGlyphRuns(truncated.line) as? [CTRun]) ?? [] {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            guard attrs[ZLRichLabel.expandTokenKey.rawValue] != nil, CTRunGetGlyphCount(run) > 0 else { continue }
            var position = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
            var ascent: CGFloat = 0
            var runDescent: CGFloat = 0
            let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &runDescent, nil))
            rect = rect.union(CGRect(x: textInsets.left + penOffset + position.x, y: baselineY - ascent,
                                     width: width, height: ascent + runDescent))
        }
        guard !rect.isNull else { return }
        // 适当扩大点击区域
        expandTokenRect = rect.insetBy(dx: -8, dy: -6)
    }
}
