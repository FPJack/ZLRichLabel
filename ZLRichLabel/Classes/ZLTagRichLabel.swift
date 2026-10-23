//
//  ZLTagRichLabel.swift
//  ZLRichLabel
//
//  基于 `ZLRichLabel` 的标签高亮组件：默认支持 `<h>`、`<h1>`、`<h2>`、`<h3>` … 标签，
//  按标签名区分高亮样式、按下高亮与点击事件。标签以内置规则（`h-tag`）的形式实现，
//  可与外部添加的正则规则一起使用（按优先级处理重叠）。
//
//  标签写法：`<h1>文字</h1>` 或 `<h1>文字<h1/>`，开闭标签名必须一致（不区分大小写）
//  通过 `tagNamePattern` / `allowsNestedTags` / `allowsSelfClosingTags` 可以识别任意标签名、
//  解析标签属性（`<a href="…">`、`<color value="#f00">`）并支持嵌套，见 `ZLTagParser`
//

import UIKit

// MARK: - 解析模型

/// 解析到的标签信息
@objcMembers
public final class ZLTagInfo: NSObject {
    /// 第几个标签（从 0 开始，所有标签名统一计数）
    public let index: Int
    /// 标签名（小写），例如 `h`、`h1`、`h2`
    public let name: String
    /// 标签内需要展示的文字，例如 `User Agreement`
    public let text: String
    /// 完整的原始标签字符串，例如 `<h1>User Agreement</h1>`
    public let raw: String
    /// 标签属性（名称为小写），例如 `<a href="https://x.com" target=_blank>` → `["href": "https://x.com", "target": "_blank"]`。
    /// 没有值的属性（`<input disabled>`）值为空字符串
    public let attributes: [String: String]
    /// 外层标签（嵌套时），最外层为 nil
    public let parent: ZLTagInfo?

    public convenience init(index: Int, name: String, text: String, raw: String) {
        self.init(index: index, name: name, text: text, raw: raw, attributes: [:], parent: nil)
    }

    public init(index: Int, name: String, text: String, raw: String, attributes: [String: String], parent: ZLTagInfo?) {
        self.index = index
        self.name = name
        self.text = text
        self.raw = raw
        self.attributes = attributes
        self.parent = parent
        super.init()
    }

    /// 嵌套深度：最外层为 0
    public var depth: Int {
        return parent.map { $0.depth + 1 } ?? 0
    }

    /// 读取属性（名称不区分大小写）
    @objc(attributeNamed:)
    public func attribute(_ name: String) -> String? {
        return attributes[name.lowercased()]
    }

    /// 把属性值解析为颜色：支持 `#rgb`、`#rrggbb`、`#rrggbbaa`（`#` 可省略）和常见颜色名（red、blue、gray …）
    @objc(colorAttributeNamed:)
    public func colorAttribute(_ name: String) -> UIColor? {
        return attribute(name).flatMap(ZLTagInfo.color(from:))
    }

    /// 解析颜色字符串（规则同 `colorAttribute(_:)`）
    @objc(colorFromString:)
    public static func color(from string: String) -> UIColor? {
        let value = string.trimmingCharacters(in: .whitespaces).lowercased()
        let named: [String: UIColor] = [
            "red": .systemRed, "green": .systemGreen, "blue": .systemBlue, "orange": .systemOrange,
            "yellow": .systemYellow, "purple": .systemPurple, "pink": .systemPink, "teal": .systemTeal,
            "gray": .systemGray, "grey": .systemGray, "black": .black, "white": .white, "clear": .clear,
        ]
        if let color = named[value] { return color }
        var hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let number = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let r = CGFloat((number >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((number >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((number >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(number & 0xFF) / 255 : 1
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    /// `<hN>` 标签名中 `h` 后面的数字：`<h1>` 为 1，`<h12>` 为 12；`<h>` 和其他标签名为 nil
    @nonobjc public var level: Int? {
        guard name.hasPrefix("h") else { return nil }
        return Int(name.dropFirst())
    }

    /// Objective-C 使用：`level`，`<h>` 时为 nil
    @objc(level) public var levelNumber: NSNumber? {
        return level.map { NSNumber(value: $0) }
    }

    public override var description: String {
        let attrs = attributes.isEmpty ? "" : ", attributes: \(attributes)"
        let depthText = parent == nil ? "" : ", depth: \(depth), parent: \(parent!.name)"
        return "ZLTagInfo(index: \(index), name: \(name), text: \(text), raw: \(raw)\(attrs)\(depthText))"
    }
}

/// `ZLTagParser` 的解析结果片段：普通文本（`tag` 为 nil）或标签
@objcMembers
public final class ZLTagSegment: NSObject {
    public let text: String
    public let tag: ZLTagInfo?

    public init(text: String, tag: ZLTagInfo?) {
        self.text = text
        self.tag = tag
        super.init()
    }

    public var isTag: Bool { return tag != nil }
}

// MARK: - 配置类型

/// 根据标签信息返回样式（可读取 index / name / level / text）
public typealias ZLTagStyleBuilder = (ZLTagInfo) -> ZLTextStyle?

/// 完全自定义某个标签的富文本，返回 nil 则使用默认样式。
/// 标签可点击时（见 `onTagTap` / `tagTapHandlers`），返回内容的整个范围都可点击
public typealias ZLTagSpanBuilder = (_ info: ZLTagInfo, _ style: ZLTextStyle) -> NSAttributedString?

/// 根据解析内容构建自定义 View，返回 nil 则使用默认文字样式
public typealias ZLTagWidgetBuilder = (_ info: ZLTagInfo, _ style: ZLTextStyle) -> ZLRichWidget?

/// 标签点击回调
public typealias ZLTagTapCallback = (ZLTagInfo) -> Void

// MARK: - 组件

/// 支持 `<h>` / `<h1>` / `<h2>` … 标签的富文本组件，按标签名区分高亮样式与点击
///
/// ```swift
/// let label = ZLTagRichLabel(frame: .zero)
/// label.numberOfLines = 0
/// label.style = [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.gray]
/// label.tagStyle = [.foregroundColor: UIColor.blue]                 // 所有标签的默认样式
/// label.tagStyles = ["h1": [.foregroundColor: UIColor.blue],        // 按标签名区分样式
///                    "h2": [.foregroundColor: UIColor.red]]
/// label.tagTapHandlers = ["h1": { _ in openAgreement() },           // 按标签名区分点击
///                         "h2": { _ in openPrivacy() }]
/// label.onTagTap = { info in print(info.name, info.text) }          // 没有对应 handler 时的兜底点击
///
/// // 自定义正则规则（来自基类 ZLRichLabel）：priority 越大越优先
/// try? label.addRule(name: "mention", pattern: "@\\w+", priority: 10) { ctx in
///     ctx.addAttributes([.foregroundColor: UIColor.purple])
///     ctx.onTap = { match in print("@", match.text) }
/// }
/// label.text = "agree to the <h1>User Agreement</h1> and <h2>Privacy Policy</h2>. cc @alice"
/// ```
@objcMembers
open class ZLTagRichLabel: ZLRichLabel {

    /// 内置 `<h>` 标签规则的名称
    public static let tagRuleName = "h-tag"

    /// 带 `<h>` 标签的原始文本（等同于 `rawText`，也可直接设置 `text = "..."`）
    open var tagText: String {
        get { return rawText }
        set { rawText = newValue }
    }

    /// 批量修改属性，只在最后刷新一次。回调参数直接是 `ZLTagRichLabel`，不需要强转。
    /// Objective-C：`[label updateTag:^(ZLTagRichLabel *v) { v.tagStyles = ...; }]`
    /// Swift 请使用 `label.update { v in ... }`（v 已经是 label 的实际类型）
    @available(swift, obsoleted: 1.0)
    @objc(updateTag:)
    public func objc_updateTag(_ block: (ZLTagRichLabel) -> Void) {
        beginUpdates()
        block(self)
        endUpdates()
    }

    // MARK: 标签样式

    /// 所有标签的默认样式（会 merge 到 style 上）
    open var tagStyle: ZLTextStyle = [:] { didSet { setNeedsTagRebuild() } }

    /// 按标签名区分的样式，key 为小写标签名（`"h"`、`"h1"`、`"h2"` …），会 merge 到 tagStyle 上
    open var tagStyles: [String: ZLTextStyle] = [:] { didSet { setNeedsTagRebuild() } }

    /// 针对单个标签的样式（最后 merge，优先级最高），可根据 index / name / level / text 区分
    open var tagStyleBuilder: ZLTagStyleBuilder? { didSet { setNeedsTagRebuild() } }

    /// 完全自定义标签富文本，返回 nil 则使用默认样式
    open var tagSpanBuilder: ZLTagSpanBuilder? { didSet { setNeedsTagRebuild() } }

    /// 可选：根据解析内容自定义 View（替换文字 / 放在文字前 / 放在文字后）
    /// 返回 nil 则使用默认文字。优先级：tagSpanBuilder > tagWidgetBuilder > 默认
    open var tagWidgetBuilder: ZLTagWidgetBuilder? { didSet { setNeedsTagRebuild() } }

    /// 标签按下时的高亮样式（为空则不高亮），等同于基类的 `highlightStyle`（同时作用于自定义规则）
    open var tagHighlightStyle: ZLTextStyle {
        get { return highlightStyle }
        set { highlightStyle = newValue }
    }

    /// 按标签名区分的按下高亮样式，优先于 `tagHighlightStyle`；设为 `[:]` 可让某类标签不高亮
    open var tagHighlightStyles: [String: ZLTextStyle] = [:] { didSet { setNeedsTagRebuild() } }

    // MARK: 点击

    /// 按标签名区分的点击回调，key 为小写标签名（`"h"`、`"h1"` …）
    /// 某个标签名有对应 handler 时只回调该 handler，否则回调 `onTagTap`
    @nonobjc open var tagTapHandlers: [String: ZLTagTapCallback] = [:] { didSet { setNeedsTagRebuild() } }

    /// 设置某个标签名的点击回调（传 nil 移除），等价于修改 `tagTapHandlers`
    /// Objective-C：`[label setTapHandler:^(ZLTagInfo *info) {...} forTag:@"h1"]`
    @objc(setTapHandler:forTag:)
    open func setTapHandler(_ handler: ZLTagTapCallback?, forTag name: String) {
        tagTapHandlers[name.lowercased()] = handler
    }

    /// 移除某个标签名的点击回调
    @objc(removeTapHandlerForTag:)
    open func removeTapHandler(forTag name: String) {
        tagTapHandlers[name.lowercased()] = nil
    }

    /// 标签点击（兜底）：标签名在 `tagTapHandlers` 中没有对应 handler 时回调
    /// `onTagTap` 和 `tagTapHandlers` 都没有处理的标签不可点击
    open var onTagTap: ZLTagTapCallback? { didSet { setNeedsTagRebuild() } }

    /// 长按标签（例如弹出「复制链接」菜单）。设置后长按标签只回调它，长按其他位置回调基类的 `onLongPress`
    open var onTagLongPress: ZLTagTapCallback? { didSet { setNeedsTagRebuild() } }

    /// 解析完成后把所有标签信息回调给外部（文本或规则变化时回调）
    open var onParsed: (([ZLTagInfo]) -> Void)?

    // MARK: 解析配置

    /// 内置标签规则的优先级（与自定义规则重叠时比较），默认 0
    open var tagPriority: Int = 0 {
        didSet {
            guard tagPriority != oldValue else { return }
            hTagRuleCache = nil
            setNeedsReparse()
        }
    }

    /// 是否解析内置标签，默认 true；设为 false 时只使用自定义规则
    open var parsesTags: Bool = true {
        didSet {
            guard parsesTags != oldValue else { return }
            setNeedsReparse()
        }
    }

    /// 标签解析配置（Swift）：可识别的标签名、是否支持嵌套 / 自闭合。默认 `.hTags`（只识别 `<h>` / `<hN>`）。
    /// 任意标签 + 嵌套 + 自闭合：`label.tagConfiguration = .anyTags`
    @nonobjc open var tagConfiguration: ZLTagParserConfiguration = .hTags {
        didSet {
            guard tagConfiguration != oldValue else { return }
            hTagRuleCache = nil
            setNeedsReparse()
        }
    }

    /// 可识别的标签名（正则，整体匹配，不区分大小写），默认 `h\\d*`；
    /// 任意标签名可用 `ZLTagParserConfiguration.anyTagName`（`[a-z][a-z0-9_:-]*`）
    open var tagNamePattern: String {
        get { return tagConfiguration.namePattern }
        set { tagConfiguration.namePattern = newValue }
    }

    /// 是否支持嵌套（`<b>粗 <color value="red">红</color></b>`），默认 false：只识别最内层，外层原样显示
    open var allowsNestedTags: Bool {
        get { return tagConfiguration.allowsNesting }
        set { tagConfiguration.allowsNesting = newValue }
    }

    /// 是否支持自闭合空标签（`<br/>`、`<icon name="star"/>`），默认 false。
    /// 前面有未闭合的同名标签时 `<h1/>` 始终作为闭合标签
    open var allowsSelfClosingTags: Bool {
        get { return tagConfiguration.allowsSelfClosing }
        set { tagConfiguration.allowsSelfClosing = newValue }
    }

    // MARK: 解析结果

    /// 当前解析出的所有标签（先序：外层在前，内层标签的 `parent` 指向外层）
    public private(set) var tags: [ZLTagInfo] = []

    /// 当前所有自定义规则的命中（不含内置标签）
    public var ruleMatches: [ZLRichMatch] {
        return matches.filter { !isHTagMatch($0) }
    }

    // MARK: 内置规则

    private var hTagRuleCache: ZLRichRule?
    private var tagExpression: ZLTagMarkupExpression?
    /// 最外层标签的位置 → 标签元素
    private var rootElementByLocation: [Int: ZLTagElement] = [:]
    /// 标签元素 → 标签信息
    private var infoByElement: [ObjectIdentifier: ZLTagInfo] = [:]
    /// 最外层标签的位置 → 它的标签序号（用于判断缓存的渲染结果是否过期）
    private var rootIndexByLocation: [Int: Int] = [:]
    private var parsedNotifyScheduled = false

    /// 内置标签规则（优先级或解析配置变化时重新创建）
    private var hTagRule: ZLRichRule {
        if let rule = hTagRuleCache { return rule }
        let expression = ZLTagMarkupExpression(configuration: tagConfiguration)
        tagExpression = expression
        let rule = ZLRichRule(name: ZLTagRichLabel.tagRuleName,
                               regex: expression,
                               priority: tagPriority) { [weak self] context in
            self?.renderTag(context)
        }
        hTagRuleCache = rule
        return rule
    }

    open override var builtInRules: [ZLRichRule] {
        return super.builtInRules + (parsesTags ? [hTagRule] : [])
    }

    /// 标签相关配置变化：只重新渲染标签，自定义规则的命中直接复用缓存（不执行 handler、不重建 View）
    private func setNeedsTagRebuild() {
        setNeedsRebuild(forRuleNamed: ZLTagRichLabel.tagRuleName)
    }

    private func isHTagMatch(_ match: ZLRichMatch) -> Bool {
        return match.rule === hTagRuleCache
    }

    open override func didParse() {
        super.didParse()
        var infos: [ZLTagInfo] = []
        var byElement: [ObjectIdentifier: ZLTagInfo] = [:]
        var roots: [Int: ZLTagElement] = [:]
        var rootIndexes: [Int: Int] = [:]

        let tagMatches = matches.filter { isHTagMatch($0) }
        if let expression = tagExpression, let source = tagMatches.first?.source {
            let ns = source as NSString
            var documentRoots: [Int: ZLTagElement] = [:]
            for root in expression.document(for: source).roots { documentRoots[root.range.location] = root }
            for match in tagMatches {
                guard let root = documentRoots[match.range.location] else { continue }
                roots[match.range.location] = root
                rootIndexes[match.range.location] = infos.count
                for element in root.allElements {
                    let parent = element.parent.flatMap { byElement[ObjectIdentifier($0)] }
                    let info = ZLTagParser.makeInfo(element, in: ns, index: infos.count, parent: parent)
                    byElement[ObjectIdentifier(element)] = info
                    infos.append(info)
                }
            }
        }
        // 标签序号变了（前面的标签增删）时，缓存的渲染结果里的 ZLTagInfo 已过期
        if rootIndexByLocation.contains(where: { old in rootIndexes[old.key].map { $0 != old.value } ?? false }) {
            invalidateRenderCache(forRuleNamed: ZLTagRichLabel.tagRuleName)
        }
        tags = infos
        infoByElement = byElement
        rootElementByLocation = roots
        rootIndexByLocation = rootIndexes

        guard onParsed != nil, !parsedNotifyScheduled else { return }
        parsedNotifyScheduled = true
        // 对应 Flutter 的 addPostFrameCallback
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.parsedNotifyScheduled = false
            self.onParsed?(self.tags)
        }
    }

    /// 内置标签规则的渲染：逐层合并样式 → tagSpanBuilder / tagWidgetBuilder → 每个标签单独的点击、长按与按下高亮
    private func renderTag(_ context: ZLRichRuleContext) {
        guard let root = rootElementByLocation[context.match.range.location] else { return }
        let source = context.match.source as NSString
        let output = NSMutableAttributedString()
        var links: [(range: NSRange, info: ZLTagInfo)] = []
        append(root, inherited: context.baseStyle, source: source, into: output, links: &links, context: context)
        context.attributedString.setAttributedString(output)

        // 外层先加、内层后加：重叠时内层优先
        for (range, info) in links {
            let onTap: ((ZLRichMatch) -> Void)? = isTappable(info) ? { [weak self] _ in self?.dispatchTap(info) } : nil
            let onLongPress: ((ZLRichMatch) -> Void)? = onTagLongPress == nil ? nil : { [weak self] _ in self?.onTagLongPress?(info) }
            context.addLink(range: range, highlightStyle: tagHighlightStyles[info.name], onTap: onTap, onLongPress: onLongPress)
        }
    }

    /// 渲染一个标签（含内层标签）并追加到 output，记录它在 output 中的范围
    private func append(_ element: ZLTagElement, inherited: ZLTextStyle, source: NSString,
                        into output: NSMutableAttributedString, links: inout [(range: NSRange, info: ZLTagInfo)],
                        context: ZLRichRuleContext) {
        guard let info = infoByElement[ObjectIdentifier(element)] else {
            output.append(NSAttributedString(string: source.substring(with: element.range), attributes: inherited))
            return
        }
        // 样式：外层样式 → tagStyle → tagStyles[name] → tagStyleBuilder(info)
        var style = inherited.merging(tagStyle) { $1 }
        if let byName = tagStyles[info.name] {
            style.merge(byName) { $1 }
        }
        if let extra = tagStyleBuilder?(info) {
            style.merge(extra) { $1 }
        }

        let start = output.length
        let slot = links.count
        links.append((NSRange(location: start, length: 0), info))

        // 1. 完全自定义（包含内层标签）
        if let custom = tagSpanBuilder?(info, style) {
            output.append(custom)
        } else {
            // 2. 自定义 View：替换 / 放在内容前 / 放在内容后
            let widget = tagWidgetBuilder?(info, style)
            let widgetSpan = widget.map { context.attachmentString(for: $0, style: style) }
            if let span = widgetSpan, widget?.position == .replace {
                output.append(span)
            } else {
                if let span = widgetSpan, widget?.position == .before { output.append(span) }
                for child in element.children {
                    switch child {
                    case .text(let range):
                        output.append(NSAttributedString(string: source.substring(with: range), attributes: style))
                    case .element(let inner):
                        append(inner, inherited: style, source: source, into: output, links: &links, context: context)
                    }
                }
                if let span = widgetSpan, widget?.position == .after { output.append(span) }
            }
        }
        links[slot].range = NSRange(location: start, length: output.length - start)
    }

    /// 标签是否可点击：有对应标签名的 handler 或设置了 onTagTap
    private func isTappable(_ info: ZLTagInfo) -> Bool {
        return tagTapHandlers[info.name] != nil || onTagTap != nil
    }

    /// 按标签名分发点击：优先 tagTapHandlers[name]，否则 onTagTap
    private func dispatchTap(_ info: ZLTagInfo) {
        if let handler = tagTapHandlers[info.name] {
            handler(info)
        } else {
            onTagTap?(info)
        }
    }
}
