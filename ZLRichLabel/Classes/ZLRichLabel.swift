//
//  ZLRichLabel.swift
//  ZLRichLabel
//
//  富文本基类（基于 TTTAttributedLabel）：
//  - 基于正则规则（`TagRichRule`）解析文本，重叠时按优先级取舍
//  - 命中内容交给规则 handler 渲染（样式 / 替换文字 / 图片 / 自定义 View / 点击 / 按下高亮）
//  - 负责渲染、内嵌 View 布局、截断、Auto Layout 自适应高度、RTL
//
//  子类通过重写 `builtInRules` 提供内置规则，例如 `ZLTagRichLabel` 的 `<h>` 标签。
//

import UIKit
import CoreText
import TTTAttributedLabel

// MARK: - 解析片段

/// 解析结果片段：普通文本（`match` 为 nil）或规则命中（`match` 不为 nil）
@objcMembers
public final class ZLRichSegment: NSObject {
    /// 原始文字
    public let text: String
    /// 规则命中，普通文本为 nil
    public let match: TagRichMatch?

    public init(text: String, match: TagRichMatch?) {
        self.text = text
        self.match = match
        super.init()
    }

    public var isRuleMatch: Bool { return match != nil }
}

// MARK: - 组件

/// 基于正则规则的富文本基类
///
/// ```swift
/// let label = ZLRichLabel(frame: .zero)
/// label.numberOfLines = 0
/// label.style = [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.gray]
/// try? label.addRule(name: "mention", pattern: "@\\w+", priority: 10) { ctx in
///     ctx.addAttributes([.foregroundColor: UIColor.purple])
///     ctx.onTap = { print("@", ctx.matchedText) }
/// }
/// label.text = "hello @alice"
/// ```
@objcMembers
open class ZLRichLabel: TTTAttributedLabel {

    /// 原始文本（与直接设置 `text = "..."` 等价），按规则解析后渲染
    open var rawText: String = "" {
        didSet {
            guard !isPassingThrough, rawText != oldValue else { return }
            setNeedsReparse()
        }
    }

    /// 可以直接设置 `text`：
    /// - `String`：按规则解析并渲染（等同于设置 `rawText`），xib / storyboard 中设置的文字同样会被解析
    /// - `NSAttributedString`：不解析，按 TTTAttributedLabel 原有逻辑直接展示
    /// - `nil`：清空
    ///
    /// 读取 `text` 得到的是渲染后的展示文字；原始字符串请读 `rawText`
    open override var text: Any! {
        get { return super.text }
        set {
            // rebuild() 内部调用 setText(result) 时直接交给 TTTAttributedLabel
            if isRebuilding {
                super.text = newValue
                return
            }
            switch newValue {
            case let string as String:
                rawText = string
            case let attributed as NSAttributedString:
                // 外部直接传富文本：清空解析状态，按普通 TTTAttributedLabel 处理
                isPassingThrough = true
                rawText = ""
                segments = []
                isPassingThrough = false
                didParse()
                removeAttachmentViews()
                super.text = attributed
            default:
                // nil：清空（rawText 已为空时 didSet 不会触发，需要手动刷新）
                if rawText.isEmpty {
                    segments = []
                    didParse()
                    rebuild()
                } else {
                    rawText = ""
                }
            }
        }
    }

    private var isPassingThrough = false

    /// 普通文本样式（未设置 font / foregroundColor 时使用 label 的 font / textColor）
    open var style: HTagTextStyle = [:] { didSet { setNeedsRebuild() } }

    /// 可点击内容按下时的默认高亮样式（为空则不高亮），规则可通过 `context.highlightStyle` 单独指定
    open var highlightStyle: HTagTextStyle = [:] { didSet { setNeedsRebuild() } }

    /// 截断时使用的省略符，nil 时使用 "…"（带普通文本样式）
    open var truncationToken: NSAttributedString? { didSet { setNeedsRebuild() } }

    // MARK: 规则

    /// 外部添加的规则（命中内容交给规则 handler 处理），重叠时按优先级取舍，见 `TagRichRule`
    open var rules: [TagRichRule] = [] { didSet { setNeedsReparse() } }

    /// 子类内置规则（默认为空）。同优先级时排在 `rules` 之前。
    /// 内置规则的配置变化后，子类需要调用 `setNeedsReparse()`
    open var builtInRules: [TagRichRule] { return [] }

    /// 实际参与解析的所有规则：`builtInRules + rules`
    public var allRules: [TagRichRule] { return builtInRules + rules }

    /// 添加规则（同名规则会被替换）
    open func addRule(_ rule: TagRichRule) {
        if let i = rules.firstIndex(where: { $0.name == rule.name }) {
            rules[i] = rule
        } else {
            rules.append(rule)
        }
    }

    /// 便捷添加规则：正则非法时抛出错误
    open func addRule(name: String, pattern: String, options: NSRegularExpression.Options = [], priority: Int = 0,
                      handler: @escaping (TagRichRuleContext) -> Void) throws {
        addRule(try TagRichRule(name: name, pattern: pattern, options: options, priority: priority, handler: handler))
    }

    /// 按名称移除规则（Objective-C：`[label removeRuleNamed:@"mention"]`）
    @objc(removeRuleNamed:)
    open func removeRule(named name: String) {
        rules.removeAll { $0.name == name }
    }

    /// 移除所有外部添加的规则（不影响 `builtInRules`）
    open func removeAllRules() {
        rules.removeAll()
    }

    /// 当前解析出的片段
    public private(set) var segments: [ZLRichSegment] = []

    /// 当前所有生效的规则命中（含内置规则），按位置排序
    public var matches: [TagRichMatch] { return segments.compactMap { $0.match } }

    // MARK: Private

    private static let attachmentKey = NSAttributedString.Key("ZLRichLabelAttachmentID")
    private static let attachmentChar: unichar = 0xFFFC

    private final class Attachment {
        let id: Int
        let view: UIView
        let size: CGSize
        let ascent: CGFloat
        let descent: CGFloat
        init(id: Int, view: UIView, size: CGSize, ascent: CGFloat, descent: CGFloat) {
            self.id = id
            self.view = view
            self.size = size
            self.ascent = ascent
            self.descent = descent
        }
    }

    /// CTRunDelegate 的 refCon
    private final class RunMetrics {
        let ascent: CGFloat
        let descent: CGFloat
        let width: CGFloat
        init(ascent: CGFloat, descent: CGFloat, width: CGFloat) {
            self.ascent = ascent
            self.descent = descent
            self.width = width
        }
    }

    private var attachments: [Int: Attachment] = [:]
    private var nextAttachmentId = 0
    private var batchUpdateDepth = 0
    private var isRebuilding = false

    // MARK: Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        enabledTextCheckingTypes = 0
        linkAttributes = [:]
        activeLinkAttributes = [:]
        inactiveLinkAttributes = nil
        isUserInteractionEnabled = true
        // xib / storyboard 中设置的 text 会在 super.init(coder:) 期间就被解析，
        // 此时 link 样式还是 TTT 默认的（蓝色下划线），这里按最终配置重新渲染一次
        if !rawText.isEmpty { rebuild() }
    }

    // MARK: 批量更新

    /// 开始批量修改：直到 `endUpdates()` 前不会重新渲染（可嵌套）
    open func beginUpdates() {
        batchUpdateDepth += 1
    }

    /// 结束批量修改，最外层结束时重新渲染一次
    open func endUpdates() {
        guard batchUpdateDepth > 0 else { return }
        batchUpdateDepth -= 1
        if batchUpdateDepth == 0 { rebuild() }
    }

    /// Objective-C：`[label update:^(ZLRichLabel *v) { ... }]`
    /// Swift 请使用 `label.update { v in ... }`（v 为 label 的实际类型）
    @available(swift, obsoleted: 1.0)
    @objc(update:)
    public func objc_update(_ block: (ZLRichLabel) -> Void) {
        beginUpdates()
        block(self)
        endUpdates()
    }

    open override var font: UIFont! {
        didSet { setNeedsRebuild() }
    }

    open override var textColor: UIColor! {
        didSet { setNeedsRebuild() }
    }

    // MARK: Parse

    /// 规则 / 解析配置变化后重新解析并渲染（子类内置规则变化时调用）
    public final func setNeedsReparse() {
        guard !isPassingThrough else { return }
        parse()
        setNeedsRebuild()
    }

    private func parse() {
        let source = rawText
        let ns = source as NSString
        var result: [ZLRichSegment] = []
        var cursor = 0
        for match in TagRichParser.resolve(source, rules: allRules) {
            if match.range.location > cursor {
                let text = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                result.append(ZLRichSegment(text: text, match: nil))
            }
            result.append(ZLRichSegment(text: match.text, match: match))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result.append(ZLRichSegment(text: ns.substring(from: cursor), match: nil))
        }
        segments = result
        didParse()
    }

    /// 解析完成（`segments` 已更新）后调用，子类可重写以整理自己的解析结果。默认空实现
    open func didParse() {}

    // MARK: Build

    /// 配置变化后重新渲染（批量更新中会推迟到 `endUpdates()`）
    public final func setNeedsRebuild() {
        guard batchUpdateDepth == 0, !isRebuilding else { return }
        rebuild()
    }

    /// 普通文本样式：label 的 font / textColor + `style`
    public var resolvedBaseStyle: HTagTextStyle {
        var baseStyle: HTagTextStyle = [:]
        if let font = font { baseStyle[.font] = font }
        if let color = textColor { baseStyle[.foregroundColor] = color }
        baseStyle.merge(style) { $1 }
        return baseStyle
    }

    /// 重新构建富文本
    open func rebuild() {
        guard !isRebuilding else { return }
        isRebuilding = true
        defer { isRebuilding = false }

        removeAttachmentViews()

        let baseStyle = resolvedBaseStyle
        // TTTAttributedLabel 绘制时用 label.font 的 descender 修正基线，保持与正文字体一致
        if let baseFont = baseStyle[.font] as? UIFont, baseFont != font {
            font = baseFont
        }

        let result = NSMutableAttributedString()
        /// (范围, 按下高亮样式, 点击)
        var linkItems: [(NSRange, HTagTextStyle?, () -> Void)] = []

        for seg in segments {
            guard let match = seg.match else {
                result.append(NSAttributedString(string: seg.text, attributes: baseStyle))
                continue
            }

            // handler 中通过 context.attachmentString(for:) 创建的 View，onTap 确定后再统一加点击
            var pending: [(Attachment, Bool)] = []
            let context = TagRichRuleContext(match: match, baseStyle: baseStyle) { [unowned self] widget, style in
                let attachment = self.makeAttachment(widget: widget, style: style)
                pending.append((attachment, widget.tappable))
                return self.makeAttachmentString(attachment, style: style)
            }
            match.rule.handler(context)
            context.attachmentFactory = nil

            let onTap = context.onTap
            if let onTap = onTap {
                for (attachment, tappable) in pending where tappable {
                    addTap(to: attachment.view, action: onTap)
                }
            }
            // TTTAttributedLabel 不绘制 NSTextAttachment，这里转换成 View 承载
            let custom = convertTextAttachments(in: context.attributedString, style: baseStyle, tapAction: onTap)
            let range = NSRange(location: result.length, length: custom.length)
            result.append(custom)
            if let onTap = onTap, range.length > 0 {
                linkItems.append((range, context.highlightStyle, onTap))
            }
        }

        // 根据最终渲染内容判断书写方向（与 CoreText 的自然段落方向一致；占位符 U+FFFC 为中性字符）
        isRightToLeft = ZLRichLabel.detectRightToLeft(result.string)
            ?? (effectiveUserInterfaceLayoutDirection == .rightToLeft)

        attributedTruncationToken = truncationToken ?? NSAttributedString(string: "\u{2026}", attributes: baseStyle)
        activeLinkAttributes = highlightStyle.isEmpty ? [:] : highlightStyle

        setText(result)

        for (range, highlight, tapAction) in linkItems {
            let checking = NSTextCheckingResult.transitInformationCheckingResult(range: range, components: [:])
            // 按下高亮：为 nil 时 TTT 使用 activeLinkAttributes（即 highlightStyle）
            let link = TTTAttributedLabelLink(attributes: nil,
                                              activeAttributes: highlight,
                                              inactiveAttributes: nil,
                                              textCheckingResult: checking)
            link?.linkTapBlock = { _, _ in tapAction() }
            if let link = link { addLink(link) }
        }

        for attachment in attachments.values.sorted(by: { $0.id < $1.id }) {
            attachment.view.isHidden = true
            addSubview(attachment.view)
        }

        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
    }

    // MARK: Attachments

    private func removeAttachmentViews() {
        attachments.values.forEach { $0.view.removeFromSuperview() }
        attachments.removeAll()
        nextAttachmentId = 0
    }

    private func makeAttachment(widget: HTagWidget, style: HTagTextStyle) -> Attachment {
        let view = widget.view
        var size = widget.size
        if size == .zero {
            let fitting = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            if fitting.width > 0, fitting.height > 0 {
                size = fitting
            } else {
                let fits = view.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
                size = (fits.width > 0 && fits.height > 0) ? fits : view.bounds.size
            }
        }

        let font = (style[.font] as? UIFont) ?? self.font ?? UIFont.systemFont(ofSize: 17)
        let height = size.height
        var ascent: CGFloat
        var descent: CGFloat
        switch widget.alignment {
        case .baseline, .aboveBaseline:
            ascent = height
            descent = 0
        case .belowBaseline:
            ascent = 0
            descent = height
        case .top:
            ascent = font.ascender
            descent = height - font.ascender
        case .bottom:
            descent = -font.descender
            ascent = height - descent
        case .middle:
            let mid = (font.ascender + font.descender) / 2
            ascent = height / 2 + mid
            descent = height / 2 - mid
        }

        // View 可能被复用：移除之前添加的点击
        view.gestureRecognizers?.filter { $0 is TagTapGestureRecognizer }.forEach { view.removeGestureRecognizer($0) }

        let attachment = Attachment(id: nextAttachmentId, view: view, size: size, ascent: ascent, descent: descent)
        nextAttachmentId += 1
        attachments[attachment.id] = attachment
        return attachment
    }

    private func addTap(to view: UIView, action: @escaping () -> Void) {
        view.isUserInteractionEnabled = true
        let tap = TagTapGestureRecognizer(target: self, action: #selector(handleAttachmentTap(_:)))
        tap.tapAction = action
        view.addGestureRecognizer(tap)
    }

    private func makeAttachmentString(_ attachment: Attachment, style: HTagTextStyle) -> NSAttributedString {
        let metrics = RunMetrics(ascent: attachment.ascent, descent: attachment.descent, width: attachment.size.width)
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { ref in
                Unmanaged<RunMetrics>.fromOpaque(ref).release()
            },
            getAscent: { ref in
                return Unmanaged<RunMetrics>.fromOpaque(ref).takeUnretainedValue().ascent
            },
            getDescent: { ref in
                return Unmanaged<RunMetrics>.fromOpaque(ref).takeUnretainedValue().descent
            },
            getWidth: { ref in
                return Unmanaged<RunMetrics>.fromOpaque(ref).takeUnretainedValue().width
            })
        let refCon = Unmanaged.passRetained(metrics).toOpaque()
        guard let delegate = CTRunDelegateCreate(&callbacks, refCon) else {
            Unmanaged<RunMetrics>.fromOpaque(refCon).release()
            return NSAttributedString()
        }

        var attrs = style
        attrs[.foregroundColor] = UIColor.clear
        attrs[.underlineStyle] = nil
        attrs[.strikethroughStyle] = nil
        attrs[.backgroundColor] = nil
        attrs[NSAttributedString.Key(kCTRunDelegateAttributeName as String)] = delegate
        attrs[ZLRichLabel.attachmentKey] = attachment.id
        return NSAttributedString(string: String(utf16CodeUnits: [ZLRichLabel.attachmentChar], count: 1), attributes: attrs)
    }

    /// 把内容中的 NSTextAttachment（图片）转换为 UIImageView 占位
    private func convertTextAttachments(in string: NSAttributedString,
                                        style: HTagTextStyle,
                                        tapAction: (() -> Void)?) -> NSAttributedString {
        var found: [(NSRange, NSTextAttachment)] = []
        string.enumerateAttribute(.attachment, in: NSRange(location: 0, length: string.length), options: []) { value, range, _ in
            if let att = value as? NSTextAttachment { found.append((range, att)) }
        }
        guard !found.isEmpty else { return string }

        let mutable = NSMutableAttributedString(attributedString: string)
        for (range, att) in found.reversed() {
            guard let image = att.image ?? att.image(forBounds: att.bounds, textContainer: nil, characterIndex: range.location) else {
                mutable.deleteCharacters(in: range)
                continue
            }
            let size = att.bounds.size == .zero ? image.size : att.bounds.size
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            if let color = mutable.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor {
                imageView.tintColor = color
            }

            var attrs = style
            mutable.attributes(at: range.location, effectiveRange: nil).forEach { attrs[$0.key] = $0.value }
            attrs[.attachment] = nil

            let widget = HTagWidget(view: imageView, size: size, position: .replace, alignment: .middle, tappable: true)
            let attachment = makeAttachment(widget: widget, style: attrs)
            if let tapAction = tapAction { addTap(to: imageView, action: tapAction) }
            mutable.replaceCharacters(in: range, with: makeAttachmentString(attachment, style: attrs))
        }
        return mutable
    }

    @objc private func handleAttachmentTap(_ gesture: TagTapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        gesture.tapAction?()
    }

    // MARK: Layout

    private var lastLayoutWidth: CGFloat = 0

    open override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastLayoutWidth {
            lastLayoutWidth = bounds.width
            // 宽度变化后高度可能变化（Auto Layout 自适应高度）
            invalidateIntrinsicContentSize()
        }
        layoutAttachmentViews()
    }

    /// 修复 TTTAttributedLabel.sizeThatFits 的问题：
    /// 设置 attributedTruncationToken 后，TTT 会把省略符拼到字符串末尾但仍使用原 framesetter，
    /// 导致 numberOfLines == 0 时 range 越界、计算结果为 0
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let attr = attributedText, attr.length > 0 else { return super.sizeThatFits(size) }
        let maxValue: CGFloat = 100000
        let horizontalInsets = textInsets.left + textInsets.right
        let verticalInsets = textInsets.top + textInsets.bottom
        var width = size.width - horizontalInsets
        if width <= 0 { width = maxValue }

        let framesetter = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
        var range = CFRange(location: 0, length: attr.length)
        var constraints = CGSize(width: width, height: maxValue)

        if numberOfLines == 1 {
            constraints = CGSize(width: maxValue, height: maxValue)
        } else if numberOfLines > 0 {
            // 只计算前 numberOfLines 行
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: maxValue), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            if let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty {
                let lastLine = lines[min(numberOfLines, lines.count) - 1]
                let lineRange = CTLineGetStringRange(lastLine)
                range = CFRange(location: 0, length: lineRange.location + lineRange.length)
            }
        }

        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, range, nil, constraints, nil)
        return CGSize(width: ceil(suggested.width) + horizontalInsets,
                      height: ceil(suggested.height) + verticalInsets)
    }

    /// 支持 Auto Layout 自适应高度：宽度由约束决定，高度根据内容计算
    open override var intrinsicContentSize: CGSize {
        let width = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : bounds.width
        guard width > 0, attributedText != nil else { return super.intrinsicContentSize }
        let size = sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(size.height))
    }

    open override var bounds: CGRect {
        didSet { if bounds.size != oldValue.size { setNeedsLayout() } }
    }

    open override var numberOfLines: Int {
        didSet { setNeedsLayout() }
    }

    /// TTTAttributedLabel 把 `.natural` 当作左对齐处理，阿拉伯语 / 希伯来语等 RTL 文本会错误地靠左。
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

    /// 当前内容是否为从右到左（RTL）书写
    /// 规则与 CoreText 自然段落方向一致：取第一个强方向字符；没有强方向字符时跟随界面布局方向
    public private(set) var isRightToLeft: Bool = false

    private static func detectRightToLeft(_ string: String) -> Bool? {
        for scalar in string.unicodeScalars {
            let v = scalar.value
            // Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan, Mandaic, Arabic Ext, 表现形式
            if (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
                || (0x10800...0x10FFF).contains(v) || (0x1E800...0x1EFFF).contains(v) {
                // 阿拉伯-印度数字（0660–0669、06F0–06F9）是弱方向字符，跳过
                if (0x0660...0x0669).contains(v) || (0x06F0...0x06F9).contains(v) { continue }
                return true
            }
            if CharacterSet.letters.contains(scalar) {
                return false
            }
        }
        return nil
    }

    open override var textInsets: UIEdgeInsets {
        didSet { setNeedsLayout() }
    }

    open override var verticalAlignment: TTTAttributedLabelVerticalAlignment {
        didSet { setNeedsLayout() }
    }

    private var flushFactor: CGFloat {
        switch textAlignment {
        case .center: return 0.5
        case .right: return 1.0
        default: return 0.0
        }
    }

    /// 与 TTTAttributedLabel 的绘制逻辑保持一致，计算自定义 View 的位置
    private func layoutAttachmentViews() {
        attachments.values.forEach { $0.view.isHidden = true }
        guard !attachments.isEmpty,
              let attr = attributedText, attr.length > 0,
              bounds.width > 0, bounds.height > 0 else { return }

        let textRect = self.textRect(forBounds: bounds, limitedToNumberOfLines: numberOfLines)
        let framesetter = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attr.length), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return }

        let count = numberOfLines > 0 ? min(numberOfLines, lines.count) : lines.count
        var origins = [CGPoint](repeating: .zero, count: count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: count), &origins)

        let truncateLastLine = lineBreakMode == .byTruncatingHead
            || lineBreakMode == .byTruncatingMiddle
            || lineBreakMode == .byTruncatingTail
        let fontDescender = (font ?? UIFont.systemFont(ofSize: 17)).descender
        let width = Double(textRect.width)

        for lineIndex in 0..<count {
            var line = lines[lineIndex]
            var lineString: NSAttributedString = attr

            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, nil, &descent, nil)

            if lineIndex == count - 1 && truncateLastLine,
               let truncated = truncatedLine(for: line, in: attr, lineCount: count, width: width) {
                line = truncated.line
                lineString = truncated.string
            }

            let penOffset = CGFloat(CTLineGetPenOffsetForFlush(line, flushFactor, width))
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
                attachment.view.isHidden = false
            }
        }
    }

    /// 复刻 TTTAttributedLabel 最后一行截断逻辑
    private func truncatedLine(for line: CTLine,
                               in attr: NSAttributedString,
                               lineCount: Int,
                               width: Double) -> (line: CTLine, string: NSAttributedString)? {
        let lastRange = CTLineGetStringRange(line)
        guard !(lastRange.length == 0 && lastRange.location == 0),
              lastRange.location + lastRange.length < attr.length else { return nil }

        var mode = lineBreakMode
        if lineCount != 1 { mode = .byTruncatingTail }

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
            ?? NSAttributedString(string: "\u{2026}", attributes: attr.attributes(at: max(0, position), effectiveRange: nil))
        let tokenLine = CTLineCreateWithAttributedString(token as CFAttributedString)

        let truncationString = NSMutableAttributedString(
            attributedString: attr.attributedSubstring(from: NSRange(location: lastRange.location, length: lastRange.length)))
        if lastRange.length > 0 {
            let lastChar = (truncationString.string as NSString).character(at: lastRange.length - 1)
            if let scalar = UnicodeScalar(lastChar), CharacterSet.newlines.contains(scalar) {
                truncationString.deleteCharacters(in: NSRange(location: lastRange.length - 1, length: 1))
            }
        }
        truncationString.append(token)

        let truncationLine = CTLineCreateWithAttributedString(truncationString as CFAttributedString)
        let result = CTLineCreateTruncatedLine(truncationLine, width, type, tokenLine) ?? tokenLine
        return (result, truncationString)
    }
}

// MARK: - 批量更新（Swift）

/// 让 `update { v in ... }` 中的 `v` 为 label 的实际类型（例如 `ZLTagRichLabel`）
public protocol ZLRichLabelUpdatable: AnyObject {}

extension ZLRichLabel: ZLRichLabelUpdatable {}

public extension ZLRichLabelUpdatable where Self: ZLRichLabel {
    /// 批量修改属性，只在最后刷新一次
    func update(_ block: (Self) -> Void) {
        beginUpdates()
        block(self)
        endUpdates()
    }
}

/// 自定义 View 的点击手势（携带点击动作）
private final class TagTapGestureRecognizer: UITapGestureRecognizer {
    var tapAction: (() -> Void)?
}
