//
//  ZLTagRichLabel.swift
//  ZLRichLabel
//
//  基于 `ZLRichLabel` 的标签高亮组件：支持 `<h>`、`<h1>`、`<h2>`、`<h3>` … 标签，
//  按标签名区分高亮样式、按下高亮与点击事件。`<h>` 标签以内置规则（`h-tag`）的形式实现，
//  可与外部添加的正则规则一起使用（按优先级处理重叠）。
//
//  标签写法：`<h1>文字</h1>` 或 `<h1>文字<h1/>`，开闭标签名必须一致（不区分大小写）
//

import UIKit

// MARK: - 解析模型

/// 解析到的标签信息
@objcMembers
public final class HTagInfo: NSObject {
    /// 第几个标签（从 0 开始，所有标签名统一计数）
    public let index: Int
    /// 标签名（小写），例如 `h`、`h1`、`h2`
    public let name: String
    /// 标签内需要展示的文字，例如 `User Agreement`
    public let text: String
    /// 完整的原始标签字符串，例如 `<h1>User Agreement</h1>`
    public let raw: String

    public init(index: Int, name: String, text: String, raw: String) {
        self.index = index
        self.name = name
        self.text = text
        self.raw = raw
        super.init()
    }

    /// 标签名中 `h` 后面的数字：`<h1>` 为 1，`<h12>` 为 12，`<h>` 为 nil
    @nonobjc public var level: Int? {
        return Int(name.dropFirst())
    }

    /// Objective-C 使用：`level`，`<h>` 时为 nil
    @objc(level) public var levelNumber: NSNumber? {
        return level.map { NSNumber(value: $0) }
    }

    public override var description: String {
        return "HTagInfo(index: \(index), name: \(name), text: \(text), raw: \(raw))"
    }
}

/// `HTagParser` 的解析结果片段：普通文本（`tag` 为 nil）或标签
@objcMembers
public final class HTagSegment: NSObject {
    public let text: String
    public let tag: HTagInfo?

    public init(text: String, tag: HTagInfo?) {
        self.text = text
        self.tag = tag
        super.init()
    }

    public var isTag: Bool { return tag != nil }
}

// MARK: - 解析器

/// 标签解析器：识别 `<h>`、`<h1>`、`<h2>` … `<hN>`（独立工具，不含自定义规则）
///
/// - 闭合写法支持 `</h1>` 与 `<h1/>`，开闭标签名必须一致（不区分大小写）
/// - 开闭不匹配（如 `<h1>xx</h2>`）或未闭合的标签按普通文字原样展示，且不会影响后面的标签
/// - 不支持嵌套：`<h1>a<h2>b</h2></h1>` 只识别最内层的 `<h2>b</h2>`，外层 `<h1>`、`</h1>` 原样展示
@objcMembers
public final class HTagParser: NSObject {

    private override init() { super.init() }

    // swiftlint:disable force_try
    /// 标签正则：group 1 为标签名，group 2 为标签内文字
    public static let tagRegex = try! NSRegularExpression(
        // 标签内容中不允许再出现 h 标签（开/闭/自闭合），避免不匹配或未闭合的标签"吞掉"后面的内容
        pattern: "<(h\\d*)>((?:(?!</?h\\d*/?>)[\\s\\S])*?)(?:</\\1>|<\\1/>)",
        options: [.caseInsensitive])
    // swiftlint:enable force_try

    /// 从一次正则命中生成标签信息
    @nonobjc static func info(from result: NSTextCheckingResult, in source: NSString, index: Int) -> HTagInfo {
        let name = source.substring(with: result.range(at: 1)).lowercased()
        let textRange = result.range(at: 2)
        let text = textRange.location == NSNotFound ? "" : source.substring(with: textRange)
        return HTagInfo(index: index, name: name, text: text, raw: source.substring(with: result.range))
    }

    public static func parse(_ source: String) -> [HTagSegment] {
        let ns = source as NSString
        var segments: [HTagSegment] = []
        var cursor = 0
        var index = 0

        for match in tagRegex.matches(in: source, options: [], range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                let text = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                segments.append(HTagSegment(text: text, tag: nil))
            }
            let info = HTagParser.info(from: match, in: ns, index: index)
            segments.append(HTagSegment(text: info.text, tag: info))
            index += 1
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            segments.append(HTagSegment(text: ns.substring(from: cursor), tag: nil))
        }
        return segments
    }

    /// 仅获取所有标签信息
    public static func tags(_ source: String) -> [HTagInfo] {
        return parse(source).compactMap { $0.tag }
    }
}

// MARK: - 配置类型

/// 根据标签信息返回样式（可读取 index / name / level / text）
public typealias HTagStyleBuilder = (HTagInfo) -> HTagTextStyle?

/// 完全自定义某个标签的富文本，返回 nil 则使用默认样式。
/// 标签可点击时（见 `onTagTap` / `tagTapHandlers`），返回内容的整个范围都可点击
public typealias HTagSpanBuilder = (_ info: HTagInfo, _ style: HTagTextStyle) -> NSAttributedString?

/// 根据解析内容构建自定义 View，返回 nil 则使用默认文字样式
public typealias HTagWidgetBuilder = (_ info: HTagInfo, _ style: HTagTextStyle) -> HTagWidget?

/// 标签点击回调
public typealias HTagTapCallback = (HTagInfo) -> Void

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
///     ctx.onTap = { print("@", ctx.matchedText) }
/// }
/// label.text = "agree to the <h1>User Agreement</h1> and <h2>Privacy Policy</h2>. cc @alice"
/// ```
@objcMembers
open class ZLTagRichLabel: ZLRichLabel {

    /// 内置 `<h>` 标签规则的名称
    public static let hTagRuleName = "h-tag"

    /// 带 `<h>` 标签的原始文本（等同于 `rawText`，也可直接设置 `text = "..."`）
    open var tagText: String {
        get { return rawText }
        set { rawText = newValue }
    }

    // MARK: 标签样式

    /// 所有标签的默认样式（会 merge 到 style 上）
    open var tagStyle: HTagTextStyle = [:] { didSet { setNeedsTagRebuild() } }

    /// 按标签名区分的样式，key 为小写标签名（`"h"`、`"h1"`、`"h2"` …），会 merge 到 tagStyle 上
    open var tagStyles: [String: HTagTextStyle] = [:] { didSet { setNeedsTagRebuild() } }

    /// 针对单个标签的样式（最后 merge，优先级最高），可根据 index / name / level / text 区分
    open var tagStyleBuilder: HTagStyleBuilder? { didSet { setNeedsTagRebuild() } }

    /// 完全自定义标签富文本，返回 nil 则使用默认样式
    open var tagSpanBuilder: HTagSpanBuilder? { didSet { setNeedsTagRebuild() } }

    /// 可选：根据解析内容自定义 View（替换文字 / 放在文字前 / 放在文字后）
    /// 返回 nil 则使用默认文字。优先级：tagSpanBuilder > tagWidgetBuilder > 默认
    open var tagWidgetBuilder: HTagWidgetBuilder? { didSet { setNeedsTagRebuild() } }

    /// 标签按下时的高亮样式（为空则不高亮），等同于基类的 `highlightStyle`（同时作用于自定义规则）
    open var tagHighlightStyle: HTagTextStyle {
        get { return highlightStyle }
        set { highlightStyle = newValue }
    }

    /// 按标签名区分的按下高亮样式，优先于 `tagHighlightStyle`；设为 `[:]` 可让某类标签不高亮
    open var tagHighlightStyles: [String: HTagTextStyle] = [:] { didSet { setNeedsTagRebuild() } }

    // MARK: 点击

    /// 按标签名区分的点击回调，key 为小写标签名（`"h"`、`"h1"` …）
    /// 某个标签名有对应 handler 时只回调该 handler，否则回调 `onTagTap`
    @nonobjc open var tagTapHandlers: [String: HTagTapCallback] = [:] { didSet { setNeedsTagRebuild() } }

    /// 设置某个标签名的点击回调（传 nil 移除），等价于修改 `tagTapHandlers`
    /// Objective-C：`[label setTapHandler:^(HTagInfo *info) {...} forTag:@"h1"]`
    @objc(setTapHandler:forTag:)
    open func setTapHandler(_ handler: HTagTapCallback?, forTag name: String) {
        tagTapHandlers[name.lowercased()] = handler
    }

    /// 移除某个标签名的点击回调
    @objc(removeTapHandlerForTag:)
    open func removeTapHandler(forTag name: String) {
        tagTapHandlers[name.lowercased()] = nil
    }

    /// 标签点击（兜底）：标签名在 `tagTapHandlers` 中没有对应 handler 时回调
    /// `onTagTap` 和 `tagTapHandlers` 都没有处理的标签不可点击
    open var onTagTap: HTagTapCallback? { didSet { setNeedsTagRebuild() } }

    /// 长按标签（例如弹出「复制链接」菜单）。设置后长按标签只回调它，长按其他位置回调基类的 `onLongPress`
    open var onTagLongPress: HTagTapCallback? { didSet { setNeedsTagRebuild() } }

    /// 解析完成后把所有标签信息回调给外部（文本或规则变化时回调）
    open var onParsed: (([HTagInfo]) -> Void)?

    // MARK: 解析配置

    /// 内置 `<h>` 标签的优先级（与自定义规则重叠时比较），默认 0
    open var hTagPriority: Int = 0 {
        didSet {
            guard hTagPriority != oldValue else { return }
            hTagRuleCache = nil
            setNeedsReparse()
        }
    }

    /// 是否解析内置 `<h>` 标签，默认 true；设为 false 时只使用自定义规则
    open var parsesHTags: Bool = true {
        didSet {
            guard parsesHTags != oldValue else { return }
            setNeedsReparse()
        }
    }

    // MARK: 解析结果

    /// 当前解析出的所有标签
    public private(set) var tags: [HTagInfo] = []

    /// 当前所有自定义规则的命中（不含内置 `<h>` 标签）
    public var ruleMatches: [TagRichMatch] {
        return matches.filter { !isHTagMatch($0) }
    }

    // MARK: 内置规则

    private var hTagRuleCache: TagRichRule?
    /// 标签命中位置 → 标签信息
    private var tagInfoByLocation: [Int: HTagInfo] = [:]
    private var parsedNotifyScheduled = false

    /// `<h>` 标签规则（`hTagPriority` 变化时重新创建）
    private var hTagRule: TagRichRule {
        if let rule = hTagRuleCache { return rule }
        let rule = TagRichRule(name: ZLTagRichLabel.hTagRuleName,
                               regex: HTagParser.tagRegex,
                               priority: hTagPriority) { [weak self] context in
            self?.renderTag(context)
        }
        hTagRuleCache = rule
        return rule
    }

    open override var builtInRules: [TagRichRule] {
        return super.builtInRules + (parsesHTags ? [hTagRule] : [])
    }

    /// 标签相关配置变化：只重新渲染 `<h>` 标签，自定义规则的命中直接复用缓存（不执行 handler、不重建 View）
    private func setNeedsTagRebuild() {
        setNeedsRebuild(forRuleNamed: ZLTagRichLabel.hTagRuleName)
    }

    private func isHTagMatch(_ match: TagRichMatch) -> Bool {
        return match.rule === hTagRuleCache
    }

    open override func didParse() {
        super.didParse()
        var infos: [HTagInfo] = []
        var byLocation: [Int: HTagInfo] = [:]
        for match in matches where isHTagMatch(match) {
            let info = HTagParser.info(from: match.result, in: match.source as NSString, index: infos.count)
            infos.append(info)
            byLocation[match.range.location] = info
        }
        // 标签序号变了（前面的标签增删）时，缓存的渲染结果里的 HTagInfo 已过期
        if tagInfoByLocation.contains(where: { old in byLocation[old.key].map { $0.index != old.value.index } ?? false }) {
            invalidateRenderCache(forRuleNamed: ZLTagRichLabel.hTagRuleName)
        }
        tags = infos
        tagInfoByLocation = byLocation

        guard onParsed != nil, !parsedNotifyScheduled else { return }
        parsedNotifyScheduled = true
        // 对应 Flutter 的 addPostFrameCallback
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.parsedNotifyScheduled = false
            self.onParsed?(self.tags)
        }
    }

    /// 内置 `<h>` 规则的渲染：样式 → tagSpanBuilder / tagWidgetBuilder → 点击与按下高亮
    private func renderTag(_ context: TagRichRuleContext) {
        guard let info = tagInfoByLocation[context.match.range.location] else { return }

        var style = context.baseStyle.merging(tagStyle) { $1 }
        if let byName = tagStyles[info.name] {
            style.merge(byName) { $1 }
        }
        if let extra = tagStyleBuilder?(info) {
            style.merge(extra) { $1 }
        }

        if isTappable(info) {
            context.onTap = { [weak self] in self?.dispatchTap(info) }
            context.highlightStyle = tagHighlightStyles[info.name]
        }
        if onTagLongPress != nil {
            context.onLongPress = { [weak self] in self?.onTagLongPress?(info) }
        }

        // 1. 完全自定义
        if let custom = tagSpanBuilder?(info, style) {
            context.attributedString.setAttributedString(custom)
            return
        }

        let textSpan = NSAttributedString(string: info.text, attributes: style)

        // 2. 自定义 View
        guard let widget = tagWidgetBuilder?(info, style) else {
            context.attributedString.setAttributedString(textSpan)
            return
        }
        let widgetSpan = context.attachmentString(for: widget, style: style)
        let output = NSMutableAttributedString()
        switch widget.position {
        case .replace:
            output.append(widgetSpan)
        case .before:
            output.append(widgetSpan)
            output.append(textSpan)
        case .after:
            output.append(textSpan)
            output.append(widgetSpan)
        }
        context.attributedString.setAttributedString(output)
    }

    /// 标签是否可点击：有对应标签名的 handler 或设置了 onTagTap
    private func isTappable(_ info: HTagInfo) -> Bool {
        return tagTapHandlers[info.name] != nil || onTagTap != nil
    }

    /// 按标签名分发点击：优先 tagTapHandlers[name]，否则 onTagTap
    private func dispatchTap(_ info: HTagInfo) {
        if let handler = tagTapHandlers[info.name] {
            handler(info)
        } else {
            onTagTap?(info)
        }
    }
}
