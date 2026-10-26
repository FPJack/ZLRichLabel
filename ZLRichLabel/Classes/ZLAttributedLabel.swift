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
//  - 字号自适应：`adjustsFontSizeToFitWidth` + `minimumScaleFactor`（单行按宽度，多行按行数与高度）
//
//  不支持：NSTextAttachment 绘制（ZLRichLabel 会把附件转换为 View）
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
    var storedText: NSAttributedString?
    /// 通过 `text` 设置的纯文本：字体 / 颜色 / 对齐等变化后按 label 属性重新生成
    private var plainText: String?
    /// 按下链接前的文字
    var inactiveText: NSAttributedString?

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
        fontScaleCache = nil
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

    // MARK: 字号自适应

    /// 为 true 时，文字在当前尺寸内放不下时等比缩小字体，最小缩放到 `minimumScaleFactor`（为 0 时不缩小，与 UILabel 相同）。
    /// - 单行（`numberOfLines == 1`）：按宽度判断
    /// - 多行：按行数（`numberOfLines > 0` 时）与 label 高度判断
    ///
    /// 只缩放字体（包括富文本中各段的字体和截断符），不缩放字间距、行距与内嵌 View；
    /// `sizeThatFits` / `intrinsicContentSize` 仍按原字号计算（与 UILabel 相同），缩放按 label 的实际尺寸进行
    open override var adjustsFontSizeToFitWidth: Bool {
        didSet { fontScaleDidChange() }
    }

    /// 字号自适应时的最小缩放比例（0 ~ 1），默认 0 表示不缩小
    open override var minimumScaleFactor: CGFloat {
        didSet { fontScaleDidChange() }
    }

    /// 当前绘制使用的字体缩放比例，1 表示未缩小
    open var currentFontScaleFactor: CGFloat {
        return currentFontScale()
    }

    struct FontScaleKey: Equatable {
        let width: CGFloat
        let height: CGFloat
        let numberOfLines: Int
        let minimum: CGFloat
    }

    /// 缩放比例缓存（文字变化时清空；按下链接只改变样式，不清空）
    var fontScaleCache: (key: FontScaleKey, scale: CGFloat)?
    /// 缩小后的文字排版
    var scaledLayoutCache: (source: NSAttributedString, scale: CGFloat, layout: ZLTextLayout)?

    // MARK: 链接

    open weak var delegate: ZLAttributedLabelDelegate?

    /// 当前所有链接（后添加的优先响应）
    public internal(set) var links: [ZLLabelLink] = [] {
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
    var activeLinkStorage: ZLLabelLink?

    /// 当前按下的链接（按下期间显示按下样式；也可以手动设置以显示 / 取消按下样式）
    public var activeLink: ZLLabelLink? {
        get { return activeLinkStorage }
        set {
            activeLinkStorage = newValue
            updateActiveLinkAppearance()
        }
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

    // MARK: 无障碍

    var accessibilityElementsCache: [Any]?
    var customAccessibilityElements: [Any]?
    var isAccessibilityElementOverride: Bool?

    var lastLayoutWidth: CGFloat = -1

}

// MARK: - 辅助类型

extension CGRect {
    var nonNullOrZero: CGRect { return isNull ? .zero : self }
}
