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
