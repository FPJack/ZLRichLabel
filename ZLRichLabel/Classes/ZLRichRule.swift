//
//  ZLRichRule.swift
//  ZLRichLabel
//
//  正则规则、命中信息、规则处理上下文，以及按优先级处理重叠的规则解析器
//

import UIKit

// MARK: - 规则

/// 自定义正则规则
///
/// ```swift
/// let mention = try ZLRichRule(name: "mention", pattern: "@[\\w]+", priority: 10) { ctx in
///     ctx.addAttributes([.foregroundColor: UIColor.purple])
///     ctx.onTap = { match in print("tap \(match.text)") }   // 命中信息作为参数传入，不需要引用 ctx
/// }
/// label.addRule(mention)
/// ```
///
/// 优先级（命中范围有重叠时）：
/// 1. `priority` 大的优先
/// 2. 同优先级：位置靠前的优先 → 匹配更长的优先 → 先添加的规则优先（子类内置规则排在外部规则之前）
/// 3. 被淘汰的匹配整体作废（其中的文字按普通文本 / 其他规则处理），不做嵌套解析
@objcMembers
public final class ZLRichRule: NSObject {
    /// 规则名（用于 `removeRule(named:)`、回调中区分规则）
    public let name: String
    /// 正则表达式，也可以传 `NSDataDetector`（它是 `NSRegularExpression` 的子类）
    public let regex: NSRegularExpression
    /// 优先级，数值越大越优先
    public let priority: Int
    /// 命中后的处理：在 `context.attributedString` 上修改 / 替换要展示的内容，设置点击与高亮。
    /// 结果会按命中缓存：修改 `style` / font / textColor、深色模式或字号变化、`rebuild()` 时重新调用；
    /// 只修改按下高亮 / 省略符，或文字变化但该命中的位置与内容不变时直接复用上次结果。
    /// handler 依赖的外部数据变化后，请调用 `rebuild()` 或 `setNeedsRebuild(forRuleNamed:)`
    public let handler: (ZLRichRuleContext) -> Void

    public init(name: String, regex: NSRegularExpression, priority: Int = 0,
                handler: @escaping (ZLRichRuleContext) -> Void) {
        self.name = name
        self.regex = regex
        self.priority = priority
        self.handler = handler
        super.init()
    }

    /// 通过正则字符串创建，正则非法时抛出错误
    /// Objective-C：`[[ZLRichRule alloc] initWithName:pattern:options:priority:error:handler:]`
    public convenience init(name: String, pattern: String, options: NSRegularExpression.Options = [], priority: Int = 0,
                            handler: @escaping (ZLRichRuleContext) -> Void) throws {
        self.init(name: name,
                  regex: try NSRegularExpression(pattern: pattern, options: options),
                  priority: priority,
                  handler: handler)
    }
}

// MARK: - 命中

/// 一次正则命中的信息（range 均相对于原始字符串）
@objcMembers
public final class ZLRichMatch: NSObject {
    /// 命中的规则
    public let rule: ZLRichRule
    /// 第几个命中（从 0 开始，参与解析的所有规则统一计数）
    public let index: Int
    /// 原始正则匹配结果
    public let result: NSTextCheckingResult
    /// 原始字符串
    public let source: String

    public init(rule: ZLRichRule, index: Int, result: NSTextCheckingResult, source: String) {
        self.rule = rule
        self.index = index
        self.result = result
        self.source = source
        super.init()
    }

    /// 命中的原始文字
    public var text: String {
        return (source as NSString).substring(with: result.range)
    }

    /// 命中范围（相对于原始字符串）
    public var range: NSRange { return result.range }

    /// 第 i 个捕获组（0 为整体），不存在或未参与匹配时为 nil
    @objc(groupAtIndex:)
    public func group(_ i: Int) -> String? {
        guard i >= 0, i <= result.numberOfRanges - 1 else { return nil }
        let r = result.range(at: i)
        return r.location == NSNotFound ? nil : (source as NSString).substring(with: r)
    }

    /// 命名捕获组 `(?<name>...)`，不存在或未参与匹配时为 nil
    @objc(groupNamed:)
    public func group(named name: String) -> String? {
        let r = result.range(withName: name)
        return r.location == NSNotFound ? nil : (source as NSString).substring(with: r)
    }

    public override var description: String {
        return "ZLRichMatch(rule: \(rule.name), index: \(index), text: \(text), range: \(range))"
    }
}

// MARK: - 处理上下文

/// 规则的处理上下文：外部在 `attributedString` 上写入解析后的展示内容
@objcMembers
public final class ZLRichRuleContext: NSObject {
    /// 命中信息
    public let match: ZLRichMatch
    /// 普通文本样式（已合并 label 的 font / textColor 与 `style`）
    public let baseStyle: ZLTextStyle

    /// 要展示的内容，初始为「命中文字 + baseStyle」。
    /// 外部可任意修改：加属性、替换文字（`replaceCharacters` / `setAttributedString`）、
    /// 插入 `NSTextAttachment` 图片 / `attachmentString(for:)` 生成的 View 占位；为空则该命中内容不显示
    public let attributedString: NSMutableAttributedString

    /// 点击回调，设置后整段内容可点击（含其中的图片 / tappable 的 View）。
    /// 参数是这次点击的命中信息（文字、捕获组、规则等），回调里不需要也不要引用 `ctx`（会造成循环引用）
    public var onTap: ((ZLRichMatch) -> Void)?

    /// 长按回调（例如弹出「复制 / 举报」菜单）。设置后长按这段内容时只回调它，不再回调 `ZLRichLabel.onLongPress`
    /// 参数同 `onTap`
    public var onLongPress: ((ZLRichMatch) -> Void)?

    /// 按下高亮样式，nil 时使用 `ZLRichLabel.highlightStyle`；`[:]` 表示不高亮
    public var highlightStyle: ZLTextStyle?

    /// 通过 `addLink` 添加的分段点击 / 长按
    private(set) var links: [ZLRuleLink] = []

    /// 给展示内容中的一段（相对 `attributedString` 的范围）单独设置点击 / 长按 / 按下高亮。
    /// 可以添加多段、可以互相包含：范围重叠时后添加的优先（例如嵌套标签先加外层、再加内层）。
    /// 范围内的图片 / tappable 的 View 点击时同样触发这一段的 `onTap`。
    /// 没有被任何一段覆盖的位置使用整体的 `onTap` / `onLongPress`
    @objc(addLinkWithRange:highlightStyle:onTap:onLongPress:)
    public func addLink(range: NSRange, highlightStyle: ZLTextStyle? = nil,
                        onTap: ((ZLRichMatch) -> Void)?, onLongPress: ((ZLRichMatch) -> Void)? = nil) {
        guard range.location != NSNotFound, range.length > 0, onTap != nil || onLongPress != nil else { return }
        links.append(ZLRuleLink(range: range, highlightStyle: highlightStyle, onTap: onTap, onLongPress: onLongPress))
    }

    /// 由 label 注入：生成 View 占位富文本（仅在 handler 执行期间有效）
    var attachmentFactory: ((ZLRichWidget, ZLTextStyle) -> NSAttributedString)?

    init(match: ZLRichMatch, baseStyle: ZLTextStyle,
         attachmentFactory: ((ZLRichWidget, ZLTextStyle) -> NSAttributedString)? = nil) {
        self.match = match
        self.baseStyle = baseStyle
        self.attributedString = NSMutableAttributedString(string: match.text, attributes: baseStyle)
        self.attachmentFactory = attachmentFactory
        super.init()
    }

    /// 便捷：规则名
    public var ruleName: String { return match.rule.name }
    /// 便捷：命中的原始文字
    public var matchedText: String { return match.text }
    /// 便捷：第 i 个捕获组
    @objc(groupAtIndex:)
    public func group(_ i: Int) -> String? { return match.group(i) }
    /// 便捷：命名捕获组
    @objc(groupNamed:)
    public func group(named name: String) -> String? { return match.group(named: name) }

    /// 便捷：用新文字替换展示内容（默认使用 baseStyle，可追加属性）
    /// Objective-C：`[ctx setText:@"xx" attributes:@{...}]`
    public func setText(_ text: String, attributes: ZLTextStyle = [:]) {
        attributedString.setAttributedString(
            NSAttributedString(string: text, attributes: baseStyle.merging(attributes) { $1 }))
    }

    /// 便捷：给整段展示内容追加属性
    public func addAttributes(_ attributes: ZLTextStyle) {
        attributedString.addAttributes(attributes, range: NSRange(location: 0, length: attributedString.length))
    }

    /// 生成自定义 View 的占位富文本，拼接到 `attributedString` 中即可在该位置显示 View。
    /// `widget.tappable` 为 true 且设置了 `onTap` 时，点击 View 触发 `onTap`。
    /// `widget.position` 在这里不生效，由调用方自行决定拼接位置。只能在规则 handler 执行期间调用
    @objc(attachmentStringForWidget:style:)
    public func attachmentString(for widget: ZLRichWidget, style: ZLTextStyle? = nil) -> NSAttributedString {
        return attachmentFactory?(widget, style ?? baseStyle) ?? NSAttributedString()
    }
}

/// 命中内容中的一段点击 / 长按（见 `ZLRichRuleContext.addLink`）
final class ZLRuleLink {
    let range: NSRange
    let highlightStyle: ZLTextStyle?
    let onTap: ((ZLRichMatch) -> Void)?
    let onLongPress: ((ZLRichMatch) -> Void)?

    init(range: NSRange, highlightStyle: ZLTextStyle?, onTap: ((ZLRichMatch) -> Void)?, onLongPress: ((ZLRichMatch) -> Void)?) {
        self.range = range
        self.highlightStyle = highlightStyle
        self.onTap = onTap
        self.onLongPress = onLongPress
    }
}

// MARK: - 解析器

/// 规则解析器：执行所有规则，按优先级处理重叠，返回互不重叠、按位置排序的命中
@objcMembers
public final class ZLRichParser: NSObject {

    private override init() { super.init() }

    private struct Candidate {
        let range: NSRange
        let priority: Int
        /// 规则在数组中的下标（同优先级时靠前的规则优先）
        let order: Int
        let rule: ZLRichRule
        let result: NSTextCheckingResult
    }

    /// - Parameters:
    ///   - source: 原始字符串
    ///   - rules: 规则（数组顺序即添加顺序）
    /// - Returns: 最终生效的命中，按位置排序
    @objc(matchesInString:rules:)
    public static func resolve(_ source: String, rules: [ZLRichRule]) -> [ZLRichMatch] {
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        var candidates: [Candidate] = []
        for (i, rule) in rules.enumerated() {
            for m in rule.regex.matches(in: source, options: [], range: fullRange) where m.range.length > 0 {
                candidates.append(Candidate(range: m.range, priority: rule.priority, order: i, rule: rule, result: m))
            }
        }

        // 按优先级排序后贪心选取互不重叠的命中
        candidates.sort { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            if a.range.location != b.range.location { return a.range.location < b.range.location }
            if a.range.length != b.range.length { return a.range.length > b.range.length }
            return a.order < b.order
        }
        // 已接受的命中互不重叠且按位置有序：二分找到插入位置后，只需检查前后相邻的两个是否重叠
        var accepted: [Candidate] = []
        accepted.reserveCapacity(candidates.count)
        for c in candidates {
            var low = 0
            var high = accepted.count
            while low < high {
                let mid = (low + high) / 2
                if accepted[mid].range.location < c.range.location { low = mid + 1 } else { high = mid }
            }
            if low > 0, NSMaxRange(accepted[low - 1].range) > c.range.location { continue }
            if low < accepted.count, accepted[low].range.location < NSMaxRange(c.range) { continue }
            accepted.insert(c, at: low)
        }

        return accepted.enumerated().map { i, c in
            ZLRichMatch(rule: c.rule, index: i, result: c.result, source: source)
        }
    }
}
