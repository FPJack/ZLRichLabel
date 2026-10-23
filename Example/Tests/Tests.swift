import XCTest
import ZLRichLabel
import TTTAttributedLabel

/// 自定义 View 尺寸变化后刷新排版
class AttachmentResizeTests: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    /// 创建 label：`[box]` 替换为传入的 View；`@x` 为可点击规则（用于验证链接不丢失）
    private func makeLabel(widget: @escaping () -> HTagWidget) -> ZLRichLabel {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 0))
        label.numberOfLines = 0
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 15)]
            try? v.addRule(name: "box", pattern: "\\[box\\]") { ctx in
                ctx.attributedString.setAttributedString(ctx.attachmentString(for: widget()))
            }
            try? v.addRule(name: "mention", pattern: "@x") { ctx in
                ctx.onTap = {}
            }
            v.text = "Hello [box] world, some words @x"
        }
        window.addSubview(label)
        fit(label)
        return label
    }

    private func fit(_ label: ZLRichLabel) {
        label.frame.size.height = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height
        window.layoutIfNeeded()
        label.layoutIfNeeded()
    }

    /// 外部直接修改 View 的 frame 尺寸：label 下次布局自动刷新
    func testExternalFrameChangeReflows() {
        let box = UIView()
        let label = makeLabel { HTagWidget(view: box, size: CGSize(width: 20, height: 14)) }
        XCTAssertEqual(box.frame.size, CGSize(width: 20, height: 14))
        let heightBefore = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height
        let linksBefore = label.links.count

        box.frame.size = CGSize(width: 150, height: 30)
        label.layoutIfNeeded()

        XCTAssertEqual(box.bounds.size, CGSize(width: 150, height: 30))
        let heightAfter = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(heightAfter, heightBefore, "View 变宽后文字应换行，高度增加")
        XCTAssertEqual(label.links.count, linksBefore, "刷新排版不应丢失链接")

        // 布局稳定：再次布局尺寸不变
        fit(label)
        XCTAssertEqual(box.bounds.size, CGSize(width: 150, height: 30))
        XCTAssertFalse(box.isHidden)
    }

    /// 自动尺寸的 View 内容变化：调用 zl_setNeedsRichLabelLayout 重新测量
    func testAutoSizeContentChange() {
        let badge = UILabel()
        badge.font = .systemFont(ofSize: 12)
        badge.text = "1"
        let label = makeLabel { HTagWidget(view: badge) }   // size == .zero 自动计算
        let widthBefore = badge.bounds.width
        XCTAssertGreaterThan(widthBefore, 0)

        badge.text = "123456789"
        badge.zl_setNeedsRichLabelLayout()
        label.layoutIfNeeded()

        XCTAssertGreaterThan(badge.bounds.width, widthBefore)
        XCTAssertEqual(badge.bounds.size, badge.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                                    height: CGFloat.greatestFiniteMagnitude)))
    }

    /// 从内部子 View 调用也能找到所在的 label
    func testInvalidateFromNestedSubview() {
        let container = UIView()
        let inner = UIView()
        container.addSubview(inner)
        let label = makeLabel { HTagWidget(view: container, size: CGSize(width: 20, height: 14)) }

        container.bounds.size = CGSize(width: 60, height: 14)
        inner.zl_setNeedsRichLabelLayout()
        label.layoutIfNeeded()

        XCTAssertEqual(container.frame.size, CGSize(width: 60, height: 14))
    }

    /// 固定尺寸且未被外部修改：invalidate 不改变尺寸
    func testFixedSizeUnchangedWithoutExternalChange() {
        let box = UIView()
        let label = makeLabel { HTagWidget(view: box, size: CGSize(width: 20, height: 14)) }
        label.invalidateAttachmentLayout()
        label.layoutIfNeeded()
        XCTAssertEqual(box.frame.size, CGSize(width: 20, height: 14))
    }
}

/// 深色模式 / Dynamic Type
class AppearanceTests: XCTestCase {

    /// 固定一个较大的系统字号，用于验证缩放
    private final class LargeTextLabel: ZLRichLabel {
        override var traitCollection: UITraitCollection {
            return UITraitCollection(traitsFrom: [super.traitCollection,
                                                  UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)])
        }
    }

    private func fonts(in label: ZLRichLabel) -> [UIFont] {
        var result: [UIFont] = []
        let attr = label.attributedText!
        attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length), options: []) { value, _, _ in
            if let font = value as? UIFont { result.append(font) }
        }
        return result
    }

    func testDynamicTypeScalesAllFonts() {
        let label = LargeTextLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 15)]
            try? v.addRule(name: "bold", pattern: "\\*\\*(.+?)\\*\\*") { ctx in
                ctx.setText(ctx.group(1) ?? "", attributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
            }
            v.text = "plain **bold**"
        }
        XCTAssertEqual(Set(fonts(in: label).map { $0.pointSize }), [15, 20], "未开启时不缩放")

        label.adjustsFontForContentSizeCategory = true
        let sizes = fonts(in: label).map { $0.pointSize }
        XCTAssertTrue(sizes.allSatisfy { $0 > 20 }, "开启后正文与规则内容都应放大：\(sizes)")
        XCTAssertGreaterThan(label.font.pointSize, 15, "label.font（基线修正用）也应缩放")

        // 再次渲染不会重复缩放
        let once = fonts(in: label).map { $0.pointSize }
        label.rebuild()
        XCTAssertEqual(fonts(in: label).map { $0.pointSize }, once)

        // 关闭后恢复
        label.adjustsFontForContentSizeCategory = false
        XCTAssertEqual(Set(fonts(in: label).map { $0.pointSize }), [15, 20])
    }

    func testDarkModeChangeRebuilds() {
        guard #available(iOS 13.0, *) else { return }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        window.isHidden = false
        defer { window.isHidden = true }

        var styles: [UIUserInterfaceStyle] = []
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        try? label.addRule(name: "any", pattern: "x") { [weak label] ctx in
            styles.append(label?.traitCollection.userInterfaceStyle ?? .unspecified)
        }
        label.overrideUserInterfaceStyle = .light
        window.addSubview(label)
        label.text = "x"
        styles.removeAll()

        label.overrideUserInterfaceStyle = .dark
        // iOS 17+ trait 变化在布局时下发
        window.layoutIfNeeded()
        label.layoutIfNeeded()
        XCTAssertEqual(styles.last, .dark, "切换到深色后应按新外观重新执行 handler")
    }
}

/// 性能优化：解析器、渲染缓存、排版缓存
class PerformanceCacheTests: XCTestCase {

    // MARK: 解析器

    private func rule(_ name: String, _ pattern: String, priority: Int = 0) -> TagRichRule {
        return try! TagRichRule(name: name, pattern: pattern, priority: priority) { _ in }
    }

    private func describe(_ matches: [TagRichMatch]) -> [String] {
        return matches.map { "\($0.rule.name):\($0.text)" }
    }

    func testParserResolvesOverlapsByPriority() {
        let text = "aa @bob #topic @bob# bb"
        // 同优先级：位置靠前优先
        XCTAssertEqual(describe(TagRichParser.resolve(text, rules: [rule("m", "@\\w+"), rule("t", "#[^#]+#")])),
                       ["m:@bob", "t:#topic @bob#"])
        // 优先级高的先占位，被它覆盖的低优先级命中作废
        XCTAssertEqual(describe(TagRichParser.resolve(text, rules: [rule("m", "@\\w+", priority: 10), rule("t", "#[^#]+#")])),
                       ["m:@bob", "m:@bob"])
        // 同位置：更长的优先；再相同：先添加的优先
        XCTAssertEqual(describe(TagRichParser.resolve("abcd", rules: [rule("s", "ab"), rule("l", "abc")])), ["l:abc"])
        XCTAssertEqual(describe(TagRichParser.resolve("abcd", rules: [rule("x", "ab"), rule("y", "ab")])), ["x:ab"])
        // 相邻不算重叠
        XCTAssertEqual(describe(TagRichParser.resolve("abcd", rules: [rule("a", "ab"), rule("c", "cd")])), ["a:ab", "c:cd"])
        // 结果按位置排序，index 连续
        let matches = TagRichParser.resolve("x1 y2 x3", rules: [rule("y", "y\\d", priority: 5), rule("x", "x\\d")])
        XCTAssertEqual(describe(matches), ["x:x1", "y:y2", "x:x3"])
        XCTAssertEqual(matches.map { $0.index }, [0, 1, 2])
    }

    func testParserHandlesManyMatchesQuickly() {
        let text = String(repeating: "@user #tag# word ", count: 5000)
        let rules = [rule("m", "@\\w+"), rule("t", "#\\w+#"), rule("w", "\\w+", priority: -1)]
        let start = CFAbsoluteTimeGetCurrent()
        let matches = TagRichParser.resolve(text, rules: rules)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertEqual(matches.count, 15000)
        XCTAssertLessThan(elapsed, 1.0, "15000 个命中应在 1 秒内完成（原 O(n²) 实现需要数秒）")
    }

    // MARK: 渲染缓存

    private final class Counter { var mention = 0; var box = 0 }

    /// 两条规则：@提及（文字）与 [box]（自定义 View），统计 handler 调用次数
    private func makeLabel(_ counter: Counter, text: String = "Hi @alice and [box], cc @bob") -> ZLRichLabel {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        label.numberOfLines = 0
        label.update { v in
            try? v.addRule(name: "mention", pattern: "@\\w+") { ctx in
                counter.mention += 1
                ctx.addAttributes([.foregroundColor: UIColor.blue])
                ctx.onTap = {}
            }
            try? v.addRule(name: "box", pattern: "\\[box\\]") { ctx in
                counter.box += 1
                let view = UIView()
                ctx.attributedString.setAttributedString(
                    ctx.attachmentString(for: HTagWidget(view: view, size: CGSize(width: 20, height: 10))))
            }
            v.text = text
        }
        return label
    }

    private func attachmentViews(_ label: ZLRichLabel) -> [UIView] {
        return label.subviews.filter { type(of: $0) == UIView.self }
    }

    func testHighlightStyleChangeReusesRenderedMatches() {
        let counter = Counter()
        let label = makeLabel(counter)
        XCTAssertEqual(counter.mention, 2)
        XCTAssertEqual(counter.box, 1)
        let view = attachmentViews(label).first

        label.highlightStyle = [.backgroundColor: UIColor.yellow]
        label.truncationToken = NSAttributedString(string: "…more")
        XCTAssertEqual(counter.mention, 2, "按下高亮 / 省略符不影响 handler 输出，不应重新执行")
        XCTAssertEqual(counter.box, 1)
        XCTAssertTrue(attachmentViews(label).first === view, "自定义 View 应复用，不重建")
        XCTAssertEqual(attachmentViews(label).count, 1)
        XCTAssertEqual(label.statistics.reusedMatches, 6)
    }

    func testStyleChangeAndRebuildRerunAllHandlers() {
        let counter = Counter()
        let label = makeLabel(counter)
        label.style = [.font: UIFont.systemFont(ofSize: 18)]
        XCTAssertEqual(counter.mention, 4)
        XCTAssertEqual(counter.box, 2)
        label.rebuild()
        XCTAssertEqual(counter.mention, 6)
        XCTAssertEqual(counter.box, 3)
        XCTAssertEqual(attachmentViews(label).count, 1, "旧 View 应被移除")
    }

    func testTextChangeOnlyRendersChangedMatches() {
        let counter = Counter()
        let label = makeLabel(counter)
        let view = attachmentViews(label).first
        // 在末尾追加：前面的命中位置、序号不变，直接复用
        label.text = "Hi @alice and [box], cc @bob and @carol"
        XCTAssertEqual(counter.mention, 3, "只有新增的 @carol 执行 handler")
        XCTAssertEqual(counter.box, 1)
        XCTAssertTrue(attachmentViews(label).first === view)
        XCTAssertEqual(label.text as? String, "Hi @alice and \u{FFFC}, cc @bob and @carol")
        XCTAssertEqual(label.links.count, 3, "复用的命中点击仍然有效")

        // 在开头插入：后面的命中位置变化，重新渲染
        label.text = "Hey Hi @alice and [box], cc @bob and @carol"
        XCTAssertEqual(counter.mention, 6)
        XCTAssertEqual(counter.box, 2)
        XCTAssertEqual(attachmentViews(label).count, 1)
    }

    func testSetNeedsRebuildForRuleOnlyRerunsThatRule() {
        let counter = Counter()
        let label = makeLabel(counter)
        let view = attachmentViews(label).first
        label.setNeedsRebuild(forRuleNamed: "mention")
        XCTAssertEqual(counter.mention, 4)
        XCTAssertEqual(counter.box, 1)
        XCTAssertTrue(attachmentViews(label).first === view)
    }

    func testTagConfigOnlyRerunsTagRule() {
        var mentions = 0
        var widgets = 0
        let label = ZLTagRichLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        label.update { v in
            try? v.addRule(name: "mention", pattern: "@\\w+", priority: 10) { _ in mentions += 1 }
            v.tagWidgetBuilder = { info, _ in
                widgets += 1
                return info.name == "h2" ? HTagWidget(view: UIView(), size: CGSize(width: 8, height: 8), position: .after) : nil
            }
            v.text = "<h1>A</h1> @bob <h2>B</h2>"
        }
        XCTAssertEqual(mentions, 1)
        XCTAssertEqual(widgets, 2)

        label.tagStyles = ["h1": [.foregroundColor: UIColor.red]]
        label.onTagTap = { _ in }
        XCTAssertEqual(mentions, 1, "标签配置变化不应重新执行自定义规则")
        XCTAssertEqual(widgets, 6)
        XCTAssertEqual(label.links.count, 2, "设置 onTagTap 后两个标签都可点击")

        // 前面的标签被删掉：后面标签的序号变化，需要重新渲染
        label.text = "@bob <h2>B</h2>"
        XCTAssertEqual(label.tags.map { $0.index }, [0])
    }

    func testDynamicTypeNotAppliedTwiceOnReusedAttachments() {
        final class LargeTextLabel: ZLRichLabel {
            override var traitCollection: UITraitCollection {
                return UITraitCollection(traitsFrom: [super.traitCollection,
                                                      UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)])
            }
        }
        let label = LargeTextLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        label.numberOfLines = 0
        label.update { v in
            v.adjustsFontForContentSizeCategory = true
            v.style = [.font: UIFont.systemFont(ofSize: 15)]
            try? v.addRule(name: "box", pattern: "\\[box\\]") { ctx in
                ctx.attributedString.setAttributedString(ctx.attachmentString(
                    for: HTagWidget(view: UIView(), size: CGSize(width: 20, height: 20), alignment: .top)))
            }
            v.text = "a [box] b"
        }
        let first = label.sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        label.highlightStyle = [.backgroundColor: UIColor.yellow] // 复用缓存再渲染一次
        label.highlightStyle = [:]
        let second = label.sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertEqual(first, second, "复用的自定义 View 不应被重复缩放")
    }

    // MARK: 排版缓存

    func testSizeThatFitsIsCached() {
        let counter = Counter()
        let label = makeLabel(counter)
        label.statistics.reset()
        let fitting = CGSize(width: 120, height: CGFloat.greatestFiniteMagnitude)
        let size = label.sizeThatFits(fitting)
        for _ in 0..<10 { XCTAssertEqual(label.sizeThatFits(fitting), size) }
        _ = label.intrinsicContentSize
        XCTAssertLessThanOrEqual(label.statistics.framesetterCreations, 1)
        XCTAssertGreaterThanOrEqual(label.statistics.sizeCacheHits, 10)

        // 内容变化后缓存失效，结果随之变化
        label.text = "Hi @alice and [box], cc @bob and a much longer tail that wraps onto more lines"
        XCTAssertGreaterThan(label.sizeThatFits(fitting).height, size.height)
    }
}

/// 展开 / 收起
class ExpandCollapseTests: XCTestCase {

    final class Box { var value = 0 }

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    private let longText = "Swift is a powerful and intuitive programming language for all Apple platforms. "
        + "It is easy to get started using Swift, with a concise yet expressive syntax and modern features "
        + "developers love. Swift code is safe by design and produces software that runs lightning-fast. @alice"

    private func makeLabel(text: String, handlerCalls: Box? = nil) -> ZLRichLabel {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 220, height: 0))
        label.numberOfLines = 2
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 15)]
            v.expandToken = NSAttributedString(string: "… 全文", attributes: [.foregroundColor: UIColor.blue])
            v.collapseToken = NSAttributedString(string: " 收起", attributes: [.foregroundColor: UIColor.blue])
            try? v.addRule(name: "mention", pattern: "@\\w+") { ctx in
                handlerCalls?.value += 1
                ctx.onTap = {}
            }
            v.text = text
        }
        window.addSubview(label)
        fit(label)
        return label
    }

    private func fit(_ label: ZLRichLabel) {
        let size = label.sizeThatFits(CGSize(width: 220, height: CGFloat.greatestFiniteMagnitude))
        label.frame = CGRect(x: 0, y: 0, width: 220, height: size.height)
        label.setNeedsLayout()
        label.layoutIfNeeded()
    }

    func testTruncatedShowsExpandTokenOnLastLine() {
        let label = makeLabel(text: longText)
        XCTAssertTrue(label.isTruncated)
        XCTAssertFalse(label.isExpanded)
        let rect = label.expandTokenRect
        XCTAssertFalse(rect.isEmpty, "被截断时应计算出「展开」按钮区域")
        XCTAssertGreaterThan(rect.midY, label.bounds.height / 2, "按钮在最后一行")
        XCTAssertGreaterThan(rect.midX, label.bounds.width / 2, "按钮在行尾")
        XCTAssertLessThanOrEqual(rect.maxX, label.bounds.width + 8)
        XCTAssertTrue(label.attributedTruncationToken.string == "… 全文")
    }

    func testShortTextIsNotTruncated() {
        let label = makeLabel(text: "Short @bob")
        XCTAssertFalse(label.isTruncated)
        XCTAssertEqual(label.expandTokenRect, .zero)
        XCTAssertFalse((label.attributedText?.string ?? "").hasSuffix("收起"))
    }

    func testToggleExpandAndCollapse() {
        let calls = Box()
        let label = makeLabel(text: longText, handlerCalls: calls)
        let collapsedHeight = label.bounds.height
        XCTAssertEqual(calls.value, 1)

        var changes: [Bool] = []
        label.onExpandChanged = { changes.append($0) }

        label.toggleExpanded()
        fit(label)
        XCTAssertTrue(label.isExpanded)
        XCTAssertEqual(changes, [true])
        XCTAssertEqual(label.numberOfLines, 0, "展开时显示全部")
        XCTAssertEqual(label.collapsedNumberOfLines, 2, "设置的行数保留")
        XCTAssertGreaterThan(label.bounds.height, collapsedHeight)
        XCTAssertFalse(label.isTruncated)
        XCTAssertEqual(label.expandTokenRect, .zero)
        XCTAssertTrue(label.attributedText.string.hasSuffix(" 收起"), "展开后末尾显示「收起」")
        XCTAssertEqual(label.links.count, 2, "@alice + 收起")
        XCTAssertEqual(calls.value, 1, "展开 / 收起只重新拼装，不重新执行 handler")

        // 点击「收起」链接
        // TTT 的 links 只保存 NSTextCheckingResult，链接对象在 linkModels 中
        let models = (label.value(forKey: "linkModels") as? [Any]) ?? []
        let collapseLink = models.compactMap { $0 as? TTTAttributedLabelLink }
            .max { $0.result.range.location < $1.result.range.location }
        collapseLink?.linkTapBlock?(label, collapseLink!)
        fit(label)
        XCTAssertFalse(label.isExpanded)
        XCTAssertEqual(changes, [true, false])
        XCTAssertEqual(label.numberOfLines, 2)
        XCTAssertEqual(label.bounds.height, collapsedHeight)
        XCTAssertTrue(label.isTruncated)
        XCTAssertFalse(label.expandTokenRect.isEmpty)
    }

    func testSettingIsExpandedDirectlyDoesNotNotify() {
        let label = makeLabel(text: longText)
        var notified = false
        label.onExpandChanged = { _ in notified = true }
        label.isExpanded = true
        label.isExpanded = false
        XCTAssertFalse(notified, "直接设置（例如 cell 复用）不回调")
    }

    func testNoCollapseTokenMeansNoCollapseLink() {
        let label = makeLabel(text: longText)
        label.collapseToken = nil
        label.isExpanded = true
        fit(label)
        XCTAssertFalse(label.attributedText.string.hasSuffix("收起"))
        XCTAssertEqual(label.links.count, 1)
    }
}

/// 长按 / 双击 / 按坐标定位 / 扩大点击热区
class GestureTests: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    private func makeLabel(lineSpacing: CGFloat = 0) -> ZLRichLabel {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 0))
        label.numberOfLines = 0
        label.update { v in
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = lineSpacing
            v.style = [.font: UIFont.systemFont(ofSize: 15), .paragraphStyle: paragraph]
            try? v.addRule(name: "mention", pattern: "@\\w+") { ctx in
                ctx.setText("👤" + ctx.matchedText.dropFirst(), attributes: [.foregroundColor: UIColor.purple])
                ctx.onTap = {}
            }
            v.text = "Hi @alice, this is a long sentence that wraps onto the next line for testing."
        }
        window.addSubview(label)
        let size = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
        label.frame = CGRect(x: 0, y: 0, width: 200, height: size.height)
        label.layoutIfNeeded()
        return label
    }

    /// 扫描整个 label，返回第一个落在命中上的点
    private func pointOnMatch(_ label: ZLRichLabel) -> CGPoint? {
        for y in stride(from: CGFloat(1), to: label.bounds.height, by: 2) {
            for x in stride(from: CGFloat(1), to: label.bounds.width, by: 2) {
                let p = CGPoint(x: x, y: y)
                if label.match(at: p) != nil { return p }
            }
        }
        return nil
    }

    func testCharacterIndexAndMatchAtPoint() {
        let label = makeLabel()
        let display = label.attributedText.string as NSString
        var sawPlain = false
        for y in stride(from: CGFloat(1), to: label.bounds.height, by: 3) {
            for x in stride(from: CGFloat(1), to: label.bounds.width, by: 3) {
                let p = CGPoint(x: x, y: y)
                let index = label.characterIndex(at: p)
                guard index != NSNotFound else { continue }
                XCTAssertLessThan(index, display.length)
                let info = label.gestureInfo(at: p)
                XCTAssertEqual(info.characterIndex, index)
                if let match = info.match {
                    XCTAssertEqual(match.text, "@alice")
                    XCTAssertEqual(info.matchDisplayText, "👤alice", "展示文字是规则替换后的内容")
                } else {
                    sawPlain = true
                }
            }
        }
        XCTAssertNotNil(pointOnMatch(label), "应能定位到 @alice")
        XCTAssertTrue(sawPlain)

        // 第一个字符在左上角
        XCTAssertEqual(label.characterIndex(at: CGPoint(x: 2, y: 8)), 0)
        // 超出 bounds
        XCTAssertEqual(label.characterIndex(at: CGPoint(x: -5, y: 5)), NSNotFound)

        let info = label.gestureInfo(at: CGPoint(x: 2, y: 8))
        XCTAssertNil(info.match)
        XCTAssertEqual(info.rawText, label.rawText)
        XCTAssertEqual(info.displayText, label.attributedText.string)
    }

    func testExtendsLinkTouchArea() {
        let label = makeLabel(lineSpacing: 12)
        guard let onMatch = pointOnMatch(label) else { return XCTFail("没有找到 @alice") }
        // 从命中处往下移动，找到第一个落在行间距里（不在文字上）的点
        var gapPoint: CGPoint?
        for dy in stride(from: CGFloat(1), through: 40, by: 1) {
            let p = CGPoint(x: onMatch.x, y: onMatch.y + dy)
            if label.characterIndex(at: p) == NSNotFound { gapPoint = p; break }
        }
        guard let gap = gapPoint else { return XCTFail("没有找到行间距中的点") }

        label.extendsLinkTouchArea = false
        XCTAssertNil(label.match(at: gap))
        label.extendsLinkTouchArea = true
        XCTAssertEqual(label.match(at: gap)?.text, "@alice", "扩大热区后行间距中的点也能定位到附近的可点击命中")
    }

    func testGestureSetup() {
        let label = makeLabel()
        XCTAssertFalse(label.longPressGestureRecognizer.isEnabled, "TTT 自带的长按被替换")
        XCTAssertTrue(label.gestureRecognizers?.contains(label.richLongPressGesture) ?? false)
        XCTAssertNil(label.richDoubleTapGesture)

        label.onDoubleTap = { _ in }
        let doubleTap = label.richDoubleTapGesture
        XCTAssertNotNil(doubleTap)
        XCTAssertEqual(doubleTap?.numberOfTapsRequired, 2)
        XCTAssertTrue(label.gestureRecognizers?.contains { $0 === doubleTap } ?? false)

        label.onDoubleTap = nil
        XCTAssertNil(label.richDoubleTapGesture)
        XCTAssertFalse(label.gestureRecognizers?.contains { $0 === doubleTap } ?? true, "不需要双击时移除，避免延迟单击")
    }

    func testMatchesStayLocatableAfterCachedRender() {
        let label = makeLabel()
        guard let p = pointOnMatch(label) else { return XCTFail() }
        label.highlightStyle = [.backgroundColor: UIColor.yellow] // 复用缓存重新渲染
        label.layoutIfNeeded()
        XCTAssertEqual(label.match(at: p)?.text, "@alice")
        label.text = "plain"
        label.layoutIfNeeded()
        XCTAssertNil(label.match(at: p))
    }
}

/// 选中复制
class SelectionTests: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    /// 原文："Hi [smile] @alice, hello world"
    /// 展示："Hi \u{FFFC} 👤alice, hello world"（表情替换为图片，@ 替换为 👤）
    private func makeLabel() -> ZLRichLabel {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 0))
        label.numberOfLines = 0
        label.update { v in
            v.isSelectable = true
            v.style = [.font: UIFont.systemFont(ofSize: 15)]
            try? v.addRule(name: "emoji", pattern: "\\[smile\\]") { ctx in
                let attachment = NSTextAttachment()
                attachment.image = UIImage(systemName: "face.smiling")
                attachment.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
                ctx.attributedString.setAttributedString(NSAttributedString(attachment: attachment))
            }
            try? v.addRule(name: "mention", pattern: "@\\w+") { ctx in
                ctx.setText("👤" + ctx.matchedText.dropFirst())
            }
            v.text = "Hi [smile] @alice, hello world"
        }
        window.addSubview(label)
        let size = label.sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        label.frame = CGRect(x: 0, y: 0, width: 300, height: size.height)
        label.layoutIfNeeded()
        return label
    }

    private func range(of text: String, in label: ZLRichLabel) -> NSRange {
        return (label.attributedText.string as NSString).range(of: text)
    }

    func testRawTextMapping() {
        let label = makeLabel()
        XCTAssertEqual(label.attributedText.string, "Hi \u{FFFC} 👤alice, hello world")

        label.selectAllText()
        XCTAssertTrue(label.hasSelection)
        XCTAssertEqual(label.selectedRawText, "Hi [smile] @alice, hello world", "全选的原文与 rawText 一致")
        XCTAssertEqual(label.selectedText, "Hi  👤alice, hello world", "展示文字去掉图片占位符")

        // 普通文字逐字对应
        label.select(range: range(of: "hello", in: label))
        XCTAssertEqual(label.selectedText, "hello")
        XCTAssertEqual(label.selectedRawText, "hello")

        // 只选中命中的一部分：原文取整个命中
        label.select(range: range(of: "ali", in: label))
        XCTAssertEqual(label.selectedText, "ali")
        XCTAssertEqual(label.selectedRawText, "@alice")

        // 跨越图片
        let start = range(of: "Hi", in: label).location
        let end = NSMaxRange(range(of: "👤", in: label))
        label.select(range: NSRange(location: start, length: end - start))
        XCTAssertEqual(label.selectedRawText, "Hi [smile] @alice")
    }

    func testSelectionAppearanceAndClear() {
        let label = makeLabel()
        var changes: [NSRange] = []
        label.onSelectionChanged = { changes.append($0) }
        XCTAssertFalse(label.canBecomeFirstResponder, "没有选中时不成为第一响应者")

        let world = range(of: "world", in: label)
        label.select(range: world)
        XCTAssertEqual(label.selectedRange, world)
        XCTAssertTrue(label.canBecomeFirstResponder)
        XCTAssertTrue(label.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
        XCTAssertTrue(label.canPerformAction(#selector(UIResponderStandardEditActions.selectAll(_:)), withSender: nil))

        // 选中背景与两个拖柄
        let selectionLayer = label.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first
        XCTAssertNotNil(selectionLayer?.path)
        let rect = selectionLayer!.path!.boundingBox
        XCTAssertGreaterThan(rect.width, 10)
        // world 在单行文字的末尾：右边界与文字宽度一致
        let textWidth = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 100)).width
        XCTAssertEqual(rect.maxX, textWidth, accuracy: 1.5, "world 在行尾")
        XCTAssertGreaterThan(rect.minX, textWidth * 0.6)
        let handles = label.subviews.filter { String(describing: type(of: $0)).contains("SelectionHandle") }
        XCTAssertEqual(handles.count, 2)
        XCTAssertTrue(handles.allSatisfy { !$0.isHidden })

        // 越界会被截断
        label.select(range: NSRange(location: world.location, length: 999))
        XCTAssertEqual(label.selectedRange, world)

        label.clearSelection()
        XCTAssertFalse(label.hasSelection)
        XCTAssertNil(label.selectedText)
        XCTAssertTrue(handles.allSatisfy { $0.isHidden })
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.last?.location, NSNotFound)
    }

    func testCopyAndCallbacks() {
        let label = makeLabel()
        var copied: [(String, Bool)] = []
        label.onCopy = { copied.append(($0, $1)) }
        label.select(range: range(of: "👤alice", in: label))

        label.copySelection(raw: false)
        XCTAssertEqual(UIPasteboard.general.string, "👤alice")
        label.zl_copyRawText(nil)
        XCTAssertEqual(UIPasteboard.general.string, "@alice")
        XCTAssertEqual(copied.map { $0.0 }, ["👤alice", "@alice"])
        XCTAssertEqual(copied.map { $0.1 }, [false, true])
    }

    func testRenderClearsSelectionAndCollapseTokenExcluded() {
        let label = makeLabel()
        label.selectAllText()
        label.text = "Hi @bob"
        XCTAssertFalse(label.hasSelection, "内容变化后取消选中")

        label.collapseToken = NSAttributedString(string: " 收起")
        label.isExpanded = true
        XCTAssertTrue(label.attributedText.string.hasSuffix(" 收起"))
        label.selectAllText()
        XCTAssertEqual(label.selectedText, "Hi 👤bob", "全选不包含「收起」")
        XCTAssertEqual(label.selectedRawText, "Hi @bob")
        XCTAssertFalse(label.canPerformAction(#selector(UIResponderStandardEditActions.selectAll(_:)), withSender: nil),
                       "已全选时不显示「全选」")

        label.isSelectable = false
        XCTAssertFalse(label.hasSelection)
        XCTAssertFalse(label.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
    }
}

// MARK: - 通用标签

class TagParserTests: XCTestCase {

    private func describe(_ tags: [HTagInfo]) -> [String] {
        return tags.map { "\($0.name):\($0.text):\($0.depth)" }
    }

    func testDefaultConfigurationKeepsHTagBehavior() {
        // 不嵌套：只识别最内层
        XCTAssertEqual(describe(ZLTagParser.tags(in: "<h1>a<h2>b</h2></h1>")), ["h2:b:0"])
        // 开闭不匹配 / 未闭合：原样显示，不影响后面的标签
        XCTAssertEqual(describe(ZLTagParser.tags(in: "<h1>x</h2> and <h3>ok</h3>")), ["h3:ok:0"])
        // <h1/> 作为闭合标签
        XCTAssertEqual(describe(ZLTagParser.tags(in: "<H1>文字<h1/>")), ["h1:文字:0"])
        // 不符合标签名的当作文字
        XCTAssertEqual(describe(ZLTagParser.tags(in: "<hx>y</hx><b>z</b>")), [])
        // 与旧解析器结果一致
        let source = "agree <h1>User Agreement</h1>, <h2>Privacy<h2/> <h>x</h1> <h3>a</h3>"
        XCTAssertEqual(describe(ZLTagParser.tags(in: source)), describe(HTagParser.tags(source)))
    }

    func testAnyTagsWithAttributesAndNesting() {
        let source = "<b>粗 <color value=\"#f00\">红</color> <A HREF='https://x.com?a=1&amp;b=2' target=_blank disabled>链接</a></b><br/>"
        let tags = ZLTagParser.tags(in: source, configuration: .anyTags)
        XCTAssertEqual(describe(tags), ["b:粗 红 链接:0", "color:红:1", "a:链接:1", "br::0"])
        XCTAssertEqual(tags.map { $0.index }, [0, 1, 2, 3])
        XCTAssertTrue(tags[1].parent === tags[0])
        XCTAssertTrue(tags[2].parent === tags[0])
        XCTAssertNil(tags[3].parent)

        XCTAssertEqual(tags[2].attributes, ["href": "https://x.com?a=1&b=2", "target": "_blank", "disabled": ""])
        XCTAssertEqual(tags[2].attribute("HREF"), "https://x.com?a=1&b=2")
        XCTAssertEqual(tags[1].colorAttribute("value"), UIColor(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(tags[3].raw, "<br/>")
        XCTAssertEqual(HTagInfo.color(from: "blue"), .systemBlue)
        XCTAssertNil(HTagInfo.color(from: "#12"))
    }

    func testNestingTolerance() {
        // 内层未闭合：外层闭合时放弃内层（原样显示）
        let tags = ZLTagParser.tags(in: "<b>a <i>b</b> <i>c</i>", configuration: .anyTags)
        XCTAssertEqual(describe(tags), ["b:a <i>b:0", "i:c:0"])
        // 多余的闭合标签当作文字
        XCTAssertEqual(describe(ZLTagParser.tags(in: "</b><b>x</b></i>", configuration: .anyTags)), ["b:x:0"])
        // 不允许自闭合时 <br/> 当作文字
        var config = ZLTagParserConfiguration.anyTags
        config.allowsSelfClosing = false
        XCTAssertEqual(describe(ZLTagParser.tags(in: "a<br/>b", configuration: config)), [])
    }

    // MARK: Label

    private func makeLabel(_ text: String, taps: @escaping (HTagInfo) -> Void) -> ZLTagRichLabel {
        let label = ZLTagRichLabel(frame: CGRect(x: 0, y: 0, width: 320, height: 0))
        label.numberOfLines = 0
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.darkGray]
            v.tagConfiguration = .anyTags
            v.tagStyles = ["b": [.font: UIFont.boldSystemFont(ofSize: 15)]]
            v.tagStyleBuilder = { info in
                info.colorAttribute("value").map { [.foregroundColor: $0] }
            }
            v.onTagTap = taps
            v.text = text
        }
        let size = label.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        label.frame.size.height = size.height
        return label
    }

    /// 与 TTT 一致：倒序查找，后添加的链接优先
    private func tap(_ label: ZLTagRichLabel, at index: Int) {
        let models = ((label.value(forKey: "linkModels") as? [Any]) ?? []).compactMap { $0 as? TTTAttributedLabelLink }
        guard let link = models.last(where: { NSLocationInRange(index, $0.result.range) }) else {
            return XCTFail("no link at \(index)")
        }
        link.linkTapBlock?(label, link)
    }

    func testLabelRendersNestedTagsWithInheritedStyle() {
        var tapped: [String] = []
        let label = makeLabel("Hi <b>粗 <color value=\"red\">红</color></b>!", taps: { tapped.append($0.name) })
        let display = label.attributedText.string as NSString
        XCTAssertEqual(display as String, "Hi 粗 红!")
        XCTAssertEqual(label.tags.map { $0.name }, ["b", "color"])

        let red = display.range(of: "红").location
        let attrs = label.attributedText.attributes(at: red, effectiveRange: nil)
        XCTAssertEqual(attrs[.foregroundColor] as? UIColor, .systemRed, "内层颜色")
        let font = attrs[.font] as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false, "继承外层粗体")

        let boldOnly = display.range(of: "粗").location
        XCTAssertEqual(label.attributedText.attribute(.foregroundColor, at: boldOnly, effectiveRange: nil) as? UIColor,
                       .darkGray)

        // 点内层触发内层，点外层触发外层
        tap(label, at: red)
        tap(label, at: boldOnly)
        XCTAssertEqual(tapped, ["color", "b"])
    }

    func testDefaultLabelStillOnlyParsesHTags() {
        let label = ZLTagRichLabel(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        label.text = "<b>x</b> <h1>y</h1>"
        XCTAssertEqual(label.attributedText.string, "<b>x</b> y")
        XCTAssertEqual(label.tags.map { $0.name }, ["h1"])
    }
}

// MARK: - 胶囊背景 / 渐变文字

class DecorationTests: XCTestCase {

    private let occurrenceKey = NSAttributedString.Key("ZLRichLabelBackgroundOccurrence")

    private func makeLabel(_ text: String, background: ZLTextBackground? = nil,
                           gradient: ZLTextGradient? = nil) -> ZLRichLabel {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 0))
        label.numberOfLines = 0
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black]
            try? v.addRule(name: "topic", pattern: "#\\w+#") { ctx in
                if let background = background { ctx.addAttributes([.zlBackground: background]) }
                if let gradient = gradient { ctx.addAttributes([.zlGradient: gradient]) }
            }
            v.text = text
        }
        let size = label.sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        label.frame.size.height = ceil(size.height) + 4
        return label
    }

    private func kern(_ label: ZLRichLabel, at index: Int) -> Double {
        return (label.attributedText.attribute(.kern, at: index, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
    }

    /// 渲染为 1x 位图，统计满足条件的像素数
    private func countPixels(_ label: ZLRichLabel, where match: (UInt8, UInt8, UInt8, UInt8) -> Bool) -> Int {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: label.bounds, format: format).image { context in
            UIColor.white.setFill()
            context.fill(label.bounds)
            label.layer.render(in: context.cgContext)
        }
        guard let cg = image.cgImage else { return 0 }
        let width = cg.width, height = cg.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for i in stride(from: 0, to: data.count, by: 4) where match(data[i], data[i + 1], data[i + 2], data[i + 3]) {
            count += 1
        }
        return count
    }

    func testBackgroundReservesPaddingWithKern() {
        let background = ZLTextBackground(fillColor: .red, padding: UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6),
                                          margin: 2)
        let plain = makeLabel("Hi #swift##ios# end")
        let label = makeLabel("Hi #swift##ios# end", background: background)
        let display = label.attributedText.string as NSString
        XCTAssertEqual(display as String, "Hi #swift##ios# end", "只改属性，不插入字符")

        let first = display.range(of: "#swift#")
        let second = display.range(of: "#ios#")
        XCTAssertEqual(kern(label, at: first.location - 1), 8, "前一个字符：padding.left + margin")
        XCTAssertEqual(kern(label, at: NSMaxRange(first) - 1), 16, "前一个胶囊的结尾 + 后一个胶囊的开头")
        XCTAssertEqual(kern(label, at: NSMaxRange(second) - 1), 8)

        // 相邻的两个命中是两个胶囊
        var occurrences: [NSRange] = []
        label.attributedText.enumerateAttribute(occurrenceKey, in: NSRange(location: 0, length: display.length)) { value, range, _ in
            if value != nil { occurrences.append(range) }
        }
        XCTAssertEqual(occurrences, [first, second])

        let plainWidth = plain.sizeThatFits(CGSize(width: 1000, height: 100)).width
        let width = label.sizeThatFits(CGSize(width: 1000, height: 100)).width
        XCTAssertEqual(width - plainWidth, 32, accuracy: 0.5, "两个胶囊各占 2 × (6 + 2)")
    }

    /// 紧挨着的两个胶囊不能重叠：前一个胶囊最后一个字符上的 kern 还包含了后一个胶囊的前侧空间
    func testAdjacentCapsulesDoNotOverlap() {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.clear]
            try? v.addRule(name: "topic", pattern: "#[^#\\s]+#") { ctx in
                ctx.addAttributes([.zlBackground: ZLTextBackground(fillColor: UIColor.red.withAlphaComponent(0.5))])
            }
            v.text = "Hi #SwiftUI##UIKit# end"
        }
        // 单层：白底上的半透明红 ≈ (255, 128, 128)；两层重叠 ≈ (255, 64, 64)
        let single = countPixels(label) { r, g, b, _ in r > 240 && g > 110 && g < 150 && b > 110 && b < 150 }
        let overlap = countPixels(label) { r, g, b, _ in r > 200 && g < 100 && b < 100 }
        XCTAssertGreaterThan(single, 200, "两个胶囊都画出来了")
        XCTAssertEqual(overlap, 0, "两个胶囊没有重叠")
    }

    func testBackgroundAtParagraphStartUsesHeadIndent() {
        let label = makeLabel("#swift# first\n#ios# second", background: ZLTextBackground(fillColor: .red))
        let display = label.attributedText.string as NSString
        for location in [0, display.range(of: "#ios#").location] {
            let style = label.attributedText.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            XCTAssertEqual(style?.firstLineHeadIndent, 8, "段落开头：用首行缩进预留 padding.left + margin")
        }
    }

    func testBackgroundIsDrawn() {
        let isRed: (UInt8, UInt8, UInt8, UInt8) -> Bool = { r, g, b, _ in r > 240 && g < 20 && b < 20 }
        XCTAssertEqual(countPixels(makeLabel("Hi #swift# end"), where: isRed), 0)
        let label = makeLabel("Hi #swift# end", background: ZLTextBackground(fillColor: .red))
        XCTAssertGreaterThan(countPixels(label, where: isRed), 200, "画出了红色背景")
    }

    func testGradientTextIsDrawnInsteadOfOriginalColor() {
        let isGreen: (UInt8, UInt8, UInt8, UInt8) -> Bool = { r, g, b, _ in g > 200 && r < 60 && b < 60 }
        let isDark: (UInt8, UInt8, UInt8, UInt8) -> Bool = { r, g, b, _ in r < 60 && g < 60 && b < 60 }
        let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)

        let plain = makeLabel("#gradient#")
        XCTAssertGreaterThan(countPixels(plain, where: isDark), 20)

        let label = makeLabel("#gradient#", gradient: ZLTextGradient(colors: [green, green]))
        XCTAssertEqual(label.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .clear)
        XCTAssertGreaterThan(countPixels(label, where: isGreen), 20, "字形区域填充了渐变")
        XCTAssertEqual(countPixels(label, where: isDark), 0, "原来的黑色文字不再绘制")
    }
}

// MARK: - SwiftUI

import SwiftUI

class RichTextSwiftUITests: XCTestCase {

    final class Model: ObservableObject {
        @Published var text: String
        init(_ text: String) { self.text = text }
    }

    struct Host: View {
        @ObservedObject var model: Model
        var lineLimit: Int?
        var configure: ZLRichText.Configure?
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ZLRichText(model.text, configure: configure)
                    .lineLimit(lineLimit)
                Spacer(minLength: 0)
            }
            .frame(width: 300)
        }
    }

    private var window: UIWindow!
    private let shortText = "Agree to <h1>User Agreement</h1>"
    private let longText = String(repeating: "A long sentence that wraps onto several lines. ", count: 6)

    override func setUp() {
        super.setUp()
        // 必须挂到 windowScene 上：脱离场景的 UIWindow 不显示，SwiftUI 不会提交后续的布局更新
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 800)
    }

    override func tearDown() {
        ZLRichText._usesLegacySizing = false
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    private func spin(_ times: Int = 5) {
        for _ in 0..<times {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.rootViewController?.view.layoutIfNeeded()
        }
    }

    private func host(_ view: Host) -> ZLTagRichLabel? {
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        spin()
        return findLabel(in: window)
    }

    private func findLabel(in view: UIView) -> ZLTagRichLabel? {
        if let label = view as? ZLTagRichLabel { return label }
        for sub in view.subviews { if let found = findLabel(in: sub) { return found } }
        return nil
    }

    private func expectedHeight(_ label: ZLRichLabel) -> CGFloat {
        return ceil(label.sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)).height)
    }

    private func checkAutoHeight(file: StaticString = #filePath, line: UInt = #line) {
        let model = Model(shortText)
        guard let label = host(Host(model: model)) else { return XCTFail("no label", file: file, line: line) }
        XCTAssertEqual(label.attributedText.string, "Agree to User Agreement", file: file, line: line)
        let oneLine = label.bounds.height
        XCTAssertGreaterThan(oneLine, 10, file: file, line: line)
        XCTAssertEqual(oneLine, expectedHeight(label), accuracy: 1, file: file, line: line)

        model.text = longText
        spin()
        XCTAssertGreaterThan(label.bounds.height, oneLine * 3, "文字变长后高度增加", file: file, line: line)
        XCTAssertEqual(label.bounds.height, expectedHeight(label), accuracy: 1, file: file, line: line)
    }

    func testAutoHeight() {
        checkAutoHeight()
    }

    func testLegacyAutoHeight() {
        ZLRichText._usesLegacySizing = true
        checkAutoHeight()
    }

    func testInternalChangeUpdatesHeight() {
        for legacy in [false, true] {
            ZLRichText._usesLegacySizing = legacy
            let model = Model(longText)
            let host = Host(model: model, configure: { label in
                label.numberOfLines = 2
                label.expandToken = NSAttributedString(string: "… 全文")
            })
            guard let label = self.host(host) else { return XCTFail("no label") }
            let collapsed = label.bounds.height
            XCTAssertTrue(label.isTruncated, "legacy=\(legacy)")

            label.toggleExpanded()     // 只改了 label 内部状态，SwiftUI 不知道
            spin()
            XCTAssertGreaterThan(label.bounds.height, collapsed * 2, "展开后 SwiftUI 重新计算了高度 legacy=\(legacy)")
            XCTAssertEqual(label.bounds.height, expectedHeight(label), accuracy: 1, "legacy=\(legacy)")
        }
    }

    func testLineLimitAndConfigureRunsOnce() {
        var configureCalls = 0
        let model = Model(longText)
        let host = Host(model: model, lineLimit: 1, configure: { label in
            configureCalls += 1
            try? label.addRule(name: "agree", pattern: "sentence") { ctx in
                ctx.addAttributes([.foregroundColor: UIColor.red])
            }
        })
        guard let label = self.host(host) else { return XCTFail("no label") }
        XCTAssertEqual(label.numberOfLines, 1)
        XCTAssertEqual(label.bounds.height, expectedHeight(label), accuracy: 1)

        model.text = longText + " more sentence"
        spin()
        XCTAssertEqual(configureCalls, 1, "configure 只执行一次")
        XCTAssertEqual(label.rules.count, 1, "规则没有重复添加")
    }
}
