import XCTest
import ZLRichLabel

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
    private func makeLabel(widget: @escaping () -> ZLRichWidget) -> ZLRichLabel {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 0))
        label.numberOfLines = 0
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 15)]
            try? v.addRule(name: "box", pattern: "\\[box\\]") { ctx in
                ctx.attributedString.setAttributedString(ctx.attachmentString(for: widget()))
            }
            try? v.addRule(name: "mention", pattern: "@x") { ctx in
                ctx.onTap = { _ in }
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
        let label = makeLabel { ZLRichWidget(view: box, size: CGSize(width: 20, height: 14)) }
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
        let label = makeLabel { ZLRichWidget(view: badge) }   // size == .zero 自动计算
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
        let label = makeLabel { ZLRichWidget(view: container, size: CGSize(width: 20, height: 14)) }

        container.bounds.size = CGSize(width: 60, height: 14)
        inner.zl_setNeedsRichLabelLayout()
        label.layoutIfNeeded()

        XCTAssertEqual(container.frame.size, CGSize(width: 60, height: 14))
    }

    /// 固定尺寸且未被外部修改：invalidate 不改变尺寸
    func testFixedSizeUnchangedWithoutExternalChange() {
        let box = UIView()
        let label = makeLabel { ZLRichWidget(view: box, size: CGSize(width: 20, height: 14)) }
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

    private func rule(_ name: String, _ pattern: String, priority: Int = 0) -> ZLRichRule {
        return try! ZLRichRule(name: name, pattern: pattern, priority: priority) { _ in }
    }

    private func describe(_ matches: [ZLRichMatch]) -> [String] {
        return matches.map { "\($0.rule.name):\($0.text)" }
    }

    func testParserResolvesOverlapsByPriority() {
        let text = "aa @bob #topic @bob# bb"
        // 同优先级：位置靠前优先
        XCTAssertEqual(describe(ZLRichParser.resolve(text, rules: [rule("m", "@\\w+"), rule("t", "#[^#]+#")])),
                       ["m:@bob", "t:#topic @bob#"])
        // 优先级高的先占位，被它覆盖的低优先级命中作废
        XCTAssertEqual(describe(ZLRichParser.resolve(text, rules: [rule("m", "@\\w+", priority: 10), rule("t", "#[^#]+#")])),
                       ["m:@bob", "m:@bob"])
        // 同位置：更长的优先；再相同：先添加的优先
        XCTAssertEqual(describe(ZLRichParser.resolve("abcd", rules: [rule("s", "ab"), rule("l", "abc")])), ["l:abc"])
        XCTAssertEqual(describe(ZLRichParser.resolve("abcd", rules: [rule("x", "ab"), rule("y", "ab")])), ["x:ab"])
        // 相邻不算重叠
        XCTAssertEqual(describe(ZLRichParser.resolve("abcd", rules: [rule("a", "ab"), rule("c", "cd")])), ["a:ab", "c:cd"])
        // 结果按位置排序，index 连续
        let matches = ZLRichParser.resolve("x1 y2 x3", rules: [rule("y", "y\\d", priority: 5), rule("x", "x\\d")])
        XCTAssertEqual(describe(matches), ["x:x1", "y:y2", "x:x3"])
        XCTAssertEqual(matches.map { $0.index }, [0, 1, 2])
    }

    func testParserHandlesManyMatchesQuickly() {
        let text = String(repeating: "@user #tag# word ", count: 5000)
        let rules = [rule("m", "@\\w+"), rule("t", "#\\w+#"), rule("w", "\\w+", priority: -1)]
        let start = CFAbsoluteTimeGetCurrent()
        let matches = ZLRichParser.resolve(text, rules: rules)
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
                ctx.onTap = { _ in }
            }
            try? v.addRule(name: "box", pattern: "\\[box\\]") { ctx in
                counter.box += 1
                let view = UIView()
                ctx.attributedString.setAttributedString(
                    ctx.attachmentString(for: ZLRichWidget(view: view, size: CGSize(width: 20, height: 10))))
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
        XCTAssertEqual(label.text, "Hi @alice and \u{FFFC}, cc @bob and @carol")
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
                return info.name == "h2" ? ZLRichWidget(view: UIView(), size: CGSize(width: 8, height: 8), position: .after) : nil
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
                    for: ZLRichWidget(view: UIView(), size: CGSize(width: 20, height: 20), alignment: .top)))
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
                ctx.onTap = { _ in }
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
        XCTAssertTrue(label.attributedTruncationToken?.string == "… 全文")
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
        XCTAssertTrue(label.attributedText!.string.hasSuffix(" 收起"), "展开后末尾显示「收起」")
        XCTAssertEqual(label.links.count, 2, "@alice + 收起")
        XCTAssertEqual(calls.value, 1, "展开 / 收起只重新拼装，不重新执行 handler")

        // 点击「收起」链接
        let collapseLink = label.links.max { $0.range.location < $1.range.location }
        label.performTap(on: collapseLink!)
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
        XCTAssertFalse(label.attributedText!.string.hasSuffix("收起"))
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
                ctx.onTap = { _ in }
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
        let display = label.attributedText!.string as NSString
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
        XCTAssertEqual(info.displayText, label.attributedText!.string)
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
        return (label.attributedText!.string as NSString).range(of: text)
    }

    func testRawTextMapping() {
        let label = makeLabel()
        XCTAssertEqual(label.attributedText!.string, "Hi \u{FFFC} 👤alice, hello world")

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
        XCTAssertTrue(label.attributedText!.string.hasSuffix(" 收起"))
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

    private func describe(_ tags: [ZLTagInfo]) -> [String] {
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
        XCTAssertEqual(describe(ZLTagParser.tags(in: source)), describe(ZLTagParser.tags(source)))
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
        XCTAssertEqual(ZLTagInfo.color(from: "blue"), .systemBlue)
        XCTAssertNil(ZLTagInfo.color(from: "#12"))
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

    private func makeLabel(_ text: String, taps: @escaping (ZLTagInfo) -> Void) -> ZLTagRichLabel {
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

    /// 倒序查找，后添加的链接优先
    private func tap(_ label: ZLTagRichLabel, at index: Int) {
        guard let link = label.link(atCharacter: index) else {
            return XCTFail("no link at \(index)")
        }
        label.performTap(on: link)
    }

    func testLabelRendersNestedTagsWithInheritedStyle() {
        var tapped: [String] = []
        let label = makeLabel("Hi <b>粗 <color value=\"red\">红</color></b>!", taps: { tapped.append($0.name) })
        let display = label.attributedText!.string as NSString
        XCTAssertEqual(display as String, "Hi 粗 红!")
        XCTAssertEqual(label.tags.map { $0.name }, ["b", "color"])

        let red = display.range(of: "红").location
        let attrs = label.attributedText!.attributes(at: red, effectiveRange: nil)
        XCTAssertEqual(attrs[.foregroundColor] as? UIColor, .systemRed, "内层颜色")
        let font = attrs[.font] as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false, "继承外层粗体")

        let boldOnly = display.range(of: "粗").location
        XCTAssertEqual(label.attributedText!.attribute(.foregroundColor, at: boldOnly, effectiveRange: nil) as? UIColor,
                       .darkGray)

        // 点内层触发内层，点外层触发外层
        tap(label, at: red)
        tap(label, at: boldOnly)
        XCTAssertEqual(tapped, ["color", "b"])
    }

    func testDefaultLabelStillOnlyParsesHTags() {
        let label = ZLTagRichLabel(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        label.text = "<b>x</b> <h1>y</h1>"
        XCTAssertEqual(label.attributedText!.string, "<b>x</b> y")
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
        return (label.attributedText!.attribute(.kern, at: index, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
    }

    /// 渲染为 1x 位图，统计满足条件的像素数
    private func countPixels(_ label: ZLRichLabel, where match: (UInt8, UInt8, UInt8, UInt8) -> Bool) -> Int {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard   // 8 位 RGBA，按 4 字节读取像素
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
        let display = label.attributedText!.string as NSString
        XCTAssertEqual(display as String, "Hi #swift##ios# end", "只改属性，不插入字符")

        let first = display.range(of: "#swift#")
        let second = display.range(of: "#ios#")
        XCTAssertEqual(kern(label, at: first.location - 1), 8, "前一个字符：padding.left + margin")
        XCTAssertEqual(kern(label, at: NSMaxRange(first) - 1), 16, "前一个胶囊的结尾 + 后一个胶囊的开头")
        XCTAssertEqual(kern(label, at: NSMaxRange(second) - 1), 8)

        // 相邻的两个命中是两个胶囊
        var occurrences: [NSRange] = []
        label.attributedText!.enumerateAttribute(occurrenceKey, in: NSRange(location: 0, length: display.length)) { value, range, _ in
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
        let display = label.attributedText!.string as NSString
        for location in [0, display.range(of: "#ios#").location] {
            let style = label.attributedText!.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
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
        XCTAssertEqual(label.attributedText!.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .clear)
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
        XCTAssertEqual(label.attributedText!.string, "Agree to User Agreement", file: file, line: line)
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

// MARK: - 点击回调传入命中

class TapCallbackTests: XCTestCase {

    private func tapAll(_ label: ZLRichLabel) {
        for link in label.links.sorted(by: { $0.range.location < $1.range.location }) {
            label.performTap(on: link)
        }
    }

    func testOnTapReceivesCurrentMatchWithoutRetainingContext() {
        var tapped: [String] = []
        weak var weakContext: ZLRichRuleContext?
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        label.update { v in
            try? v.addRule(name: "mention", pattern: "@(\\w+)") { ctx in
                weakContext = ctx
                ctx.setText("👤" + (ctx.group(1) ?? ""))
                ctx.onTap = { match in
                    tapped.append("\(match.rule.name):\(match.text):\(match.group(1) ?? ""):\(match.index):\(match.source.prefix(2))")
                }
            }
            v.text = "Hi @alice and @bob"
        }
        XCTAssertNil(weakContext, "回调没有持有 ctx，handler 结束后 ctx 即释放")

        tapAll(label)
        XCTAssertEqual(tapped, ["mention:@alice:alice:0:Hi", "mention:@bob:bob:1:Hi"])

        // 命中位置和内容不变时复用缓存的渲染结果，点击时传入的仍是本次解析的命中
        tapped = []
        label.statistics.reset()
        label.text = "Yo @alice and @bob"
        XCTAssertEqual(label.statistics.handlerCalls, 0, "复用了缓存")
        tapAll(label)
        XCTAssertEqual(tapped, ["mention:@alice:alice:0:Yo", "mention:@bob:bob:1:Yo"])
    }

    func testLinkSegmentsReceiveMatch() {
        var tapped: [String] = []
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        label.update { v in
            try? v.addRule(name: "pair", pattern: "\\[(\\w+)\\|(\\w+)\\]") { ctx in
                let first = ctx.group(1) ?? "", second = ctx.group(2) ?? ""
                ctx.setText(first + " " + second)
                ctx.addLink(range: NSRange(location: 0, length: (first as NSString).length),
                            onTap: { match in tapped.append("first:\(match.group(1) ?? "")") })
                ctx.addLink(range: NSRange(location: (first as NSString).length + 1, length: (second as NSString).length),
                            onTap: { match in tapped.append("second:\(match.group(2) ?? "")") })
            }
            v.text = "pick [left|right] now"
        }
        tapAll(label)
        XCTAssertEqual(tapped, ["first:left", "second:right"])
    }
}

// MARK: - Objective-C updateTag:

class ObjCUpdateTagTests: XCTestCase {

    func testUpdateTagPassesTagLabelAndBatchesRender() {
        let label = ZLTagRichLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        let selector = NSSelectorFromString("updateTag:")
        XCTAssertTrue(label.responds(to: selector), "OC 可以调用 updateTag:")

        // 按 OC 的方式调用：[label updateTag:^(ZLTagRichLabel *v) { ... }]
        typealias Block = @convention(block) (ZLTagRichLabel) -> Void
        typealias Function = @convention(c) (AnyObject, Selector, Block) -> Void
        let function = unsafeBitCast(label.method(for: selector), to: Function.self)

        var received: ZLTagRichLabel?
        label.statistics.reset()
        function(label, selector) { v in
            received = v
            v.tagStyle = [.foregroundColor: UIColor.red]
            v.tagStyles = ["h1": [.foregroundColor: UIColor.blue]]
            v.tagPriority = 3
            v.text = "Agree <h1>Terms</h1>"
        }
        XCTAssertTrue(received === label, "回调参数就是这个 ZLTagRichLabel")
        XCTAssertEqual(label.statistics.renders, 1, "多处修改只渲染一次")
        XCTAssertEqual(label.attributedText!.string, "Agree Terms")
        XCTAssertEqual(label.tags.map { $0.name }, ["h1"])
    }
}

// MARK: - 修复：扩大热区不覆盖普通文字 / collapseThreshold

class TouchAreaAndThresholdTests: XCTestCase {

    /// 与用例 25 一致：行间距 10，标签和 @alice 在前一行，普通文字（❤️）紧挨在下一行
    private func makeTouchLabel() -> ZLTagRichLabel {
        let label = ZLTagRichLabel(frame: CGRect(x: 0, y: 0, width: 220, height: 0))
        label.numberOfLines = 0
        label.update { v in
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 10
            v.style = [.font: UIFont.systemFont(ofSize: 15), .paragraphStyle: paragraph]
            v.extendsLinkTouchArea = true
            v.onTagTap = { _ in }
            try? v.addRule(name: "mention", pattern: "@\\w+") { ctx in ctx.onTap = { _ in } }
            v.text = "Press <h1>User Agreement</h1> or @alice for menus, double tap to like ❤️ plain words here."
        }
        let size = label.sizeThatFits(CGSize(width: 220, height: CGFloat.greatestFiniteMagnitude))
        label.frame.size.height = size.height
        label.layoutIfNeeded()
        return label
    }

    func testPlainTextNeverResolvesToNearbyLink() {
        let label = makeTouchLabel()
        let display = label.attributedText!.string as NSString
        var plainChecked = 0
        var gapExtended = 0
        for y in stride(from: CGFloat(0.5), to: label.bounds.height, by: 1) {
            for x in stride(from: CGFloat(0.5), to: label.bounds.width, by: 2) {
                let p = CGPoint(x: x, y: y)
                let index = label.characterIndex(at: p)
                if index != NSNotFound {
                    // 按在文字上：只有这个字本身属于链接 / 命中时才返回
                    let ownMatch = label.links.contains { NSLocationInRange(index, $0.range) }
                    if !ownMatch {
                        plainChecked += 1
                        XCTAssertNil(label.link(at: p), "普通文字「\(display.substring(with: NSRange(location: index, length: 1)))」不应命中附近的链接 \(p)")
                        XCTAssertNil(label.match(at: p), "普通文字不应命中附近的规则 \(p)")
                    }
                } else if label.match(at: p) != nil {
                    gapExtended += 1
                }
            }
        }
        XCTAssertGreaterThan(plainChecked, 100)
        XCTAssertGreaterThan(gapExtended, 0, "行间距 / 空白处仍然会扩大查找")
    }

    // MARK: collapseThreshold

    private let fourLines = "第一行文字内容比较长一些。第二行文字内容比较长一些。第三行文字内容比较长一些。第四行文字内容比较长。"

    private func makeExpandLabel(width: CGFloat, threshold: Int) -> ZLRichLabel {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: width, height: 0))
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 15)]
            v.numberOfLines = 3
            v.collapseThreshold = threshold
            v.expandToken = NSAttributedString(string: "… 全文")
            v.text = fourLines
        }
        let size = label.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        label.frame.size.height = size.height
        label.layoutIfNeeded()
        return label
    }

    private func totalLines(_ label: ZLRichLabel, width: CGFloat) -> Int {
        let framesetter = CTFramesetterCreateWithAttributedString(label.attributedText! as CFAttributedString)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10000), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        return (CTFrameGetLines(frame) as? [CTLine])?.count ?? 0
    }

    func testThresholdShowsAllWhenWithinLimit() {
        // 宽度 200 时大约 4 ~ 6 行：阈值设为实际行数，不折叠
        let probe = makeExpandLabel(width: 200, threshold: 0)
        let lines = totalLines(probe, width: 200)
        XCTAssertGreaterThan(lines, 3, "测试文字需要超过 3 行")
        XCTAssertTrue(probe.isTruncated, "默认（阈值 0）超过 3 行就折叠")

        let within = makeExpandLabel(width: 200, threshold: lines)
        XCTAssertFalse(within.isTruncated, "不超过阈值：完整显示")
        XCTAssertEqual(within.expandTokenRect, .zero, "不显示「全文」")
        XCTAssertEqual(within.numberOfLines, 0)
        XCTAssertEqual(within.collapsedNumberOfLines, 3, "设置的行数保留")
        XCTAssertGreaterThan(within.bounds.height, probe.bounds.height, "完整显示比折叠后高")

        let exceeded = makeExpandLabel(width: 200, threshold: lines - 1)
        XCTAssertTrue(exceeded.isTruncated, "超过阈值：折叠")
        XCTAssertEqual(exceeded.numberOfLines, 3)
        XCTAssertFalse(exceeded.expandTokenRect.isEmpty, "显示「全文」")
        XCTAssertEqual(exceeded.bounds.height, probe.bounds.height, accuracy: 0.5)
    }

    func testThresholdDependsOnWidth() {
        let label = makeExpandLabel(width: 200, threshold: 0)
        let narrowLines = totalLines(label, width: 200)
        let wideLines = totalLines(label, width: 400)
        XCTAssertGreaterThan(narrowLines, wideLines)
        label.collapseThreshold = wideLines   // 宽 400 时不超过阈值，宽 200 时超过

        let narrow = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height
        let wide = label.sizeThatFits(CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude)).height
        let font = UIFont.systemFont(ofSize: 15)
        XCTAssertEqual(Int((narrow / font.lineHeight).rounded()), 3, "窄：折叠为 3 行")
        XCTAssertEqual(Int((wide / font.lineHeight).rounded()), wideLines, "宽：完整显示")
    }

    func testExpandStillWorksWithThreshold() {
        let probe = makeExpandLabel(width: 200, threshold: 0)
        let lines = totalLines(probe, width: 200)
        let label = makeExpandLabel(width: 200, threshold: lines - 1)
        let collapsed = label.bounds.height
        label.toggleExpanded()
        let size = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertGreaterThan(size.height, collapsed)
        label.toggleExpanded()
        XCTAssertEqual(label.numberOfLines, 3)
    }
}

/// 用例 21：标签可点击（onTagTap）时，内嵌 View 自带的手势 / UIControl 仍能收到触摸
class AttachmentHitTestTests: XCTestCase {

    private func makeLabel(widget: @escaping () -> ZLRichWidget) -> ZLTagRichLabel {
        let label = ZLTagRichLabel(frame: CGRect(x: 0, y: 0, width: 260, height: 0))
        label.numberOfLines = 0
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 15)]
            v.onTagTap = { _ in }
            v.tagWidgetBuilder = { info, _ in info.name == "h1" ? widget() : nil }
            v.text = "Tap the box <h1>box</h1> to resize it, tap <h2>like</h2> to add likes."
        }
        label.frame.size.height = label.sizeThatFits(CGSize(width: 260, height: CGFloat.greatestFiniteMagnitude)).height
        label.layoutIfNeeded()
        return label
    }

    private func center(of view: UIView, in label: UIView) -> CGPoint {
        return view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: label)
    }

    func testViewWithOwnGestureReceivesTouch() {
        let box = UIView()
        box.addGestureRecognizer(UITapGestureRecognizer())
        let label = makeLabel { ZLRichWidget(view: box, size: CGSize(width: 24, height: 16), tappable: false) }
        XCTAssertFalse(box.isHidden)
        let p = center(of: box, in: label)
        XCTAssertNotNil(label.link(at: p), "前提：View 所在位置是标签链接")
        XCTAssertTrue(label.hitTest(p, with: nil) === box)
    }

    func testControlReceivesTouch() {
        let button = UIButton(type: .system)
        let label = makeLabel { ZLRichWidget(view: button, size: CGSize(width: 30, height: 16), tappable: false) }
        XCTAssertTrue(label.hitTest(center(of: button, in: label), with: nil) === button)
    }

    func testPlainViewStillHandledByLink() {
        let icon = UIView()
        let label = makeLabel { ZLRichWidget(view: icon, size: CGSize(width: 16, height: 16)) }
        // 没有自己的交互（tappable 只加内部点击）：仍由 label 处理链接点击和按下高亮
        XCTAssertTrue(label.hitTest(center(of: icon, in: label), with: nil) === label)
    }
}

/// 基类 ZLAttributedLabel：纯文本 / 富文本、链接识别、按下样式、绘制、无障碍
class AttributedLabelTests: XCTestCase {

    private func makeLabel(width: CGFloat = 300) -> ZLAttributedLabel {
        let label = ZLAttributedLabel(frame: CGRect(x: 0, y: 0, width: width, height: 0))
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 15)
        return label
    }

    private func fit(_ label: ZLAttributedLabel) {
        label.frame.size.height = label.sizeThatFits(CGSize(width: label.bounds.width, height: CGFloat.greatestFiniteMagnitude)).height
        label.layoutIfNeeded()
    }

    private func render(_ label: ZLAttributedLabel) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard   // 8 位 RGBA，按 4 字节读取像素
        return UIGraphicsImageRenderer(bounds: label.bounds, format: format).image { ctx in
            label.layer.render(in: ctx.cgContext)
        }
    }

    private func colorCount(_ image: UIImage, matching: (UInt8, UInt8, UInt8) -> Bool) -> Int {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return 0 }
        var count = 0
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let i = y * cg.bytesPerRow + x * 4
                // BGRA / RGBA 都按通道判断（只用于纯红 / 纯绿检测）
                let (c0, c1, c2) = (ptr[i], ptr[i + 1], ptr[i + 2])
                if cg.bitmapInfo.contains(.byteOrder32Little) ? matching(c2, c1, c0) : matching(c0, c1, c2) { count += 1 }
            }
        }
        return count
    }

    func testPlainTextUsesLabelAttributesAndFollowsChanges() {
        let label = makeLabel()
        label.textColor = .red
        label.text = "Hello"
        XCTAssertEqual(label.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .red)
        label.font = .boldSystemFont(ofSize: 20)
        XCTAssertEqual((label.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize, 20,
                       "纯文本在字体变化后重新生成")
        label.text = nil
        XCTAssertNil(label.attributedText)
        XCTAssertEqual(label.sizeThatFits(CGSize(width: 100, height: 100)), .zero)
    }

    func testAttributedTextFillsMissingFontAndDetectsLinks() {
        let label = makeLabel()
        label.enabledTextCheckingTypes = NSTextCheckingResult.CheckingType.link.rawValue
        let text = NSMutableAttributedString(string: "Visit https://example.com or tap here")
        text.addAttribute(.link, value: "https://apple.com", range: (text.string as NSString).range(of: "here"))
        label.attributedText = text
        XCTAssertNotNil(label.attributedText?.attribute(.font, at: 0, effectiveRange: nil), "未设置字体时补上 label.font")
        XCTAssertEqual(label.links.count, 2)
        XCTAssertEqual(Set(label.links.compactMap { $0.url?.host }), ["example.com", "apple.com"])
        let index = (label.attributedText!.string as NSString).range(of: "example").location
        XCTAssertEqual(label.attributedText?.attribute(.foregroundColor, at: index, effectiveRange: nil) as? UIColor,
                       label.linkAttributes[.foregroundColor] as? UIColor, "识别的链接使用 linkAttributes")

        label.attributedText = NSAttributedString(string: "no links")
        XCTAssertTrue(label.links.isEmpty, "重新设置文字清空链接")
    }

    func testTapHighlightsAndCallsBack() {
        final class Delegate: NSObject, ZLAttributedLabelDelegate {
            var urls: [URL] = []
            func attributedLabel(_ label: ZLAttributedLabel, didSelectLinkWith url: URL) { urls.append(url) }
        }
        let label = makeLabel()
        let delegate = Delegate()
        label.delegate = delegate
        label.text = "open link now"
        let range = NSRange(location: 5, length: 4)
        label.addLink(to: URL(string: "https://a.com")!, range: range)
        var tapped = 0
        label.addLink(range: NSRange(location: 10, length: 3)) { _, _ in tapped += 1 }
        fit(label)

        let before = label.attributedText
        let link = label.links[0]
        label.activeLink = link
        XCTAssertFalse(label.attributedText === before, "按下时显示按下样式")
        label.activeLink = nil
        XCTAssertTrue(label.attributedText === before, "松开后恢复")

        label.performTap(on: link)
        label.performTap(on: label.links[1])
        XCTAssertEqual(delegate.urls, [URL(string: "https://a.com")!])
        XCTAssertEqual(tapped, 1)

        let rect = label.boundingRect(forCharacterRange: range)
        XCTAssertFalse(rect.isEmpty)
        XCTAssertTrue(label.link(at: CGPoint(x: rect.midX, y: rect.midY)) === link)
        XCTAssertTrue(label.hitTest(CGPoint(x: rect.midX, y: rect.midY), with: nil) === label)
    }

    func testTruncationAndVerticalAlignment() {
        let label = makeLabel(width: 120)
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.text = String(repeating: "word ", count: 40)
        fit(label)
        let twoLines = label.bounds.height
        label.numberOfLines = 0
        XCTAssertGreaterThan(label.sizeThatFits(CGSize(width: 120, height: CGFloat.greatestFiniteMagnitude)).height, twoLines)

        let short = makeLabel()
        short.text = "Hi"
        short.frame.size.height = 100
        short.verticalAlignment = .top
        let top = short.textRect(forBounds: short.bounds, limitedToNumberOfLines: 0).minY
        short.verticalAlignment = .bottom
        let bottom = short.textRect(forBounds: short.bounds, limitedToNumberOfLines: 0).minY
        XCTAssertEqual(top, 0)
        XCTAssertGreaterThan(bottom, 50)
        short.textInsets = UIEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        let size = short.sizeThatFits(CGSize(width: 300, height: 100))
        short.textInsets = .zero
        XCTAssertEqual(size.width - short.sizeThatFits(CGSize(width: 300, height: 100)).width, 14)
    }

    func testDrawsBackgroundColorAndStrikethrough() {
        let label = makeLabel()
        label.backgroundColor = .white
        let text = NSMutableAttributedString(string: "background strike",
                                             attributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black])
        text.addAttribute(.backgroundColor, value: UIColor.green, range: NSRange(location: 0, length: 10))
        text.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: UIColor.red],
                           range: NSRange(location: 11, length: 6))
        label.attributedText = text
        fit(label)
        let image = render(label)
        XCTAssertGreaterThan(colorCount(image) { r, g, b in g > 200 && r < 60 && b < 60 }, 100, "绘制了背景色")
        XCTAssertGreaterThan(colorCount(image) { r, g, b in r > 200 && g < 60 && b < 60 }, 20, "绘制了删除线")
    }

    func testAccessibilityExposesLinks() {
        let label = makeLabel()
        label.text = "plain"
        fit(label)
        XCTAssertTrue(label.isAccessibilityElement, "没有链接时与 UILabel 相同")
        XCTAssertNil(label.accessibilityElements)

        label.text = "read terms please"
        var tapped = false
        label.addLink(range: NSRange(location: 5, length: 5)) { _, _ in tapped = true }
        fit(label)
        XCTAssertFalse(label.isAccessibilityElement)
        let elements = label.accessibilityElements as? [UIAccessibilityElement] ?? []
        XCTAssertEqual(elements.count, 2)
        XCTAssertEqual(elements.last?.accessibilityLabel, "terms")
        XCTAssertTrue(elements.last?.accessibilityTraits.contains(.link) ?? false)
        XCTAssertTrue(elements.last?.accessibilityActivate() ?? false)
        XCTAssertTrue(tapped)
    }
}

/// 内边距 textInsets：尺寸、绘制、点击定位、内嵌 View、展开按钮都要按内边距偏移
class TextInsetsTests: XCTestCase {

    private let insets = UIEdgeInsets(top: 12, left: 20, bottom: 8, right: 16)
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

    private func makeLabel(insets: UIEdgeInsets, numberOfLines: Int = 0, box: UIView? = nil) -> ZLRichLabel {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 240, height: 0))
        label.numberOfLines = numberOfLines
        label.verticalAlignment = .top
        label.update { v in
            v.textInsets = insets
            v.style = [.font: UIFont.systemFont(ofSize: 15)]
            v.expandToken = NSAttributedString(string: "… 全文")
            if let box = box {
                try? v.addRule(name: "box", pattern: "\\[box\\]") { ctx in
                    ctx.attributedString.setAttributedString(ctx.attachmentString(for: ZLRichWidget(view: box, size: CGSize(width: 20, height: 12))))
                }
            }
            try? v.addRule(name: "mention", pattern: "@\\w+") { ctx in ctx.onTap = { _ in } }
            v.text = "[box] @alice " + String(repeating: "some words here ", count: 12)
        }
        window.addSubview(label)
        label.frame.size.height = label.sizeThatFits(CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude)).height
        label.layoutIfNeeded()
        return label
    }

    func testSizeIncludesInsets() {
        let plain = makeLabel(insets: .zero)
        let padded = makeLabel(insets: insets)
        let plainSize = plain.sizeThatFits(CGSize(width: 240 - 36, height: CGFloat.greatestFiniteMagnitude))
        let paddedSize = padded.sizeThatFits(CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertEqual(paddedSize.height, plainSize.height + 20, "同样的文字宽度，高度只多出上下内边距")
        padded.preferredMaxLayoutWidth = 240
        XCTAssertEqual(padded.intrinsicContentSize.height, paddedSize.height)
    }

    func testContentIsOffsetByInsets() {
        let plainBox = UIView(), paddedBox = UIView()
        let plain = makeLabel(insets: .zero, box: plainBox)
        let padded = makeLabel(insets: UIEdgeInsets(top: 12, left: 20, bottom: 8, right: 20), box: paddedBox)
        // 同样的文字宽度（240 - 40 vs 200 无内边距时排版不同），这里只比较首字符：都在第一行行首
        XCTAssertEqual(paddedBox.frame.minX - plainBox.frame.minX, 20, accuracy: 0.5, "内嵌 View 向右偏移左内边距")
        XCTAssertEqual(paddedBox.frame.minY - plainBox.frame.minY, 12, accuracy: 0.5, "内嵌 View 向下偏移上内边距")

        // 内边距区域没有文字，也不会命中链接
        XCTAssertEqual(padded.characterIndex(at: CGPoint(x: 5, y: 20)), NSNotFound)
        XCTAssertEqual(padded.characterIndex(at: CGPoint(x: 30, y: 4)), NSNotFound)
        let mention = (padded.attributedText!.string as NSString).range(of: "@alice")
        let rect = padded.boundingRect(forCharacterRange: mention)
        XCTAssertGreaterThanOrEqual(rect.minX, 20)
        XCTAssertGreaterThanOrEqual(rect.minY, 12 - 1, "（行高框比字形略高，允许 1pt）")
        XCTAssertNotNil(padded.link(at: CGPoint(x: rect.midX, y: rect.midY)))
        XCTAssertNotNil(padded.match(at: CGPoint(x: rect.midX, y: rect.midY)))
        let all = padded.boundingRect(forCharacterRange: NSRange(location: 0, length: padded.attributedText!.length))
        XCTAssertLessThanOrEqual(all.maxX, 240 - 20 + 0.5, "文字不超过右内边距")
        XCTAssertLessThanOrEqual(all.maxY, padded.bounds.height - 8 + 0.5, "文字不超过下内边距")
    }

    func testExpandTokenRespectsInsets() {
        let label = makeLabel(insets: insets, numberOfLines: 2)
        XCTAssertTrue(label.isTruncated)
        let token = label.expandTokenRect.insetBy(dx: 8, dy: 6)   // 去掉点击区域的扩大量
        XCTAssertLessThanOrEqual(token.maxX, 240 - insets.right + 0.5, "「展开」不超过右内边距")
        XCTAssertLessThanOrEqual(token.maxY, label.bounds.height - insets.bottom + 0.5)
    }

    func testInsetsAreNotDrawnInto() {
        let label = makeLabel(insets: insets)
        label.backgroundColor = .white
        label.style = [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.black]
        label.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard   // 8 位 RGBA，按 4 字节读取像素
        let image = UIGraphicsImageRenderer(bounds: label.bounds, format: format).image { label.layer.render(in: $0.cgContext) }
        guard let cg = image.cgImage, let ptr = CFDataGetBytePtr(cg.dataProvider!.data) else { return XCTFail() }
        func dark(_ x: Int, _ y: Int) -> Bool {
            let i = y * cg.bytesPerRow + x * 4
            return Int(ptr[i]) + Int(ptr[i + 1]) + Int(ptr[i + 2]) < 600
        }
        var inInsets = 0, inContent = 0
        for y in 0..<cg.height {
            for x in 0..<cg.width where dark(x, y) {
                let inside = CGFloat(x) >= insets.left - 1 && CGFloat(x) < 240 - insets.right + 1
                    && CGFloat(y) >= insets.top - 1 && CGFloat(y) < label.bounds.height - insets.bottom + 1
                if inside { inContent += 1 } else { inInsets += 1 }
            }
        }
        XCTAssertGreaterThan(inContent, 200)
        XCTAssertEqual(inInsets, 0, "内边距区域不绘制文字")
    }

    func testChangingInsetsRelayouts() {
        let box = UIView()
        let label = makeLabel(insets: .zero, box: box)
        let before = box.frame.minX
        label.textInsets = UIEdgeInsets(top: 0, left: 30, bottom: 0, right: 0)
        label.layoutIfNeeded()
        XCTAssertEqual(box.frame.minX - before, 30, accuracy: 0.5, "修改内边距后内嵌 View 跟随移动")
    }
}



/// 字号自适应：adjustsFontSizeToFitWidth + minimumScaleFactor
class AdjustsFontSizeTests: XCTestCase {

    private let longText = "The quick brown fox jumps over the lazy dog END"

    private func makeLabel(width: CGFloat, height: CGFloat = 30, lines: Int = 1, text: String? = nil) -> ZLAttributedLabel {
        let label = ZLAttributedLabel(frame: CGRect(x: 0, y: 0, width: width, height: height))
        label.numberOfLines = lines
        label.font = .systemFont(ofSize: 20)
        label.text = text ?? longText
        label.layoutIfNeeded()
        return label
    }

    /// 末尾 "END" 中 "N" 的矩形（被截断或超出行数时为 .zero）；不取最后一个字：单行截断时截断符映射到最后一个字上
    private func lastCharacterRect(_ label: ZLAttributedLabel) -> CGRect {
        let length = label.attributedText?.length ?? 0
        return label.boundingRect(forCharacterRange: NSRange(location: length - 2, length: 1))
    }

    func testDisabledByDefaultAndWithoutMinimum() {
        let label = makeLabel(width: 120)
        XCTAssertFalse(label.adjustsFontSizeToFitWidth)
        XCTAssertEqual(label.currentFontScaleFactor, 1)
        XCTAssertEqual(lastCharacterRect(label), .zero, "不缩小时单行被截断，最后一个字不可见")

        label.adjustsFontSizeToFitWidth = true   // minimumScaleFactor 为 0：与 UILabel 相同，不缩小
        XCTAssertEqual(label.currentFontScaleFactor, 1)
    }

    func testSingleLineShrinksToFitWidth() {
        let label = makeLabel(width: 300)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.3
        let scale = label.currentFontScaleFactor
        XCTAssertLessThan(scale, 1)
        XCTAssertGreaterThanOrEqual(scale, 0.3)
        let rect = lastCharacterRect(label)
        XCTAssertNotEqual(rect, .zero, "缩小后整行放下，最后一个字可见")
        XCTAssertLessThanOrEqual(rect.maxX, 300.5)
        // 取能放下的最大比例：再放大 5% 就放不下
        XCTAssertGreaterThan(scale, 0.3)
        let wider = makeLabel(width: 300 * 1.06)
        wider.adjustsFontSizeToFitWidth = true
        wider.minimumScaleFactor = 0.3
        XCTAssertGreaterThan(wider.currentFontScaleFactor, scale)
    }

    func testShortTextKeepsOriginalSize() {
        let label = makeLabel(width: 300, text: "Short")
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        XCTAssertEqual(label.currentFontScaleFactor, 1)
    }

    func testMinimumScaleFactorIsLowerBoundAndTruncatesBeyond() {
        let label = makeLabel(width: 80)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        XCTAssertEqual(label.currentFontScaleFactor, 0.5, accuracy: 0.001, "放不下时停在最小比例")
        XCTAssertEqual(lastCharacterRect(label), .zero, "最小比例仍放不下时照常截断")
    }

    func testMultilineShrinksToLineLimit() {
        let label = makeLabel(width: 150, height: 200, lines: 2)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.3
        XCTAssertLessThan(label.currentFontScaleFactor, 1)
        XCTAssertNotEqual(lastCharacterRect(label), .zero, "缩小后两行内显示全部文字")
    }

    func testUnlimitedLinesShrinkToHeight() {
        let label = makeLabel(width: 150, height: 40, lines: 0)
        label.verticalAlignment = .top
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.2
        XCTAssertLessThan(label.currentFontScaleFactor, 1)
        let rect = lastCharacterRect(label)
        XCTAssertNotEqual(rect, .zero)
        XCTAssertLessThanOrEqual(rect.maxY, 40.5, "缩小后文字在 label 高度内")
    }

    func testSizeThatFitsUsesOriginalFont() {
        let plain = makeLabel(width: 300)
        let adjusted = makeLabel(width: 300)
        adjusted.adjustsFontSizeToFitWidth = true
        adjusted.minimumScaleFactor = 0.3
        let unlimited = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        XCTAssertEqual(adjusted.sizeThatFits(unlimited), plain.sizeThatFits(unlimited), "与 UILabel 相同：尺寸按原字号计算")
    }

    func testLinksAndCharacterIndexFollowScaledLayout() {
        let label = makeLabel(width: 300)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.3
        let range = (longText as NSString).range(of: "END")
        var tapped = false
        label.addLink(range: range) { _, _ in tapped = true }
        let rect = label.boundingRect(forCharacterRange: range)
        XCTAssertNotEqual(rect, .zero)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        XCTAssertTrue(NSLocationInRange(label.characterIndex(at: center), range))
        guard let link = label.link(at: center) else { return XCTFail("缩小后按位置找到链接") }
        label.performTap(on: link)
        XCTAssertTrue(tapped)
    }

    func testTextAndSizeChangesRecompute() {
        let label = makeLabel(width: 300)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.3
        XCTAssertLessThan(label.currentFontScaleFactor, 1)
        label.text = "Short"
        XCTAssertEqual(label.currentFontScaleFactor, 1, "文字变化后重新计算")
        label.text = longText
        let narrow = label.currentFontScaleFactor
        label.frame.size.width = 600
        XCTAssertGreaterThan(label.currentFontScaleFactor, narrow, "宽度变化后重新计算")
    }

    func testDrawsWithinBounds() {
        let label = makeLabel(width: 200)
        label.backgroundColor = .white
        label.textColor = .black
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.3
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: label.bounds, format: format).image { label.layer.render(in: $0.cgContext) }
        guard let cg = image.cgImage, let ptr = CFDataGetBytePtr(cg.dataProvider!.data) else { return XCTFail() }
        var maxDarkX = -1
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let i = y * cg.bytesPerRow + x * 4
                if Int(ptr[i]) + Int(ptr[i + 1]) + Int(ptr[i + 2]) < 300 { maxDarkX = max(maxDarkX, x) }
            }
        }
        XCTAssertGreaterThan(maxDarkX, 150, "整行文字绘制到接近右边")
        XCTAssertLessThan(maxDarkX, 200)
    }

    func testRichLabelRulesWorkWhenScaled() {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 220, height: 30))
        label.numberOfLines = 1
        var tapped: String?
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 20)]
            try? v.addRule(name: "mention", pattern: "@\\w+") { ctx in
                ctx.addAttributes([.foregroundColor: UIColor.systemBlue])
                ctx.onTap = { match in tapped = match.text }
            }
            v.text = "Hello everyone, please welcome @alice"
        }
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.3
        label.layoutIfNeeded()
        XCTAssertLessThan(label.currentFontScaleFactor, 1)
        let display = (label.attributedText?.string ?? "") as NSString
        let rect = label.boundingRect(forCharacterRange: display.range(of: "@alice"))
        XCTAssertNotEqual(rect, .zero, "缩小后 @alice 可见")
        guard let link = label.link(at: CGPoint(x: rect.midX, y: rect.midY)) else { return XCTFail() }
        label.performTap(on: link)
        XCTAssertEqual(tapped, "@alice")
    }
}

/// 「展开 / 收起」按钮的外部处理 onExpandTokenTap
class ExpandTokenTapTests: XCTestCase {

    /// 模拟一次结束的点击（位置固定）
    private final class FakeTap: UITapGestureRecognizer {
        var point: CGPoint = .zero
        override var state: UIGestureRecognizer.State {
            get { return .ended }
            set {}
        }
        override func location(in view: UIView?) -> CGPoint { return point }
    }

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

    private func makeLabel() -> ZLRichLabel {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 220, height: 0))
        label.numberOfLines = 2
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 15)]
            v.expandToken = NSAttributedString(string: "… 全文")
            v.collapseToken = NSAttributedString(string: " 收起")
            v.text = String(repeating: "Swift is a powerful and intuitive programming language. ", count: 6)
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

    /// 走真实的「展开」点击处理
    private func tapExpand(_ label: ZLRichLabel) {
        XCTAssertFalse(label.expandTokenRect.isEmpty, "应显示「展开」按钮")
        let tap = FakeTap()
        tap.point = CGPoint(x: label.expandTokenRect.midX, y: label.expandTokenRect.midY)
        label.perform(NSSelectorFromString("handleExpandTap:"), with: tap)
    }

    /// 点击「收起」链接（展开后拼接在末尾）
    private func tapCollapse(_ label: ZLRichLabel) {
        guard let link = label.links.max(by: { $0.range.location < $1.range.location }) else { return XCTFail("没有「收起」") }
        label.performTap(on: link)
    }

    func testDefaultTogglesAutomatically() {
        let label = makeLabel()
        var changes: [Bool] = []
        label.onExpandChanged = { changes.append($0) }
        tapExpand(label)
        XCTAssertTrue(label.isExpanded, "没有设置 onExpandTokenTap：内部自动展开")
        fit(label)
        tapCollapse(label)
        XCTAssertFalse(label.isExpanded, "内部自动收起")
        XCTAssertEqual(changes, [true, false])
    }

    func testExternalHandlerDecidesAndBlocksAutoToggle() {
        let label = makeLabel()
        var taps: [Bool] = []
        var changes: [Bool] = []
        label.onExpandChanged = { changes.append($0) }
        label.onExpandTokenTap = { tapped, wantsExpand in
            XCTAssertTrue(tapped === label)
            taps.append(wantsExpand)
        }
        tapExpand(label)
        XCTAssertEqual(taps, [true], "点击「展开」回调 wantsExpand = true")
        XCTAssertFalse(label.isExpanded, "设置了 onExpandTokenTap：不自动展开")
        XCTAssertEqual(changes, [], "也不回调 onExpandChanged")

        // 外部决定展开
        label.isExpanded = true
        fit(label)
        tapCollapse(label)
        XCTAssertEqual(taps, [true, false], "点击「收起」回调 wantsExpand = false")
        XCTAssertTrue(label.isExpanded, "不自动收起")
    }

    func testExternalHandlerCanUseDefaultToggle() {
        let label = makeLabel()
        var changes: [Bool] = []
        label.onExpandChanged = { changes.append($0) }
        var allow = false
        label.onExpandTokenTap = { tapped, _ in
            if allow { tapped.toggleExpanded() }
        }
        tapExpand(label)
        XCTAssertFalse(label.isExpanded, "外部拒绝")
        allow = true
        tapExpand(label)
        XCTAssertTrue(label.isExpanded, "外部调用 toggleExpanded() 按默认方式展开")
        XCTAssertEqual(changes, [true])

        // 去掉外部处理后恢复默认
        label.onExpandTokenTap = nil
        fit(label)
        tapCollapse(label)
        XCTAssertFalse(label.isExpanded)
        XCTAssertEqual(changes, [true, false])
    }
}

/// 从右到左（RTL）/ 双向混排下的胶囊内边距，以及段落缩进
class RTLDecorationTests: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.isHidden = false
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    /// 一个胶囊的测量结果（单位 pt）
    struct Capsule {
        let minX: CGFloat, maxX: CGFloat
        /// 胶囊内文字到背景左 / 右边缘的距离
        let innerLeft: CGFloat, innerRight: CGFloat
        /// 背景到相邻黑色文字的距离，没有相邻文字时为 nil
        let outerLeft: CGFloat?, outerRight: CGFloat?
    }

    private let padding: CGFloat = 6
    private let margin: CGFloat = 3

    /// 渲染：胶囊纯红填充、胶囊内文字蓝色、其它文字黑色；返回每条红色带中的胶囊（从左到右）
    private func capsules(_ text: String, pattern: String, width: CGFloat = 320) -> [[Capsule]] {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: width, height: 0))
        label.numberOfLines = 0
        label.backgroundColor = .white
        label.update { v in
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 10
            v.style = [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.black, .paragraphStyle: paragraph]
            try? v.addRule(name: "capsule", pattern: pattern) { [padding, margin] ctx in
                ctx.addAttributes([.foregroundColor: UIColor.blue,
                                   .zlBackground: ZLTextBackground(fillColor: .red, cornerRadius: 0,
                                                                   padding: UIEdgeInsets(top: 1, left: padding, bottom: 1, right: padding),
                                                                   margin: margin)])
            }
            v.text = text
        }
        window.addSubview(label)
        label.frame.size.height = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height + 8
        label.layoutIfNeeded()

        let scale: CGFloat = 2
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: label.bounds, format: format).image { label.layer.render(in: $0.cgContext) }
        guard let cg = image.cgImage, let ptr = CFDataGetBytePtr(cg.dataProvider!.data) else { return [] }
        let little = cg.bitmapInfo.contains(.byteOrder32Little)
        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = y * cg.bytesPerRow + x * 4
            let (a, b, c) = (Int(ptr[i]), Int(ptr[i + 1]), Int(ptr[i + 2]))
            return little ? (c, b, a) : (a, b, c)
        }
        func isRed(_ x: Int, _ y: Int) -> Bool { let p = rgb(x, y); return p.0 > 200 && p.1 < 60 && p.2 < 60 }
        func isBlue(_ x: Int, _ y: Int) -> Bool { let p = rgb(x, y); return p.2 > 110 && p.2 > p.0 + 30 && p.1 < 140 }
        func isBlack(_ x: Int, _ y: Int) -> Bool {
            let p = rgb(x, y); return p.0 < 140 && p.1 < 140 && p.2 < 140 && !isBlue(x, y) && !(p.0 > p.1 + 60)
        }
        func rowHasRed(_ y: Int) -> Bool { (0..<cg.width).contains { isRed($0, y) } }

        var bands: [[Capsule]] = []
        var y = 0
        while y < cg.height {
            guard rowHasRed(y) else { y += 1; continue }
            let top = y
            while y < cg.height, rowHasRed(y) { y += 1 }
            let bottom = y - 1
            let mid = (top...bottom).max { a, b in
                (0..<cg.width).filter { isRed($0, a) }.count < (0..<cg.width).filter { isRed($0, b) }.count
            }!
            var result: [Capsule] = []
            var x = 0
            while x < cg.width {
                guard isRed(x, mid) else { x += 1; continue }
                let start = x
                var lastRed = x
                while x < cg.width, isRed(x, mid) || isBlue(x, mid) || (rgb(x, mid).0 > 120 && rgb(x, mid).1 < 120) {
                    if isRed(x, mid) { lastRed = x }
                    x += 1
                }
                var blueMin = Int.max, blueMax = Int.min
                var blackLeft = Int.min, blackRight = Int.max
                for yy in top...bottom {
                    for xx in start...lastRed where isBlue(xx, yy) { blueMin = min(blueMin, xx); blueMax = max(blueMax, xx) }
                    for xx in stride(from: start - 1, through: max(0, start - 60), by: -1) where isBlack(xx, yy) {
                        blackLeft = max(blackLeft, xx); break
                    }
                    for xx in (lastRed + 1)..<min(cg.width, lastRed + 60) where isBlack(xx, yy) {
                        blackRight = min(blackRight, xx); break
                    }
                }
                guard blueMin != Int.max else { continue }
                result.append(Capsule(minX: CGFloat(start) / scale, maxX: CGFloat(lastRed + 1) / scale,
                                      innerLeft: CGFloat(blueMin - start) / scale,
                                      innerRight: CGFloat(lastRed - blueMax) / scale,
                                      outerLeft: blackLeft == Int.min ? nil : CGFloat(start - blackLeft - 1) / scale,
                                      outerRight: blackRight == Int.max ? nil : CGFloat(blackRight - lastRed - 1) / scale))
            }
            bands.append(result)
        }
        return bands
    }

    /// 两侧内边距都接近设置值（字形本身的左右留白有 1 ~ 2pt 误差）
    private func assertPadding(_ capsule: Capsule?, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let c = capsule else { return XCTFail("没有画出胶囊：\(message)", file: file, line: line) }
        XCTAssertGreaterThanOrEqual(c.innerLeft, padding - 1.5, "左侧内边距：\(message) \(c)", file: file, line: line)
        XCTAssertLessThanOrEqual(c.innerLeft, padding + 2.5, "左侧内边距：\(message) \(c)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(c.innerRight, padding - 1.5, "右侧内边距：\(message) \(c)", file: file, line: line)
        XCTAssertLessThanOrEqual(c.innerRight, padding + 2.5, "右侧内边距：\(message) \(c)", file: file, line: line)
    }

    /// 外侧与相邻文字的距离：有相邻文字的一侧不能贴住（>= margin），两侧大致对称
    private func assertOuterGaps(_ capsule: Capsule?, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let c = capsule else { return XCTFail("没有画出胶囊：\(message)", file: file, line: line) }
        for gap in [c.outerLeft, c.outerRight].compactMap({ $0 }) {
            XCTAssertGreaterThanOrEqual(gap, margin, "外侧贴住了相邻文字：\(message) \(c)", file: file, line: line)
            XCTAssertLessThanOrEqual(gap, margin + 8, "外侧空隙过大（间距挤到了一侧）：\(message) \(c)", file: file, line: line)
        }
    }

    func testLeftToRightBaseline() {
        let mid = capsules("Hello world #Swift# and more words here.", pattern: "#[^#]+#").first?.first
        assertPadding(mid, "LTR 句中")
        assertOuterGaps(mid, "LTR 句中")
        let start = capsules("#Swift# starts the paragraph", pattern: "#[^#]+#").first?.first
        assertPadding(start, "LTR 段落开头")
        XCTAssertGreaterThanOrEqual(start?.minX ?? -1, 0, "段落开头的胶囊不被裁掉")
    }

    func testRightToLeftPadding() {
        let arabic = "مرحبا بالعالم سويفت لغة برمجة قوية"
        for (name, text) in [("阿拉伯语句中", arabic),
                             ("阿拉伯语句首", "سويفت لغة برمجة قوية"),
                             ("阿拉伯语句尾", "لغة برمجة قوية سويفت")] {
            let capsule = capsules(text, pattern: "سويفت").first?.first
            assertPadding(capsule, name)
            assertOuterGaps(capsule, name)
        }
        let hebrew = capsules("שלום עולם סוויפט היא שפה", pattern: "סוויפט").first?.first
        assertPadding(hebrew, "希伯来语")
        assertOuterGaps(hebrew, "希伯来语")
        let hashtag = capsules("مرحبا #سويفت# برمجة", pattern: "#[^#]+#").first?.first
        assertPadding(hashtag, "阿拉伯语 #话题#")
        let start = capsules("سويفت لغة برمجة قوية", pattern: "سويفت").first?.first
        XCTAssertLessThanOrEqual(start?.maxX ?? .greatestFiniteMagnitude, 320, "RTL 段落开头（最右）的胶囊不被裁掉")
    }

    func testAdjacentRightToLeftCapsulesDoNotOverlap() {
        guard let band = capsules("مرحبا سويفتلغة برمجة", pattern: "سويفت|لغة").first else { return XCTFail() }
        XCTAssertEqual(band.count, 2, "紧挨着的两个胶囊分开画")
        guard band.count == 2 else { return }
        band.forEach { assertPadding($0, "紧挨着的 RTL 胶囊") }
        XCTAssertGreaterThanOrEqual(band[1].minX - band[0].maxX, margin, "两个胶囊之间留有间距，不重叠")
    }

    func testBidirectionalMixedCapsules() {
        let ltrInRtl = capsules("مرحبا بالعالم Swift لغة برمجة", pattern: "Swift").first?.first
        assertPadding(ltrInRtl, "阿拉伯段落中的英文胶囊")
        assertOuterGaps(ltrInRtl, "阿拉伯段落中的英文胶囊")
        let rtlInLtr = capsules("Hello world سويفت is great", pattern: "سويفت").first?.first
        assertPadding(rtlInLtr, "英文段落中的阿拉伯胶囊")
        assertOuterGaps(rtlInLtr, "英文段落中的阿拉伯胶囊")
        let digits = capsules("السعر 123 دولار فقط", pattern: "123").first?.first
        assertPadding(digits, "阿拉伯段落中的数字")
        assertOuterGaps(digits, "阿拉伯段落中的数字")
    }

    func testWrappedRightToLeftCapsuleDrawsOnEachLine() {
        let bands = capsules("مرحبا بالعالم هذا نص طويل جدا يحتوي على كبسولة طويلة سويفت لغة برمجة قوية وسهلة ثم يكمل النص",
                             pattern: "سويفت لغة برمجة قوية وسهلة", width: 200)
        XCTAssertEqual(bands.count, 2, "跨行时每行一段")
        // 胶囊起点（逻辑开头）在第一段的右侧：右内边距正常
        XCTAssertGreaterThanOrEqual(bands.first?.first?.innerRight ?? 0, padding - 1.5)
        // 胶囊结尾在第二段的左侧：左内边距正常
        XCTAssertGreaterThanOrEqual(bands.last?.first?.innerLeft ?? 0, padding - 1.5)
    }

    // MARK: 段落缩进

    private func indentLabel(_ text: String, style: NSParagraphStyle) -> ZLAttributedLabel {
        let label = ZLAttributedLabel(frame: CGRect(x: 0, y: 0, width: 240, height: 200))
        label.numberOfLines = 0
        label.verticalAlignment = .top
        label.attributedText = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 17),
                                                                             .paragraphStyle: style])
        label.layoutIfNeeded()
        return label
    }

    func testParagraphIndentsAreApplied() {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 30
        style.headIndent = 10
        let text = "Hello world this is a long paragraph that wraps onto more lines here."
        let label = indentLabel(text, style: style)
        let first = label.boundingRect(forCharacterRange: NSRange(location: 0, length: 1))
        XCTAssertEqual(first.minX, 30, accuracy: 1.5, "首行缩进")
        let firstLineEnd = (text as NSString).range(of: "long").location
        let secondLine = label.lineRects(forTesting: NSRange(location: firstLineEnd, length: text.count - firstLineEnd))
        XCTAssertNotNil(secondLine)
        // 字符定位与绘制一致：首行缩进区域内不是文字
        XCTAssertEqual(label.characterIndex(at: CGPoint(x: 15, y: first.midY)), NSNotFound)
        XCTAssertEqual(label.characterIndex(at: CGPoint(x: first.midX, y: first.midY)), 0)
    }

    func testRightToLeftParagraphIndentIsOnTheRight() {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 30
        style.baseWritingDirection = .rightToLeft
        style.alignment = .right
        let label = indentLabel("مرحبا بالعالم", style: style)
        label.textAlignment = .right
        label.layoutIfNeeded()
        let rect = label.boundingRect(forCharacterRange: NSRange(location: 0, length: 13))
        XCTAssertEqual(rect.maxX, 240 - 30, accuracy: 1.5, "RTL 段落的首行缩进在右侧")
    }
}

private extension ZLAttributedLabel {
    /// 测试用：一段文字是否可见
    func lineRects(forTesting range: NSRange) -> CGRect? {
        let rect = boundingRect(forCharacterRange: range)
        return rect == .zero ? nil : rect
    }
}

// MARK: - ZLAttributedLabel 绘制 NSTextAttachment

class AttributedLabelTextAttachmentTests: XCTestCase {

    private func solidImage(_ color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func attachmentString(_ image: UIImage, bounds: CGRect = .zero) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = bounds
        return NSAttributedString(attachment: attachment)
    }

    private func makeLabel(_ text: NSAttributedString, width: CGFloat = 300, lines: Int = 0) -> ZLAttributedLabel {
        let label = ZLAttributedLabel(frame: CGRect(x: 0, y: 0, width: width, height: 0))
        label.numberOfLines = lines
        label.font = .systemFont(ofSize: 15)
        label.attributedText = text
        label.frame.size.height = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        label.layoutIfNeeded()
        return label
    }

    private func render(_ label: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard   // 8 位 RGBA，按 4 字节读取像素
        return UIGraphicsImageRenderer(bounds: label.bounds, format: format).image { ctx in
            label.layer.render(in: ctx.cgContext)
        }
    }

    /// 符合条件的像素数，以及它们的外接矩形
    private func pixels(_ image: UIImage, matching: (UInt8, UInt8, UInt8) -> Bool) -> (count: Int, rect: CGRect) {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return (0, .null) }
        var count = 0
        var rect = CGRect.null
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let i = y * cg.bytesPerRow + x * 4
                let (c0, c1, c2) = (ptr[i], ptr[i + 1], ptr[i + 2])
                let hit = cg.bitmapInfo.contains(.byteOrder32Little) ? matching(c2, c1, c0) : matching(c0, c1, c2)
                if hit {
                    count += 1
                    rect = rect.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return (count, rect)
    }

    private let isGreen: (UInt8, UInt8, UInt8) -> Bool = { r, g, b in g > 200 && r < 60 && b < 60 }
    private let isRed: (UInt8, UInt8, UInt8) -> Bool = { r, g, b in r > 200 && g < 60 && b < 60 }

    func testImageAttachmentReservesSpaceAndIsDrawnAtItsPosition() {
        let text = NSMutableAttributedString(string: "AB")
        let plainWidth = makeLabel(text).sizeThatFits(CGSize(width: 300, height: 1000)).width
        text.insert(attachmentString(solidImage(.green, size: CGSize(width: 20, height: 20)),
                                     bounds: CGRect(x: 0, y: -4, width: 20, height: 20)), at: 1)
        let label = makeLabel(text)

        // 占位：宽度增加 20
        let width = label.sizeThatFits(CGSize(width: 300, height: 1000)).width
        XCTAssertEqual(width - plainWidth, 20, accuracy: 1, "附件按 bounds 宽度占位")

        // 绘制：整张图片画出来，位置与附件字符的矩形一致
        let green = pixels(render(label), matching: isGreen)
        XCTAssertGreaterThan(green.count, 300, "图片被绘制（20×20）")
        let charRect = label.boundingRect(forCharacterRange: NSRange(location: 1, length: 1))
        XCTAssertEqual(green.rect.minX, charRect.minX, accuracy: 1.5, "图片在附件字符的位置")
        XCTAssertEqual(green.rect.width, 20, accuracy: 1.5)
        XCTAssertEqual(green.rect.height, 20, accuracy: 1.5)

        // 基线偏移：bounds.y = -4，图片底部在 "A" 的基线下方 4pt
        let aRect = label.boundingRect(forCharacterRange: NSRange(location: 0, length: 1))
        let baselineY = aRect.maxY + UIFont.systemFont(ofSize: 15).descender   // 行底 + descender（负数）= 基线
        XCTAssertEqual(green.rect.maxY, baselineY + 4, accuracy: 2, "图片按 bounds.y 相对基线偏移")
    }

    func testZeroBoundsUsesImageSize() {
        let text = NSMutableAttributedString(string: "A")
        text.append(attachmentString(solidImage(.green, size: CGSize(width: 30, height: 12))))
        let label = makeLabel(text)
        let green = pixels(render(label), matching: isGreen)
        XCTAssertEqual(green.rect.width, 30, accuracy: 1.5, "bounds 为空时使用图片尺寸")
        XCTAssertEqual(green.rect.height, 12, accuracy: 1.5)
    }

    func testTallAttachmentIncreasesLineHeight() {
        let plain = makeLabel(NSAttributedString(string: "A")).bounds.height
        let text = NSMutableAttributedString(string: "A")
        text.append(attachmentString(solidImage(.green, size: CGSize(width: 10, height: 60))))
        let label = makeLabel(text)
        XCTAssertGreaterThan(label.bounds.height, plain + 30, "高附件撑高行高")
        XCTAssertEqual(pixels(render(label), matching: isGreen).rect.height, 60, accuracy: 1.5, "高附件完整绘制，不被裁掉")
    }

    func testTemplateImageIsTintedWithTextColor() {
        let template = solidImage(.black, size: CGSize(width: 20, height: 20)).withRenderingMode(.alwaysTemplate)
        let text = NSMutableAttributedString(attributedString: attachmentString(template))
        text.addAttribute(.foregroundColor, value: UIColor.red, range: NSRange(location: 0, length: text.length))
        let label = makeLabel(text)
        XCTAssertGreaterThan(pixels(render(label), matching: isRed).count, 300, "模板图片按文字颜色着色")
    }

    func testAttachmentInTruncationToken() {
        let token = NSMutableAttributedString(string: "…")
        token.append(attachmentString(solidImage(.green, size: CGSize(width: 14, height: 14))))
        let label = ZLAttributedLabel(frame: CGRect(x: 0, y: 0, width: 120, height: 30))
        label.numberOfLines = 1
        label.font = .systemFont(ofSize: 15)
        label.attributedTruncationToken = token
        // 注意：用 `text` 设置纯文本时自定义截断符不生效（原有问题，与附件无关），这里用 attributedText
        label.attributedText = NSAttributedString(string: "A long long long long long long text")
        label.layoutIfNeeded()
        XCTAssertGreaterThan(pixels(render(label), matching: isGreen).count, 150, "截断符中的图片被绘制")
    }

    func testAttachmentWorksWithLinkHighlightAndCharacterIndex() {
        let text = NSMutableAttributedString(string: "go ")
        text.append(attachmentString(solidImage(.green, size: CGSize(width: 20, height: 20))))
        text.append(NSAttributedString(string: " end"))
        let label = makeLabel(text)
        var tapped = false
        label.addLink(range: NSRange(location: 3, length: 1)) { _, _ in tapped = true }
        let rect = label.boundingRect(forCharacterRange: NSRange(location: 3, length: 1))
        XCTAssertEqual(label.characterIndex(at: CGPoint(x: rect.midX, y: rect.midY)), 3, "点在图片上定位到附件字符")
        if let link = label.link(at: CGPoint(x: rect.midX, y: rect.midY)) { label.performTap(on: link) }
        XCTAssertTrue(tapped, "附件可作为链接点击")
    }

    func testRichLabelPassThroughAttributedTextDrawsAttachment() {
        let text = NSMutableAttributedString(string: "A")
        text.append(attachmentString(solidImage(.green, size: CGSize(width: 20, height: 20))))
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 0))
        label.numberOfLines = 0
        label.attributedText = text
        label.frame.size.height = label.sizeThatFits(CGSize(width: 300, height: 1000)).height
        label.layoutIfNeeded()
        XCTAssertTrue(label.subviews.filter { $0 is UIImageView }.isEmpty, "直接设置的富文本由基类绘制，不创建 View")
        XCTAssertGreaterThan(pixels(render(label), matching: isGreen).count, 300)
    }

    func testRichLabelRuleAttachmentsStillUseViews() {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 0))
        label.numberOfLines = 0
        let image = solidImage(.green, size: CGSize(width: 20, height: 20))
        try? label.addRule(name: "img", pattern: "\\[img\\]") { ctx in
            let attachment = NSTextAttachment()
            attachment.image = image
            ctx.attributedString.setAttributedString(NSAttributedString(attachment: attachment))
        }
        label.text = "a [img] b"
        label.frame.size.height = label.sizeThatFits(CGSize(width: 300, height: 1000)).height
        label.layoutIfNeeded()
        XCTAssertEqual(label.subviews.filter { $0 is UIImageView }.count, 1, "规则中的附件仍转换为 View（不重复绘制）")
        // View 是隐藏后在 layoutSubviews 中显示的；只检查基类没有再额外画一份
        let attr = label.attributedText!
        var hasTextAttachment = false
        attr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attr.length), options: []) { v, _, _ in
            if v != nil { hasTextAttachment = true }
        }
        XCTAssertFalse(hasTextAttachment)
    }
}

// MARK: - 单行纯文本的自定义截断符 / 段落样式中的截断模式

class TruncationTokenTests: XCTestCase {

    private let long = "Hello world, this is a fairly long sentence that cannot fit in one line"

    private func render(_ label: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard   // 8 位 RGBA，按 4 字节读取像素
        return UIGraphicsImageRenderer(bounds: label.bounds, format: format).image { ctx in
            label.layer.render(in: ctx.cgContext)
        }
    }

    /// 符合条件的像素的外接矩形（没有时为 .null）
    private func inkRect(_ image: UIImage, matching: (UInt8, UInt8, UInt8, UInt8) -> Bool) -> CGRect {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return .null }
        var rect = CGRect.null
        let little = cg.bitmapInfo.contains(.byteOrder32Little)
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let i = y * cg.bytesPerRow + x * 4
                let (r, g, b, a) = little ? (ptr[i + 2], ptr[i + 1], ptr[i], ptr[i + 3]) : (ptr[i], ptr[i + 1], ptr[i + 2], ptr[i + 3])
                if matching(r, g, b, a) { rect = rect.union(CGRect(x: x, y: y, width: 1, height: 1)) }
            }
        }
        return rect
    }

    private let isRed: (UInt8, UInt8, UInt8, UInt8) -> Bool = { r, g, b, a in a > 128 && r > 180 && g < 90 && b < 90 }
    private let isBlack: (UInt8, UInt8, UInt8, UInt8) -> Bool = { r, g, b, a in a > 128 && r < 80 && g < 80 && b < 80 }

    private func redToken() -> NSAttributedString {
        return NSAttributedString(string: "…MORE", attributes: [.foregroundColor: UIColor.red,
                                                                .font: UIFont.boldSystemFont(ofSize: 15)])
    }

    private func singleLineLabel(_ mode: NSLineBreakMode, token: NSAttributedString?, text: String) -> ZLAttributedLabel {
        let label = ZLAttributedLabel(frame: CGRect(x: 0, y: 0, width: 240, height: 30))
        label.numberOfLines = 1
        label.font = .systemFont(ofSize: 15)
        label.textColor = .black
        label.lineBreakMode = mode
        label.attributedTruncationToken = token
        label.text = text
        label.layoutIfNeeded()
        return label
    }

    func testPlainTextSingleLineUsesCustomTokenForEveryMode() {
        let tail = inkRect(render(singleLineLabel(.byTruncatingTail, token: redToken(), text: long)), matching: isRed)
        XCTAssertFalse(tail.isNull, "尾部截断：纯文本也显示自定义截断符")
        XCTAssertGreaterThan(tail.minX, 120, "尾部截断：截断符在右侧")

        let head = inkRect(render(singleLineLabel(.byTruncatingHead, token: redToken(), text: long)), matching: isRed)
        XCTAssertFalse(head.isNull, "头部截断：显示自定义截断符")
        XCTAssertLessThan(head.maxX, 120, "头部截断：截断符在左侧")

        let middle = inkRect(render(singleLineLabel(.byTruncatingMiddle, token: redToken(), text: long)), matching: isRed)
        XCTAssertFalse(middle.isNull, "中间截断：显示自定义截断符")
        XCTAssertTrue(middle.minX > 30 && middle.maxX < 210, "中间截断：截断符在中间，实际 \(middle)")
    }

    func testSingleLineTruncatesAtCharacterLevel() {
        // 第二个词很长：按词换行时第一行只有 "AAAA "，截断应在字符级别，尽量填满宽度
        let text = "AAAA BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
        let plain = singleLineLabel(.byTruncatingTail, token: redToken(), text: text)
        let black = inkRect(render(plain), matching: isBlack)
        let red = inkRect(render(plain), matching: isRed)
        XCTAssertGreaterThan(black.maxX, 100, "长单词被截断到字符，而不是只显示第一个词")
        XCTAssertFalse(red.isNull)
        XCTAssertLessThanOrEqual(red.maxX, 240, "截断后不超出宽度")

        // 富文本同样适用
        let label = ZLAttributedLabel(frame: CGRect(x: 0, y: 0, width: 240, height: 30))
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingHead
        label.attributedTruncationToken = redToken()
        label.attributedText = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 15),
                                                                              .foregroundColor: UIColor.black])
        label.layoutIfNeeded()
        let headBlack = inkRect(render(label), matching: isBlack)
        let headRed = inkRect(render(label), matching: isRed)
        XCTAssertLessThan(headRed.maxX, headBlack.minX + 2, "头部截断：截断符在左、文字在右")
        XCTAssertGreaterThan(headBlack.maxX, 200, "头部截断显示文字结尾")
    }

    func testDefaultEllipsisStillWorksForPlainSingleLine() {
        let label = singleLineLabel(.byTruncatingTail, token: nil, text: long)
        XCTAssertGreaterThan(inkRect(render(label), matching: isBlack).maxX, 200, "默认 … 截断时文字填满宽度")
    }

    func testSingleLineWithMoreParagraphsShowsToken() {
        let label = singleLineLabel(.byTruncatingTail, token: redToken(), text: "Short\nSecond paragraph")
        XCTAssertFalse(inkRect(render(label), matching: isRed).isNull, "第一段放得下但后面还有段落：显示截断符")
    }

    func testTruncatingParagraphStyleInAttributedTextStillWraps() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let label = ZLAttributedLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 0))
        label.numberOfLines = 0
        let font = UIFont.systemFont(ofSize: 15)
        label.attributedText = NSAttributedString(string: long + " " + long,
                                                  attributes: [.font: font, .paragraphStyle: paragraph])
        let height = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(height, font.lineHeight * 3, "段落样式里的截断模式不能让多行文字变成一行")

        // 限制 2 行时最后一行显示自定义截断符
        label.numberOfLines = 2
        label.attributedTruncationToken = redToken()
        label.frame.size.height = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height
        label.layoutIfNeeded()
        let red = inkRect(render(label), matching: isRed)
        XCTAssertFalse(red.isNull)
        XCTAssertGreaterThan(red.minY, label.bounds.height / 2, "截断符在第二行")
    }

    func testRichLabelSingleLineHeadTruncation() {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 240, height: 30))
        label.numberOfLines = 1
        label.textColor = .black
        label.font = .systemFont(ofSize: 15)
        label.lineBreakMode = .byTruncatingHead
        label.truncationToken = redToken()
        label.text = long
        label.layoutIfNeeded()
        let red = inkRect(render(label), matching: isRed)
        let black = inkRect(render(label), matching: isBlack)
        XCTAssertFalse(red.isNull, "ZLRichLabel 单行头部截断显示截断符")
        XCTAssertLessThan(red.maxX, black.minX + 2, "截断符在文字左侧")
    }
}
