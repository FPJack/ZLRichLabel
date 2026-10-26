//
//  ZLAttributedLabel+Link.swift
//  ZLRichLabel
//
//  ZLAttributedLabel 的链接与触摸：添加 / 查找链接、自动识别、按下样式、点击与长按
//

import UIKit
import CoreText

extension ZLAttributedLabel {

    /// 添加链接（`link.attributes` 不为空时应用到文字上）
    @discardableResult
    open func addLink(_ link: ZLLabelLink) -> ZLLabelLink {
        if let attrs = link.attributes, !attrs.isEmpty, let text = inactiveText ?? storedText,
           NSMaxRange(link.range) <= text.length {
            let mutable = NSMutableAttributedString(attributedString: text)
            mutable.addAttributes(attrs, range: link.range)
            let wasActive = activeLink
            activeLinkStorage = nil
            inactiveText = nil
            storedText = NSAttributedString(attributedString: mutable)
            if wasActive != nil { activeLink = wasActive }
            setNeedsDisplay()
        }
        links.append(link)
        return link
    }

    /// 添加指向 URL 的链接（使用 `linkAttributes`）
    @discardableResult
    @objc(addLinkToURL:withRange:)
    open func addLink(to url: URL, range: NSRange) -> ZLLabelLink {
        let result = NSTextCheckingResult.linkCheckingResult(range: range, url: url)
        return addLink(ZLLabelLink(range: range, result: result, attributes: linkAttributes))
    }

    /// 添加带点击回调的链接（`attributes` 为 nil 时使用 `linkAttributes`）
    @discardableResult
    @objc(addLinkWithRange:attributes:onTap:)
    open func addLink(range: NSRange, attributes: ZLTextStyle? = nil,
                      onTap: @escaping (ZLAttributedLabel, ZLLabelLink) -> Void) -> ZLLabelLink {
        return addLink(ZLLabelLink(range: range, attributes: attributes ?? linkAttributes, onTap: onTap))
    }

    /// 移除所有链接（已应用到文字上的链接样式不会移除）
    open func removeAllLinks() {
        activeLink = nil
        links = []
    }

    /// 某个位置的链接，没有时为 nil
    @objc(linkAtPoint:)
    open func link(at point: CGPoint) -> ZLLabelLink? {
        guard !links.isEmpty, bounds.insetBy(dx: -15, dy: -15).contains(point) else { return nil }
        let index = characterIndex(at: point)
        // 按在文字上：以这个字为准，不向四周扩大查找（避免按在普通文字上却命中了上下行的链接）
        if index != NSNotFound { return link(atCharacter: index) }
        guard extendsLinkTouchArea else { return nil }
        for radius: CGFloat in [2.5, 5, 7.5, 12.5, 15] {
            let diagonal = (2 * radius * radius).squareRoot()
            let deltas = [CGPoint(x: 0, y: -radius), CGPoint(x: 0, y: radius), CGPoint(x: -radius, y: 0),
                          CGPoint(x: radius, y: 0), CGPoint(x: -diagonal, y: -diagonal), CGPoint(x: -diagonal, y: diagonal),
                          CGPoint(x: diagonal, y: diagonal), CGPoint(x: diagonal, y: -diagonal)]
            for delta in deltas {
                if let link = link(atCharacter: characterIndex(at: CGPoint(x: point.x + delta.x, y: point.y + delta.y))) {
                    return link
                }
            }
        }
        return nil
    }

    /// 某个位置是否有链接
    @objc(containsLinkAtPoint:)
    open func containsLink(at point: CGPoint) -> Bool {
        return link(at: point) != nil
    }

    /// 某个字符所在的链接（后添加的优先）
    @objc(linkAtCharacterIndex:)
    open func link(atCharacter index: Int) -> ZLLabelLink? {
        guard index != NSNotFound, index >= 0, index < (storedText?.length ?? 0) else { return nil }
        return links.last { NSLocationInRange(index, $0.range) }
    }

    private static var detectors: [NSTextCheckingTypes: NSDataDetector] = [:]

    func detectLinks(in text: NSAttributedString) -> [ZLLabelLink] {
        var result: [ZLLabelLink] = []
        let full = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.link, in: full, options: []) { value, range, _ in
            let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
            guard let link = url else { return }
            result.append(ZLLabelLink(range: range, result: .linkCheckingResult(range: range, url: link),
                                      attributes: linkAttributes))
        }
        guard enabledTextCheckingTypes != 0 else { return result }
        let types = enabledTextCheckingTypes
        let detector: NSDataDetector?
        if let cached = ZLAttributedLabel.detectors[types] {
            detector = cached
        } else {
            detector = try? NSDataDetector(types: types)
            ZLAttributedLabel.detectors[types] = detector
        }
        for match in detector?.matches(in: text.string, options: [], range: full) ?? [] {
            // 已有 .link 的范围不重复添加
            guard !result.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else { continue }
            result.append(ZLLabelLink(range: match.range, result: match, attributes: linkAttributes))
        }
        return result
    }

    func updateActiveLinkAppearance() {
        let attrs = activeLink?.activeAttributes ?? activeLinkAttributes
        if let link = activeLink, !attrs.isEmpty {
            if inactiveText == nil { inactiveText = storedText }
            guard let base = inactiveText else { return }
            let mutable = NSMutableAttributedString(attributedString: base)
            if link.range.length > 0, NSMaxRange(link.range) <= mutable.length {
                mutable.addAttributes(attrs, range: link.range)
            }
            storedText = NSAttributedString(attributedString: mutable)
            setNeedsDisplay()
            CATransaction.flush()
        } else if let original = inactiveText {
            storedText = original
            inactiveText = nil
            setNeedsDisplay()
        }
    }

    /// 触发链接点击（与手指点击相同）
    @objc(performTapOnLink:)
    open func performTap(on link: ZLLabelLink) {
        if let onTap = link.onTap {
            onTap(self, link)
            return
        }
        if let url = link.url, delegate?.attributedLabel?(self, didSelectLinkWith: url) != nil { return }
        delegate?.attributedLabel?(self, didSelect: link)
    }

    @objc func handleLinkLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: self)
        guard let link = activeLink ?? link(at: point) else { return }
        activeLink = nil
        if let onLongPress = link.onLongPress {
            onLongPress(self, link)
        } else {
            delegate?.attributedLabel?(self, didLongPress: link, at: point)
        }
    }

    // MARK: 触摸

    open override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha >= 0.01, link(at: point) != nil else {
            return super.hitTest(point, with: event)
        }
        return self
    }

    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first, let link = link(at: touch.location(in: self)) {
            activeLink = link
        } else {
            super.touchesBegan(touches, with: event)
        }
    }

    open override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeLink else {
            super.touchesMoved(touches, with: event)
            return
        }
        if let touch = touches.first, link(at: touch.location(in: self)) !== active {
            activeLink = nil
        }
    }

    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let link = activeLink else {
            super.touchesEnded(touches, with: event)
            return
        }
        // 先恢复样式再回调（回调中可能重新设置文字）
        activeLink = nil
        performTap(on: link)
    }

    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if activeLink != nil {
            activeLink = nil
        } else {
            super.touchesCancelled(touches, with: event)
        }
    }

    open override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsDisplay()
    }
}

/// 链接长按手势的代理：只在按在链接上时接收
final class ZLLinkGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var label: ZLAttributedLabel?

    init(label: ZLAttributedLabel) {
        self.label = label
        super.init()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let label = label else { return false }
        return label.link(at: touch.location(in: label)) != nil
    }
}
