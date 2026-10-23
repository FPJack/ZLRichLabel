//
//  ZLAttributedLabel.swift
//  ZLRichLabel
//
//  基于 CoreText 的富文本 Label（替代 TTTAttributedLabel），`ZLRichLabel` 的基类：
//  - 富文本绘制：内边距、垂直对齐、行数限制、自定义截断符（头 / 中 / 尾）、阴影、高亮文字颜色
//  - 补充 CoreText 不绘制的属性：`.backgroundColor`、`.strikethroughStyle` / `.strikethroughColor`
//  - 链接：手动添加、`.link` 属性自动识别、NSDataDetector 识别（URL / 电话 / 地址 / 日期等）
//    默认 / 按下 / 失活（tintAdjustmentMode == .dimmed）样式，点击 / 长按回调，扩大点击热区
//  - 尺寸计算（sizeThatFits / intrinsicContentSize，按宽度 + 行数缓存）、字符定位、文字范围的矩形
//  - VoiceOver：每个链接单独作为可点击的无障碍元素
//
//  不支持：`adjustsFontSizeToFitWidth`、NSTextAttachment 绘制（ZLRichLabel 会把附件转换为 View）
//

import UIKit
import CoreText

// MARK: - 类型

/// 文字在 label 中的垂直对齐方式（内容高度小于 label 高度时生效）
@objc public enum ZLLabelVerticalAlignment: Int {
    case center = 0
    case top = 1
    case bottom = 2
}

/// label 中的一个链接
@objcMembers
open class ZLLabelLink: NSObject {
    /// 链接在文字中的范围
    public let range: NSRange
    /// 识别结果（`.link` 属性 / NSDataDetector 识别的链接有值，手动添加的可以为 nil）
    public let result: NSTextCheckingResult?
    /// 链接样式，添加时应用到文字上；nil 时不修改文字样式
    public let attributes: ZLTextStyle?
    /// 按下时的样式，nil 时使用 label 的 `activeLinkAttributes`
    public let activeAttributes: ZLTextStyle?
    /// 失活（`tintAdjustmentMode == .dimmed`）时的样式，nil 时使用 label 的 `inactiveLinkAttributes`
    public let inactiveAttributes: ZLTextStyle?
    /// VoiceOver 读出的附加信息（accessibilityValue），nil 时使用 URL / 电话号码等
    public var accessibilityHintText: String?
    /// 点击回调，设置后不再回调 delegate
    public var onTap: ((ZLAttributedLabel, ZLLabelLink) -> Void)?
    /// 长按回调，设置后不再回调 delegate
    public var onLongPress: ((ZLAttributedLabel, ZLLabelLink) -> Void)?

    /// 链接的 URL（`.link` 属性、识别出的网址）
    public var url: URL? { return result?.url }

    public init(range: NSRange,
                result: NSTextCheckingResult? = nil,
                attributes: ZLTextStyle? = nil,
                activeAttributes: ZLTextStyle? = nil,
                inactiveAttributes: ZLTextStyle? = nil,
                onTap: ((ZLAttributedLabel, ZLLabelLink) -> Void)? = nil) {
        self.range = range
        self.result = result
        self.attributes = attributes
        self.activeAttributes = activeAttributes
        self.inactiveAttributes = inactiveAttributes
        self.onTap = onTap
        super.init()
    }

    public override var description: String {
        return "ZLLabelLink(range: \(range), url: \(url?.absoluteString ?? "nil"))"
    }
}

/// 链接点击 / 长按回调（链接自己设置了 `onTap` / `onLongPress` 时不会回调）
@objc public protocol ZLAttributedLabelDelegate: NSObjectProtocol {
    /// 点击了带 URL 的链接（实现后 URL 链接不再回调 `didSelect link`）
    @objc(attributedLabel:didSelectLinkWithURL:)
    optional func attributedLabel(_ label: ZLAttributedLabel, didSelectLinkWith url: URL)
    /// 点击了链接
    @objc(attributedLabel:didSelectLink:)
    optional func attributedLabel(_ label: ZLAttributedLabel, didSelect link: ZLLabelLink)
    /// 长按了链接
    @objc(attributedLabel:didLongPressLink:atPoint:)
    optional func attributedLabel(_ label: ZLAttributedLabel, didLongPress link: ZLLabelLink, at point: CGPoint)
}

// MARK: - 排版缓存

/// 同一份文字只创建一次 CTFramesetter；尺寸、行数、textRect 内的行与原点按参数缓存
final class ZLTextLayout {
    struct SizeKey: Hashable {
        let width: CGFloat
        let height: CGFloat
        let numberOfLines: Int
    }

    let text: NSAttributedString
    let framesetter: CTFramesetter
    /// sizeThatFits 结果（宽度 + 行数）
    var sizes: [SizeKey: CGSize] = [:]
    /// textRect 计算时的建议尺寸（约束尺寸）
    var suggestedSizes: [SizeKey: CGSize] = [:]
    /// 宽度 → 总行数
    var lineCounts: [CGFloat: Int] = [:]
    var frameRect: CGRect?
    var frameLines: [CTLine] = []
    var frameOrigins: [CGPoint] = []

    init(text: NSAttributedString) {
        self.text = text
        self.framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
    }
}

// MARK: - ZLAttributedLabel

@objcMembers
open class ZLAttributedLabel: UILabel {

    // MARK: 文字

    /// 当前展示的富文本（按下链接时为带按下样式的副本）
    private var storedText: NSAttributedString?
    /// 通过 `text` 设置的纯文本：字体 / 颜色 / 对齐等变化后按 label 属性重新生成
    private var plainText: String?
    /// 按下链接前的文字
    private var inactiveText: NSAttributedString?

    /// 设置纯文本：使用 label 的 `font`、`textColor`、`textAlignment`、`lineBreakMode`。读取得到展示的文字
    open override var text: String? {
        get { return storedText?.string }
        set {
            guard let string = newValue else {
                setContent(nil)
                return
            }
            setContent(NSAttributedString(string: string, attributes: labelAttributes()))
            plainText = string
        }
    }

    /// 设置富文本：按原样展示（未设置字体 / 颜色的部分使用 label 的 `font` / `textColor`）。
    /// 设置后会清空之前的链接，并自动识别 `.link` 属性与 `enabledTextCheckingTypes` 指定的内容
    open override var attributedText: NSAttributedString? {
        get { return storedText }
        set { setContent(newValue) }
    }

    private func setContent(_ text: NSAttributedString?) {
        inactiveText = nil
        activeLinkStorage = nil
        plainText = nil
        links = []
        guard let text = text else {
            storedText = nil
            textDidChange()
            return
        }
        let mutable = NSMutableAttributedString(attributedString: text)
        fillMissingAttributes(in: mutable)
        let detected = detectLinks(in: mutable)
        for link in detected {
            if let attrs = link.attributes, !attrs.isEmpty { mutable.addAttributes(attrs, range: link.range) }
        }
        storedText = NSAttributedString(attributedString: mutable)
        links = detected
        textDidChange()
    }

    /// 替换文字但保留已添加的链接（字符与下标不变、只修改属性时使用，例如更新附件占位尺寸）
    func replaceAttributedTextKeepingLinks(_ text: NSAttributedString) {
        activeLink = nil
        storedText = text.copy() as? NSAttributedString
        textDidChange()
    }

    private func textDidChange() {
        invalidateAccessibilityElements()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// 富文本中没有字体 / 颜色的部分补上 label 的字体 / 颜色（CoreText 默认是 12pt 黑色）
    private func fillMissingAttributes(in text: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: text.length)
        let baseFont = font ?? UIFont.systemFont(ofSize: 17)
        let baseColor = textColor ?? UIColor.black
        text.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            if value == nil { text.addAttribute(.font, value: baseFont, range: range) }
        }
        text.enumerateAttribute(.foregroundColor, in: full, options: []) { value, range, _ in
            if value == nil { text.addAttribute(.foregroundColor, value: baseColor, range: range) }
        }
    }

    /// 纯文本使用的属性
    open func labelAttributes() -> ZLTextStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        paragraph.lineBreakMode = numberOfLines == 1 ? lineBreakMode : .byWordWrapping
        return [.font: font ?? UIFont.systemFont(ofSize: 17),
                .foregroundColor: textColor ?? UIColor.black,
                .paragraphStyle: paragraph]
    }

    /// 纯文本：label 属性变化后重新生成（保留链接）
    private func labelAttributesDidChange() {
        if let string = plainText {
            let mutable = NSMutableAttributedString(string: string, attributes: labelAttributes())
            for link in links {
                if let attrs = link.attributes, !attrs.isEmpty, NSMaxRange(link.range) <= mutable.length {
                    mutable.addAttributes(attrs, range: link.range)
                }
            }
            replaceAttributedTextKeepingLinks(mutable)
            plainText = string
        } else {
            setNeedsDisplay()
        }
    }

    open override var font: UIFont! {
        didSet { labelAttributesDidChange() }
    }

    open override var textColor: UIColor! {
        didSet { labelAttributesDidChange() }
    }

    open override var textAlignment: NSTextAlignment {
        didSet { labelAttributesDidChange() }
    }

    open override var lineBreakMode: NSLineBreakMode {
        didSet { labelAttributesDidChange() }
    }

    open override var numberOfLines: Int {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    open override var isHighlighted: Bool {
        didSet { setNeedsDisplay() }
    }

    // MARK: 排版属性

    /// 文字与 label 边缘的距离，`sizeThatFits` 的结果包含它
    open var textInsets: UIEdgeInsets = .zero {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// 内容高度小于 label 高度时的垂直对齐方式，默认居中
    open var verticalAlignment: ZLLabelVerticalAlignment = .center {
        didSet {
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// 截断时显示在末尾的富文本，nil 时使用 "…"（与截断处文字的样式相同）
    open var attributedTruncationToken: NSAttributedString? {
        didSet { setNeedsDisplay() }
    }

    /// 文字阴影的模糊半径（配合 `shadowColor` / `shadowOffset`）
    open var shadowRadius: CGFloat = 0 {
        didSet { setNeedsDisplay() }
    }

    // MARK: 链接

    open weak var delegate: ZLAttributedLabelDelegate?

    /// 当前所有链接（后添加的优先响应）
    public private(set) var links: [ZLLabelLink] = [] {
        didSet { invalidateAccessibilityElements() }
    }

    /// 识别 / 便捷方法添加的链接使用的样式，默认蓝色加下划线
    open var linkAttributes: ZLTextStyle = [.foregroundColor: UIColor.systemBlue,
                                            .underlineStyle: NSUnderlineStyle.single.rawValue]

    /// 按下链接时的样式（链接没有单独设置 `activeAttributes` 时使用），为空时按下不改变样式
    open var activeLinkAttributes: ZLTextStyle = [.foregroundColor: UIColor.systemBlue.withAlphaComponent(0.5)]

    /// 失活（`tintAdjustmentMode == .dimmed`，例如弹出 alert 时）的链接样式，nil 或空时不改变
    open var inactiveLinkAttributes: ZLTextStyle? = [.foregroundColor: UIColor.systemGray] {
        didSet { setNeedsDisplay() }
    }

    /// 为 true 时，手指没有按在文字上（行间距、行尾空白等）时向四周最多 15pt 查找链接。
    /// 按在文字上时只以该文字为准，不会命中旁边的链接
    open var extendsLinkTouchArea = false

    /// 自动识别的内容（例如 `NSTextCheckingResult.CheckingType.link.rawValue | ...phoneNumber.rawValue`），默认 0 不识别。
    /// 设置文字时识别，识别结果作为链接（使用 `linkAttributes`）
    open var enabledTextCheckingTypes: NSTextCheckingTypes = 0 {
        didSet {
            guard enabledTextCheckingTypes != oldValue, let text = storedText else { return }
            if let string = plainText {
                self.text = string
            } else {
                setContent(text)
            }
        }
    }

    /// 长按链接的手势（只在按在链接上时开始）
    public private(set) var longPressGestureRecognizer: UILongPressGestureRecognizer!

    private lazy var linkGestureDelegate = ZLLinkGestureDelegate(label: self)

    /// 当前按下的链接
    private var activeLinkStorage: ZLLabelLink?

    /// 当前按下的链接（按下期间显示按下样式；也可以手动设置以显示 / 取消按下样式）
    public var activeLink: ZLLabelLink? {
        get { return activeLinkStorage }
        set {
            activeLinkStorage = newValue
            updateActiveLinkAppearance()
        }
    }

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

    private func detectLinks(in text: NSAttributedString) -> [ZLLabelLink] {
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

    private func updateActiveLinkAppearance() {
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

    // MARK: Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupAttributedLabel()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAttributedLabel()
        // xib / storyboard 中的文字：UILabel 解码时直接保存在内部，这里转换为富文本
        if storedText == nil {
            if let attributed = super.attributedText, attributed.length > 0 {
                attributedText = attributed
            } else if let string = super.text, !string.isEmpty {
                text = string
            }
        }
    }

    private func setupAttributedLabel() {
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = false
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLinkLongPress(_:)))
        longPress.delegate = linkGestureDelegate
        addGestureRecognizer(longPress)
        longPressGestureRecognizer = longPress
    }

    @objc private func handleLinkLongPress(_ gesture: UILongPressGestureRecognizer) {
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

    // MARK: 排版

    private var layoutStorage: ZLTextLayout?
    /// 上一份文字的排版（按下链接时文字会临时替换为带按下样式的副本，松开后可直接复用）
    private var previousLayoutStorage: ZLTextLayout?

    /// 某份文字的排版缓存
    func textLayout(for text: NSAttributedString) -> ZLTextLayout {
        if let layout = layoutStorage, layout.text === text { return layout }
        if let layout = previousLayoutStorage, layout.text === text {
            previousLayoutStorage = layoutStorage
            layoutStorage = layout
            return layout
        }
        let layout = ZLTextLayout(text: text)
        didCreateFramesetter()
        previousLayoutStorage = layoutStorage
        layoutStorage = layout
        return layout
    }

    /// 创建了新的 CTFramesetter（子类统计用）
    func didCreateFramesetter() {}

    /// `sizeThatFits` 命中缓存（子类统计用）
    func didHitSizeCache() {}

    /// 计算某个文字宽度下的尺寸时使用的行数（子类可按宽度决定，例如超过阈值才折叠）
    func numberOfLines(forTextWidth width: CGFloat) -> Int {
        return numberOfLines
    }

    /// 按 textRect 排版得到的所有行与原点（缓存，内容或区域不变时直接返回）
    func frameLines(for text: NSAttributedString, in textRect: CGRect) -> ([CTLine], [CGPoint]) {
        let layout = textLayout(for: text)
        if layout.frameRect != textRect {
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(layout.framesetter, CFRange(location: 0, length: text.length), path, nil)
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
        return font ?? UIFont.systemFont(ofSize: 17)
    }

    open override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let insetBounds = bounds.inset(by: textInsets)
        guard let text = storedText, text.length > 0 else {
            return super.textRect(forBounds: insetBounds, limitedToNumberOfLines: numberOfLines)
        }
        var textRect = insetBounds
        // 高度至少两行，避免约束过小时 CTFramesetterSuggestFrameSizeWithConstraints 返回 0
        textRect.size.height = max(baselineFont.lineHeight * CGFloat(max(2, numberOfLines)), insetBounds.height)
        let layout = textLayout(for: text)
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
        let fontDescender = baselineFont.descender
        let width = Double(textRect.width)

        for lineIndex in 0..<count {
            let line = lines[lineIndex]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let baselineY = textRect.minY + textRect.height - (origins[lineIndex].y - descent - fontDescender)
            if point.y < baselineY - ascent { return NSNotFound }     // 在这一行上方（行间距）
            if point.y > baselineY + descent + leading { continue }  // 在这一行下方
            let penOffset = CGFloat(CTLineGetPenOffsetForFlush(line, flushFactor, width))
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
        let fontDescender = baselineFont.descender
        var rects: [CGRect] = []
        for i in 0..<count {
            let line = lines[i]
            let cf = CTLineGetStringRange(line)
            let overlap = NSIntersectionRange(range, NSRange(location: cf.location, length: cf.length))
            guard overlap.length > 0 else { continue }
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            let baselineY = textRect.minY + textRect.height - (origins[i].y - descent - fontDescender)
            let penOffset = CGFloat(CTLineGetPenOffsetForFlush(line, flushFactor, Double(textRect.width)))
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
        let lastRange = CTLineGetStringRange(line)
        guard !(lastRange.length == 0 && lastRange.location == 0),
              lastRange.location + lastRange.length < text.length else { return nil }

        let mode: NSLineBreakMode = lineCount != 1 ? .byTruncatingTail : lineBreakMode
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

        let token = attributedTruncationToken
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

    /// 是否截断最后一行
    var truncatesLastLine: Bool {
        return lineBreakMode == .byTruncatingHead || lineBreakMode == .byTruncatingMiddle
            || lineBreakMode == .byTruncatingTail
    }

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
            let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: text.length),
                                                 CGPath(rect: textRect, transform: nil), nil)
            lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
            var buffer = [CGPoint](repeating: .zero, count: lines.count)
            if !lines.isEmpty { CTFrameGetLineOrigins(frame, CFRange(location: 0, length: lines.count), &buffer) }
            origins = buffer
        }
        let count = numberOfLines > 0 ? min(numberOfLines, lines.count) : lines.count
        let fontDescender = baselineFont.descender
        let width = Double(textRect.width)
        var result: [DrawingLine] = []
        for i in 0..<count {
            var line = lines[i]
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, nil, &descent, nil)
            if i == count - 1, truncatesLastLine,
               let truncated = truncatedLine(for: line, in: text, lineCount: count, width: width) {
                line = truncated.line
            }
            let penOffset = CGFloat(CTLineGetPenOffsetForFlush(line, flushFactor, width))
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

    // MARK: 无障碍

    private var accessibilityElementsCache: [Any]?
    private var customAccessibilityElements: [Any]?
    private var isAccessibilityElementOverride: Bool?

    private func invalidateAccessibilityElements() {
        accessibilityElementsCache = nil
    }

    private var lastLayoutWidth: CGFloat = -1

    open override func layoutSubviews() {
        super.layoutSubviews()
        invalidateAccessibilityElements()
        // 多行时高度取决于宽度：宽度变化后重新计算（Auto Layout 自适应高度）
        if bounds.width != lastLayoutWidth {
            lastLayoutWidth = bounds.width
            if numberOfLines != 1 && preferredMaxLayoutWidth <= 0 { invalidateIntrinsicContentSize() }
        }
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

// MARK: - 辅助类型

private extension CGRect {
    var nonNullOrZero: CGRect { return isNull ? .zero : self }
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

/// 链接长按手势的代理：只在按在链接上时接收
private final class ZLLinkGestureDelegate: NSObject, UIGestureRecognizerDelegate {
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
