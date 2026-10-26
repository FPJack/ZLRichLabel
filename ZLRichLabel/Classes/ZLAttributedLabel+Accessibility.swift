//
//  ZLAttributedLabel+Accessibility.swift
//  ZLRichLabel
//
//  ZLAttributedLabel 的无障碍：有链接时作为容器，每个链接单独可聚焦、可激活
//

import UIKit
import CoreText

extension ZLAttributedLabel {

    func invalidateAccessibilityElements() {
        accessibilityElementsCache = nil
    }

    /// 有链接时作为容器（整段文字 + 每个链接），没有链接时与 UILabel 相同
    open override var isAccessibilityElement: Bool {
        get { return isAccessibilityElementOverride ?? links.isEmpty }
        set { isAccessibilityElementOverride = newValue }
    }

    open override var accessibilityLabel: String? {
        get { return super.accessibilityLabel ?? storedText?.string }
        set { super.accessibilityLabel = newValue }
    }

    open override var accessibilityElements: [Any]? {
        get {
            if let custom = customAccessibilityElements { return custom }
            guard !links.isEmpty, let text = storedText else { return nil }
            if let cached = accessibilityElementsCache { return cached }
            var elements: [Any] = []
            let base = UIAccessibilityElement(accessibilityContainer: self)
            base.accessibilityLabel = accessibilityLabel
            base.accessibilityTraits = .staticText
            base.accessibilityFrameInContainerSpace = bounds
            elements.append(base)
            let string = text.string as NSString
            for link in links where NSMaxRange(link.range) <= string.length {
                let rect = boundingRect(forCharacterRange: link.range)
                guard rect != .zero else { continue }   // 截断后不可见
                let element = ZLLinkAccessibilityElement(accessibilityContainer: self)
                element.label = self
                element.link = link
                element.accessibilityLabel = string.substring(with: link.range)
                element.accessibilityValue = link.accessibilityHintText ?? link.url?.absoluteString ?? link.result?.phoneNumber
                element.accessibilityTraits = .link
                element.accessibilityFrameInContainerSpace = rect
                elements.append(element)
            }
            accessibilityElementsCache = elements
            return elements
        }
        set { customAccessibilityElements = newValue }
    }
}

/// 链接的无障碍元素：激活时触发链接点击
private final class ZLLinkAccessibilityElement: UIAccessibilityElement {
    weak var label: ZLAttributedLabel?
    var link: ZLLabelLink?

    override func accessibilityActivate() -> Bool {
        guard let label = label, let link = link else { return false }
        label.performTap(on: link)
        return true
    }
}
