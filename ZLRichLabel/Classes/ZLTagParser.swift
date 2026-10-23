//
//  ZLTagParser.swift
//  ZLRichLabel
//
//  可配置的标签解析器：任意标签名（`<b>`、`<a href="…">`、`<color value="#f00">`）、标签属性、嵌套、容错。
//  `ZLTagRichLabel` 用它实现内置的标签规则；也可以单独使用（`ZLTagParser.tags(in:configuration:)`）。
//  同时提供 `<h>` 标签的简单解析 `ZLTagParser.parse(_:)` / `tags(_:)`（原 `HTagParser`）。
//
//  容错规则：
//  - 标签名不符合 `namePattern` 的标签当作普通文字（例如默认配置下的 `<hx>`）
//  - 开闭不匹配、未闭合的标签：开始标签原样显示，里面的内容照常处理，不影响后面的标签
//  - 不允许嵌套时（`allowsNesting == false`），遇到新的开始标签会放弃外层（外层原样显示），只识别最内层
//  - `<name/>`：前面有未闭合的同名标签时作为闭合标签（兼容 `<h1>文字<h1/>` 写法）；
//    否则在 `allowsSelfClosing == true` 时作为空标签（例如 `<br/>`、`<img src="…"/>`），不允许时原样显示
//

import UIKit

/// 标签解析配置
public struct ZLTagParserConfiguration: Equatable {
    /// 可识别的标签名（正则，需要整体匹配，不区分大小写）。
    /// 默认 `h\d*`（`<h>`、`<h1>`、`<h2>` …）；任意标签名可用 `ZLTagParserConfiguration.anyTagName`
    public var namePattern: String
    /// 是否支持嵌套，例如 `<b>粗体 <color value="red">红色</color></b>`
    public var allowsNesting: Bool
    /// 是否支持自闭合空标签，例如 `<br/>`、`<icon name="star"/>`
    public var allowsSelfClosing: Bool

    /// 任意标签名：字母开头，可包含字母、数字、`_`、`-`、`:`
    public static let anyTagName = "[a-z][a-z0-9_:-]*"

    /// 默认配置：只识别 `<h>` / `<hN>`，不支持嵌套和自闭合（与之前的行为一致）
    public static let hTags = ZLTagParserConfiguration(namePattern: "h\\d*", allowsNesting: false, allowsSelfClosing: false)

    /// 任意标签名 + 嵌套 + 自闭合
    public static let anyTags = ZLTagParserConfiguration(namePattern: anyTagName, allowsNesting: true, allowsSelfClosing: true)

    public init(namePattern: String = "h\\d*", allowsNesting: Bool = false, allowsSelfClosing: Bool = false) {
        self.namePattern = namePattern
        self.allowsNesting = allowsNesting
        self.allowsSelfClosing = allowsSelfClosing
    }
}

/// 解析出的标签元素（树结构）
final class ZLTagElement {
    enum Node {
        case text(NSRange)
        case element(ZLTagElement)
    }

    let name: String
    let attributes: [String: String]
    /// 开始标签在原文中的范围（自闭合标签即整个标签）
    let openRange: NSRange
    /// 闭合标签在原文中的范围，自闭合时为 nil
    var closeRange: NSRange?
    let isSelfClosing: Bool
    var children: [Node] = []
    weak var parent: ZLTagElement?

    init(name: String, attributes: [String: String], openRange: NSRange, isSelfClosing: Bool) {
        self.name = name
        self.attributes = attributes
        self.openRange = openRange
        self.isSelfClosing = isSelfClosing
    }

    /// 整个标签（开始标签到闭合标签）在原文中的范围
    var range: NSRange {
        let end = NSMaxRange(closeRange ?? openRange)
        return NSRange(location: openRange.location, length: end - openRange.location)
    }

    /// 标签内容在原文中的范围（不含开闭标签）
    var contentRange: NSRange {
        guard let close = closeRange else { return NSRange(location: NSMaxRange(openRange), length: 0) }
        return NSRange(location: NSMaxRange(openRange), length: close.location - NSMaxRange(openRange))
    }

    /// 标签内的纯文字（去掉内层标签）
    func plainText(in source: NSString) -> String {
        var result = ""
        for child in children {
            switch child {
            case .text(let range): result += source.substring(with: range)
            case .element(let element): result += element.plainText(in: source)
            }
        }
        return result
    }

    /// 自己和所有内层标签（先序：外层在前）
    var allElements: [ZLTagElement] {
        var result = [self]
        for case .element(let child) in children { result += child.allElements }
        return result
    }
}

/// 一次解析的结果
final class ZLTagDocument {
    let source: String
    /// 最外层的标签（按位置排序）
    let roots: [ZLTagElement]

    init(source: String, roots: [ZLTagElement]) {
        self.source = source
        self.roots = roots
    }
}

/// 标签解析器（Objective-C 可用）：
/// - 可配置的通用解析：`tags(in:configuration:)`（任意标签名、属性、嵌套、自闭合、容错）
/// - `<h>` 标签的简单解析：`parse(_:)` / `tags(_:)`（原 `HTagParser`）
public final class ZLTagParser: NSObject {

    private override init() { super.init() }

    // swiftlint:disable force_try
    /// 标签：group 1 为 `/`（闭合），group 2 为标签名，group 3 为属性，group 4 为 `/`（自闭合）
    private static let tokenRegex = try! NSRegularExpression(
        pattern: "<(/)?([a-z][a-z0-9_:-]*)((?:\\s+[^\\s=/>\"']+(?:\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s\"'=<>`]+))?)*)\\s*(/)?>",
        options: [.caseInsensitive])

    /// 属性：group 1 为名称，group 2 / 3 / 4 为双引号 / 单引号 / 无引号的值
    private static let attributeRegex = try! NSRegularExpression(
        pattern: "([^\\s=/>\"']+)(?:\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>`]+)))?",
        options: [])
    // swiftlint:enable force_try

    private static var nameRegexCache: [String: NSRegularExpression] = [:]
    private static let cacheLock = NSLock()

    private static func nameRegex(_ pattern: String) -> NSRegularExpression? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let regex = nameRegexCache[pattern] { return regex }
        let regex = try? NSRegularExpression(pattern: "^(?:\(pattern))$", options: [.caseInsensitive])
        nameRegexCache[pattern] = regex
        return regex
    }

    /// 解析，返回所有标签信息（先序：外层在前，`index` 按开始标签的位置计数）
    @nonobjc public static func tags(in source: String, configuration: ZLTagParserConfiguration = .hTags) -> [ZLTagInfo] {
        let document = parse(source, configuration: configuration)
        let ns = source as NSString
        var result: [ZLTagInfo] = []
        var infos: [ObjectIdentifier: ZLTagInfo] = [:]
        for root in document.roots {
            for element in root.allElements {
                let parent = element.parent.flatMap { infos[ObjectIdentifier($0)] }
                let info = makeInfo(element, in: ns, index: result.count, parent: parent)
                infos[ObjectIdentifier(element)] = info
                result.append(info)
            }
        }
        return result
    }

    static func makeInfo(_ element: ZLTagElement, in source: NSString, index: Int, parent: ZLTagInfo?) -> ZLTagInfo {
        return ZLTagInfo(index: index, name: element.name, text: element.plainText(in: source),
                        raw: source.substring(with: element.range), attributes: element.attributes, parent: parent)
    }

    static func parse(_ source: String, configuration: ZLTagParserConfiguration) -> ZLTagDocument {
        let ns = source as NSString
        let root = ZLTagElement(name: "", attributes: [:], openRange: NSRange(location: 0, length: 0), isSelfClosing: false)
        var stack: [ZLTagElement] = [root]
        var cursor = 0
        let names = nameRegex(configuration.namePattern)

        /// 放弃一个未闭合的标签：开始标签变成文字，里面的内容移到外层
        func abandon(_ element: ZLTagElement) {
            guard let parent = element.parent,
                  let index = parent.children.lastIndex(where: {
                      if case .element(let e) = $0 { return e === element }
                      return false
                  }) else { return }
            for case .element(let child) in element.children { child.parent = parent }
            parent.children.replaceSubrange(index...index, with: [.text(element.openRange)] + element.children)
        }

        /// 栈中可以被关闭的同名标签（不允许嵌套时只看最内层）
        func openIndex(named name: String) -> Int? {
            guard stack.count > 1 else { return nil }
            let candidates = configuration.allowsNesting ? Array((1..<stack.count).reversed()) : [stack.count - 1]
            return candidates.first { stack[$0].name == name }
        }

        func close(at index: Int, with range: NSRange) {
            for j in ((index + 1)..<stack.count).reversed() { abandon(stack[j]) }
            stack[index].closeRange = range
            stack.removeLast(stack.count - index)
        }

        func append(_ node: ZLTagElement.Node) { stack.last!.children.append(node) }

        func appendElement(_ element: ZLTagElement) {
            // 不允许嵌套：放弃外层未闭合的标签
            if !configuration.allowsNesting, stack.count > 1 {
                let outer = stack.removeLast()
                abandon(outer)
            }
            element.parent = stack.last
            append(.element(element))
        }

        for token in tokenRegex.matches(in: source, options: [], range: NSRange(location: 0, length: ns.length)) {
            let range = token.range
            if range.location > cursor {
                append(.text(NSRange(location: cursor, length: range.location - cursor)))
            }
            cursor = NSMaxRange(range)

            let name = ns.substring(with: token.range(at: 2)).lowercased()
            let isClosing = token.range(at: 1).location != NSNotFound
            let isSelfClosing = token.range(at: 4).location != NSNotFound
            let nameMatches = names.map { $0.firstMatch(in: name, options: [], range: NSRange(location: 0, length: (name as NSString).length)) != nil } ?? false
            guard nameMatches, !(isClosing && isSelfClosing) else {
                append(.text(range))
                continue
            }

            if isClosing {
                if let index = openIndex(named: name) { close(at: index, with: range) } else { append(.text(range)) }
            } else if isSelfClosing {
                if let index = openIndex(named: name) {
                    close(at: index, with: range)   // <h1>文字<h1/>
                } else if configuration.allowsSelfClosing {
                    let element = ZLTagElement(name: name, attributes: attributes(in: ns, range: token.range(at: 3)),
                                               openRange: range, isSelfClosing: true)
                    appendElement(element)
                } else {
                    append(.text(range))
                }
            } else {
                let element = ZLTagElement(name: name, attributes: attributes(in: ns, range: token.range(at: 3)),
                                           openRange: range, isSelfClosing: false)
                appendElement(element)
                stack.append(element)
            }
        }
        if cursor < ns.length {
            append(.text(NSRange(location: cursor, length: ns.length - cursor)))
        }
        // 到结尾仍未闭合的标签全部放弃
        while stack.count > 1 { abandon(stack.removeLast()) }

        var roots: [ZLTagElement] = []
        for case .element(let element) in root.children {
            element.parent = nil
            roots.append(element)
        }
        return ZLTagDocument(source: source, roots: roots)
    }

    private static func attributes(in source: NSString, range: NSRange) -> [String: String] {
        guard range.location != NSNotFound, range.length > 0 else { return [:] }
        var result: [String: String] = [:]
        for match in attributeRegex.matches(in: source as String, options: [], range: range) {
            let key = source.substring(with: match.range(at: 1)).lowercased()
            var value = ""
            for group in 2...4 where match.range(at: group).location != NSNotFound {
                value = decodeEntities(source.substring(with: match.range(at: group)))
                break
            }
            result[key] = value
        }
        return result
    }

    /// 属性值中常用的字符实体
    static func decodeEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        return value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: <h> 标签（原 HTagParser）
    //
    // - 闭合写法支持 `</h1>` 与 `<h1/>`，开闭标签名必须一致（不区分大小写）
    // - 开闭不匹配（如 `<h1>xx</h2>`）或未闭合的标签按普通文字原样展示，且不会影响后面的标签
    // - 不支持嵌套：`<h1>a<h2>b</h2></h1>` 只识别最内层的 `<h2>b</h2>`，外层 `<h1>`、`</h1>` 原样展示


    // swiftlint:disable force_try
    /// 标签正则：group 1 为标签名，group 2 为标签内文字
    @objc public static let tagRegex = try! NSRegularExpression(
        // 标签内容中不允许再出现 h 标签（开/闭/自闭合），避免不匹配或未闭合的标签"吞掉"后面的内容
        pattern: "<(h\\d*)>((?:(?!</?h\\d*/?>)[\\s\\S])*?)(?:</\\1>|<\\1/>)",
        options: [.caseInsensitive])
    // swiftlint:enable force_try

    /// 从一次正则命中生成标签信息
    @nonobjc static func info(from result: NSTextCheckingResult, in source: NSString, index: Int) -> ZLTagInfo {
        let name = source.substring(with: result.range(at: 1)).lowercased()
        let textRange = result.range(at: 2)
        let text = textRange.location == NSNotFound ? "" : source.substring(with: textRange)
        return ZLTagInfo(index: index, name: name, text: text, raw: source.substring(with: result.range))
    }

    @objc(parse:)
    public static func parse(_ source: String) -> [ZLTagSegment] {
        let ns = source as NSString
        var segments: [ZLTagSegment] = []
        var cursor = 0
        var index = 0

        for match in tagRegex.matches(in: source, options: [], range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                let text = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                segments.append(ZLTagSegment(text: text, tag: nil))
            }
            let info = ZLTagParser.info(from: match, in: ns, index: index)
            segments.append(ZLTagSegment(text: info.text, tag: info))
            index += 1
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            segments.append(ZLTagSegment(text: ns.substring(from: cursor), tag: nil))
        }
        return segments
    }

    /// 仅获取所有标签信息
    @objc(tags:)
    public static func tags(_ source: String) -> [ZLTagInfo] {
        return parse(source).compactMap { $0.tag }
    }

    /// 通用标签解析（任意标签名、属性、嵌套），返回所有标签（外层在前，内层的 `parent` 指向外层）。
    /// Swift 也可以直接用 `ZLTagParser.tags(in:configuration:)`
    @objc(tagsInString:namePattern:allowsNesting:allowsSelfClosing:)
    public static func tags(in source: String, namePattern: String, allowsNesting: Bool,
                            allowsSelfClosing: Bool) -> [ZLTagInfo] {
        let configuration = ZLTagParserConfiguration(namePattern: namePattern, allowsNesting: allowsNesting,
                                                     allowsSelfClosing: allowsSelfClosing)
        return tags(in: source, configuration: configuration)
    }

    /// 任意标签名的正则（`[a-z][a-z0-9_:-]*`），配合 `tagNamePattern` / `tagsInString:namePattern:…` 使用
    @objc public static var anyTagNamePattern: String { return ZLTagParserConfiguration.anyTagName }
}

// MARK: - 规则适配

/// 让标签解析器可以作为 `ZLRichRule` 的正则使用：`matches` 返回最外层标签的范围
/// （group 1 为标签名，group 2 为标签内容），与其他规则一起按优先级处理重叠
/// 可变状态（解析缓存）由 `lock` 保护
final class ZLTagMarkupExpression: NSRegularExpression, @unchecked Sendable {
    let configuration: ZLTagParserConfiguration
    private var cachedDocument: ZLTagDocument?
    private let lock = NSLock()

    init(configuration: ZLTagParserConfiguration) {
        self.configuration = configuration
        // 不会被使用的占位正则
        // swiftlint:disable:next force_try
        try! super.init(pattern: "(?!)", options: [])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// 解析结果（同一字符串只解析一次）
    func document(for source: String) -> ZLTagDocument {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedDocument, cached.source == source { return cached }
        let document = ZLTagParser.parse(source, configuration: configuration)
        cachedDocument = document
        return document
    }

    override func matches(in string: String, options: NSRegularExpression.MatchingOptions = [],
                          range: NSRange) -> [NSTextCheckingResult] {
        return document(for: string).roots.compactMap { element in
            guard NSLocationInRange(element.range.location, range) || element.range.location == range.location,
                  NSMaxRange(element.range) <= NSMaxRange(range) else { return nil }
            let nameRange = NSRange(location: element.openRange.location + 1, length: (element.name as NSString).length)
            var ranges = [element.range, nameRange, element.contentRange]
            return NSTextCheckingResult.regularExpressionCheckingResult(ranges: &ranges, count: ranges.count,
                                                                         regularExpression: self)
        }
    }

    override func numberOfMatches(in string: String, options: NSRegularExpression.MatchingOptions = [],
                                  range: NSRange) -> Int {
        return matches(in: string, options: options, range: range).count
    }

    override func firstMatch(in string: String, options: NSRegularExpression.MatchingOptions = [],
                             range: NSRange) -> NSTextCheckingResult? {
        return matches(in: string, options: options, range: range).first
    }
}
