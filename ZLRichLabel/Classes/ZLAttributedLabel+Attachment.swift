//
//  ZLAttributedLabel+Attachment.swift
//  ZLRichLabel
//
//  ZLAttributedLabel 的图片附件（NSTextAttachment）：
//  CoreText 不认识 `.attachment`，设置文字时给附件字符加上 CTRunDelegate 占位（宽度 / 上下高度来自附件 bounds），
//  绘制文字后在占位处画出图片。
//
//  - 尺寸：`attachment.bounds` 不为空时使用它（`origin.y` 为相对基线的偏移，负数往下），否则使用图片尺寸，底部对齐基线
//  - 图片：`attachment.image`，没有时使用 `image(forBounds:textContainer:characterIndex:)`（例如只设置了 contents）
//  - 模板图片（`.alwaysTemplate` / SF Symbols）按所在位置的文字颜色着色，因此也跟随高亮文字颜色、链接按下样式
//  - 字号自适应缩小时附件不缩放（与 ZLRichLabel 的内嵌 View 一致）
//

import UIKit
import CoreText

/// 附件占位的尺寸（CTRunDelegate 的 refCon）
final class ZLAttachmentRunMetrics {
    let ascent: CGFloat
    let descent: CGFloat
    let width: CGFloat

    init(ascent: CGFloat, descent: CGFloat, width: CGFloat) {
        self.ascent = ascent
        self.descent = descent
        self.width = width
    }
}

extension ZLAttributedLabel {

    static let ctRunDelegateKey = NSAttributedString.Key(kCTRunDelegateAttributeName as String)

    /// 附件的图片，没有时为 nil
    static func image(of attachment: NSTextAttachment, characterIndex: Int) -> UIImage? {
        if let image = attachment.image { return image }
        return attachment.image(forBounds: attachment.bounds, textContainer: nil, characterIndex: characterIndex)
    }

    /// 附件的绘制区域（相对基线，y 向上为正）：bounds 不为空时用 bounds，否则用图片尺寸
    static func bounds(of attachment: NSTextAttachment, image: UIImage?) -> CGRect {
        if attachment.bounds.width > 0, attachment.bounds.height > 0 { return attachment.bounds }
        return CGRect(origin: .zero, size: image?.size ?? .zero)
    }

    /// 给文字中的 NSTextAttachment 加上 CTRunDelegate 占位（已有 CTRunDelegate 的不处理）。没有附件时返回 false
    @discardableResult
    static func prepareTextAttachments(in text: NSMutableAttributedString) -> Bool {
        var found = false
        let full = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.attachment, in: full, options: []) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            found = true
            guard text.attribute(ctRunDelegateKey, at: range.location, effectiveRange: nil) == nil else { return }
            let image = self.image(of: attachment, characterIndex: range.location)
            let rect = bounds(of: attachment, image: image)
            let metrics = ZLAttachmentRunMetrics(ascent: max(0, rect.maxY), descent: max(0, -rect.minY), width: rect.width)
            if let delegate = makeRunDelegate(metrics) {
                text.addAttribute(ctRunDelegateKey, value: delegate, range: range)
            }
        }
        return found
    }

    /// 已加好占位的副本（没有附件时原样返回）
    static func preparingTextAttachments(in text: NSAttributedString) -> NSAttributedString {
        var hasAttachment = false
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length), options: []) { value, _, stop in
            if value is NSTextAttachment {
                hasAttachment = true
                stop.pointee = true
            }
        }
        guard hasAttachment else { return text }
        let mutable = NSMutableAttributedString(attributedString: text)
        prepareTextAttachments(in: mutable)
        return NSAttributedString(attributedString: mutable)
    }

    private static func makeRunDelegate(_ metrics: ZLAttachmentRunMetrics) -> CTRunDelegate? {
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { ref in
                Unmanaged<ZLAttachmentRunMetrics>.fromOpaque(ref).release()
            },
            getAscent: { ref in
                return Unmanaged<ZLAttachmentRunMetrics>.fromOpaque(ref).takeUnretainedValue().ascent
            },
            getDescent: { ref in
                return Unmanaged<ZLAttachmentRunMetrics>.fromOpaque(ref).takeUnretainedValue().descent
            },
            getWidth: { ref in
                return Unmanaged<ZLAttachmentRunMetrics>.fromOpaque(ref).takeUnretainedValue().width
            })
        let refCon = Unmanaged.passRetained(metrics).toOpaque()
        guard let delegate = CTRunDelegateCreate(&callbacks, refCon) else {
            Unmanaged<ZLAttachmentRunMetrics>.fromOpaque(refCon).release()
            return nil
        }
        return delegate
    }

    /// 在已翻转为 CoreText 坐标（y 向上）的 context 中绘制各行里的附件图片
    /// - Parameter lines: (行, 基线起点)
    func drawTextAttachments(_ lines: [(line: CTLine, position: CGPoint)], in context: CGContext) {
        for item in lines {
            for run in (CTLineGetGlyphRuns(item.line) as? [CTRun]) ?? [] {
                let attrs = CTRunGetAttributes(run) as NSDictionary
                guard let attachment = attrs[NSAttributedString.Key.attachment.rawValue] as? NSTextAttachment,
                      CTRunGetGlyphCount(run) > 0 else { continue }
                let index = CTRunGetStringRange(run).location
                guard var image = ZLAttributedLabel.image(of: attachment, characterIndex: index) else { continue }
                let rect = ZLAttributedLabel.bounds(of: attachment, image: image)
                guard rect.width > 0, rect.height > 0 else { continue }
                if image.renderingMode == .alwaysTemplate || image.isSymbolImage {
                    let color = (attrs[NSAttributedString.Key.foregroundColor.rawValue] as? UIColor) ?? textColor ?? .black
                    image = image.withTintColor(color, renderingMode: .alwaysOriginal)
                }
                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
                let frame = CGRect(x: item.position.x + position.x,
                                   y: item.position.y + rect.minY,
                                   width: rect.width, height: rect.height)
                // UIImage.draw 按 UIKit 坐标（y 向下）绘制：在图片区域内局部翻转回来
                context.saveGState()
                context.translateBy(x: 0, y: frame.minY + frame.maxY)
                context.scaleBy(x: 1, y: -1)
                image.draw(in: frame)
                context.restoreGState()
            }
        }
    }
}
