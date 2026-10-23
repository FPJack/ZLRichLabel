//
//  HTagDemoPage.swift
//  GMTagRichView_Example
//
//  Created by admin on 2026/10/22.
//  Copyright © 2026 CocoaPods. All rights reserved.
//
//  ZLRichLabel 演示页面（对应 Flutter 版 h_tag_demo_page.dart）
//

import UIKit
import ZLRichLabel

// MARK: - 数据

private struct TapRecord {
    let caseName: String
    let info: HTagInfo
    /// 触发的点击动作（tagTapHandlers 按标签名分发的结果）
    let action: String
    let time = Date()
}

// MARK: - 页面

final class HTagDemoPage: UIViewController {

    /// 最近一次点击
    private var last: TapRecord?
    /// 点击历史
    private var history: [TapRecord] = []
    /// 用例 11 的勾选状态
    private var agreed11 = false

    private let tapInfoPanel = TapInfoPanel()
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let historyCard = HistoryCard()
    /// 每个用例的卡片（用于显示 onParsed 结果）
    private var cards: [String: DemoCard] = [:]
    private weak var case11Label: ZLTagRichLabel?
    /// 用例 16 的勾选状态
    private var agreed16 = false
    private weak var case16Label: ZLTagRichLabel?

    private static let baseStyle: HTagTextStyle = [
        .font: UIFont.systemFont(ofSize: 15),
        .foregroundColor: UIColor(white: 0, alpha: 0.87),
    ]

    // MARK: Life cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "HTagRichText Demo"
        view.backgroundColor = UIColor(hex: 0xFEF7FF)
        setupNavigationBar()
        setupLayout()

        case1()
        case2()
        case3()
        case4()
        case5()
        case6()
        case7()
        case8()
        case9()
        case10()
        // 阿拉伯语（RTL）
        case11()
        case12()
        case13()
        case14()
        case15()
        case16()
        // 自定义正则规则
        case17()
        case18()
        case19()
        case20()
        stackView.addArrangedSubview(historyCard)

        refreshTapViews()
    }

    private func setupNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(hex: 0xD0BCFF) // inversePrimary
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = .black

        let clear = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(clearHistory))
        clear.accessibilityLabel = "清空点击记录"
        navigationItem.rightBarButtonItem = clear
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "OC", style: .plain,
                                                           target: self, action: #selector(openOCDemo))
    }

    /// Objective-C 示例页（OCDemoViewController.m），通过类名加载，无需桥接头文件
    @objc private func openOCDemo() {
        guard let cls = NSClassFromString("OCDemoViewController") as? UIViewController.Type else { return }
        let vc = cls.init()
        vc.title = "Objective-C Demo"
        navigationController?.pushViewController(vc, animated: true)
    }

    private func setupLayout() {
        let divider = UIView()
        divider.backgroundColor = UIColor(white: 0, alpha: 0.12)

        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .fill

        [tapInfoPanel, divider, scrollView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            tapInfoPanel.topAnchor.constraint(equalTo: safe.topAnchor),
            tapInfoPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tapInfoPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            divider.topAnchor.constraint(equalTo: tapInfoPanel.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -12),
        ])
    }

    // MARK: Events

    private func onTap(_ caseName: String, _ info: HTagInfo, action: String = "onTagTap（兜底）") {
        let record = TapRecord(caseName: caseName, info: info, action: action)
        last = record
        history.insert(record, at: 0)
        if history.count > 20 { history.removeLast() }
        print("[\(caseName)] \(action) -> \(info)")
        refreshTapViews()
    }

    private func onParsed(_ caseName: String, _ tags: [HTagInfo]) {
        cards[caseName]?.parsed = tags
    }

    @objc private func clearHistory() {
        last = nil
        history.removeAll()
        refreshTapViews()
    }

    private func refreshTapViews() {
        tapInfoPanel.record = last
        historyCard.history = history
    }

    // MARK: Helper

    /// 添加一个用例卡片：标题 + 原始字符串 + 渲染效果 + onParsed 结果
    @discardableResult
    private func addCase(_ name: String,
                         source: String,
                         tappable: Bool = true,
                         configure: (ZLTagRichLabel) -> Void) -> ZLTagRichLabel {
        let label = ZLTagRichLabel(frame: .zero)
        label.numberOfLines = 0
        label.verticalAlignment = .top
        label.update { v in
            v.style = HTagDemoPage.baseStyle
            if tappable {
                v.onTagTap = { [weak self] info in self?.onTap(name, info) }
            }
            v.onParsed = { [weak self] tags in self?.onParsed(name, tags) }
            configure(v)
            v.text = source // 等同于 v.tagText = source
        }

        let card = DemoCard(title: name, source: source, content: label)
        cards[name] = card
        stackView.addArrangedSubview(card)
        return label
    }

    /// 添加一个纯自定义规则的用例：直接使用基类 ZLRichLabel（不解析 <h> 标签）
    /// 卡片底部展示最终生效的规则命中（解析是同步的，设置 text 后即可读取 `matches`）
    @discardableResult
    private func addRuleCase(_ name: String,
                             source: String,
                             configure: (ZLRichLabel) -> Void) -> ZLRichLabel {
        let label = ZLRichLabel(frame: .zero)
        label.numberOfLines = 0
        label.verticalAlignment = .top
        label.update { v in
            v.style = HTagDemoPage.baseStyle
            configure(v)
            v.text = source // 等同于 v.rawText = source
        }

        let card = DemoCard(title: name, source: source, content: label)
        card.matches = label.matches
        cards[name] = card
        stackView.addArrangedSubview(card)
        return label
    }

    // MARK: - 各用例

    /// 1. 按标签名区分样式（tagStyles）
    private func case1() {
        addCase("1. 按标签名区分样式（h1 / h2）",
                source: "By logging in or registering an account, you agree to the "
                    + "<h1>User Agreement</h1> and <h2>Privacy Policy</h2>.") { v in
            v.tagStyle = [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]
            v.tagStyles = [
                "h1": [
                    .foregroundColor: UIColor.mBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: UIColor.mBlue,
                ],
                "h2": [.foregroundColor: UIColor.mDeepOrange],
            ]
        }
    }

    /// 2. 只用 <h>，按 index 区分样式（tagStyleBuilder）
    private func case2() {
        let colors: [UIColor] = [.mRed, .mGreen, .mPurple]
        addCase("2. 同名标签 <h>，按 index 区分样式",
                source: "Fruits: <h>Apple</h>, <h>Banana<h/> and <h>Cherry</h>.") { v in
            v.tagStyleBuilder = { info in
                [
                    .foregroundColor: colors[info.index % colors.count],
                    .font: UIFont.boldSystemFont(ofSize: 15),
                ]
            }
        }
    }

    /// 3. 多种标签名 + 两种闭合写法 + 大小写
    private func case3() {
        addCase("3. h / h1 / h2 / h3 / H4，</hN> 与 <hN/> 闭合",
                source: "<h>Default</h>, <h1>Level one<h1/>, <h2>Level two</h2>, "
                    + "<h3>Level three<h3/> and <H4>Upper case</H4>.") { v in
            v.tagStyle = [.foregroundColor: UIColor.mBlue]
            v.tagStyles = [
                "h1": [.font: UIFont.boldSystemFont(ofSize: 15),
                       .underlineStyle: NSUnderlineStyle.single.rawValue],
                "h2": [.foregroundColor: UIColor.mGreen,
                       .font: UIFont.italicSystemFont(ofSize: 15)],
                "h3": [.foregroundColor: UIColor.mPurple,
                       .backgroundColor: UIColor(hex: 0xEDE7F6)],
                "h4": [.foregroundColor: UIColor.mRed,
                       .strikethroughStyle: NSUnderlineStyle.single.rawValue],
            ]
        }
    }

    /// 4. 按标签名区分点击（tagTapHandlers），没有 handler 的走 onTagTap 兜底
    private func case4() {
        let name = "4. 按标签名区分点击（tagTapHandlers）"
        addCase(name,
                source: "Read <h1>User Agreement</h1>, <h2>Privacy Policy</h2> "
                    + "and <h3>FAQ</h3> (h3 has no handler → onTagTap).") { v in
            v.tagStyles = [
                "h1": [.foregroundColor: UIColor.mBlue],
                "h2": [.foregroundColor: UIColor.mDeepOrange],
                "h3": [.foregroundColor: UIColor.mTeal],
            ]
            v.tagTapHandlers = [
                "h1": { [weak self] info in self?.onTap(name, info, action: "h1 handler → 打开用户协议") },
                "h2": { [weak self] info in self?.onTap(name, info, action: "h2 handler → 打开隐私政策") },
            ]
        }
    }

    /// 5. 按标签名区分按下高亮（tagHighlightStyles）
    private func case5() {
        addCase("5. 按标签名区分按下高亮（长按查看）",
                source: "Press and hold: <h1>Yellow bg</h1> / <h2>Red text</h2> / "
                    + "<h3>No highlight</h3> / <h>Default grey</h>.") { v in
            v.tagStyle = [.foregroundColor: UIColor.mBlue]
            v.tagHighlightStyle = [.backgroundColor: UIColor(hex: 0xE0E0E0)] // 默认（<h>）
            v.tagHighlightStyles = [
                "h1": [.backgroundColor: UIColor(hex: 0xFFF59D)],
                "h2": [.foregroundColor: UIColor.mRed,
                       .underlineStyle: NSUnderlineStyle.single.rawValue],
                "h3": [:], // 不高亮
            ]
        }
    }

    /// 6. 容错：[] 原样展示 / 开闭不匹配 / 未闭合 / 嵌套 / 非 h 标签
    private func case6() {
        addCase("6. 容错：[] 原样 / 不匹配 / 未闭合 / 嵌套",
                source: "Brackets kept: <h1>Terms[1]</h1>; mismatched: <h1>X</h2>; "
                    + "unclosed: <h2>Y; nested: <h1>a<h2>b</h2>c</h1>; not h: <hx>no</hx>.") { v in
            v.tagStyles = [
                "h1": [.foregroundColor: UIColor.mTeal, .font: UIFont.boldSystemFont(ofSize: 15)],
                "h2": [.foregroundColor: UIColor.mPink, .font: UIFont.boldSystemFont(ofSize: 15)],
            ]
        }
    }

    /// 7. tagSpanBuilder：按标签名加图标
    private func case7() {
        let icons: [String: String] = ["h1": "doc.text.fill", "h2": "lock.shield.fill"]
        addCase("7. tagSpanBuilder 按标签名加图标",
                source: "Please read <h1>User Agreement</h1> and "
                    + "<h2>Privacy Policy</h2> carefully, or <h>skip</h>.") { v in
            v.tagStyle = [.foregroundColor: UIColor.mIndigo]
            v.tagSpanBuilder = { info, style in
                // 返回 nil 使用默认样式
                guard let icon = icons[info.name],
                      let image = UIImage(systemName: icon)?.withRenderingMode(.alwaysTemplate) else { return nil }

                // 图标：NSTextAttachment 会被组件自动转换为可点击的 View
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)

                let result = NSMutableAttributedString(attachment: attachment)
                result.addAttributes(style, range: NSRange(location: 0, length: result.length))
                result.append(NSAttributedString(string: "《\(info.text)》", attributes: style))
                return result
            }
        }
    }

    /// 8. 无点击事件
    private func case8() {
        addCase("8. 无点击（无 onTagTap / tagTapHandlers）",
                source: "Plain text. <h1>Not clickable</h1> and <h2>neither</h2>.",
                tappable: false) { v in
            v.tagStyles = ["h1": [.foregroundColor: UIColor.mBrown],
                           "h2": [.foregroundColor: UIColor.mGrey]]
        }
    }

    /// 9. 多行 + maxLines 省略
    private func case9() {
        addCase("9. maxLines = 2 + 省略号",
                source: "This is a very long text to demonstrate the maxLines and "
                    + "overflow parameters. <h1>First</h1> link, some more words, "
                    + "<h2>Second</h2> link, and even more words that will be cut off "
                    + "here <h3>Hidden</h3>.") { v in
            v.numberOfLines = 2
            v.lineBreakMode = .byTruncatingTail
            v.tagStyle = [.foregroundColor: UIColor.mBlue]
        }
    }

    /// 10. tagWidgetBuilder：按标签名展示不同的自定义 View
    private func case10() {
        addCase("10. tagWidgetBuilder 按标签名自定义 View",
                source: "Replace: <h1>Follow</h1>  Before: <h2>Hot topic</h2>  "
                    + "After: <h3>Alice</h3>  Default: <h>Plain</h>") { v in
            v.tagStyle = [.foregroundColor: UIColor.mBlue]
            v.tagWidgetBuilder = { info, _ in
                switch info.name {
                case "h1": return DemoWidgets.button("+ \(info.text) #\(info.index)")   // 替换文字
                case "h2": return DemoWidgets.redDot(position: .before)                 // 文字前
                case "h3": return DemoWidgets.vipBadge(position: .after)                // 文字后
                default: return nil                                                     // 默认文字
                }
            }
        }
    }

    /// 11. View 自己处理交互（tappable: false）
    private func case11() {
        case11Label = addCase("11. Widget 自带交互 (tappable: false)",
                              source: "<h0>check</h0> I have read and agree to the "
                                  + "<h1>User Agreement</h1> and <h2>Privacy Policy</h2>.") { v in
            v.tagStyle = [.foregroundColor: UIColor.mBlue]
            v.tagWidgetBuilder = { [weak self] info, _ in
                guard let self = self, info.name == "h0" else { return nil }
                return DemoWidgets.checkbox(checked: self.agreed11, target: self, action: #selector(self.toggleAgree11))
            }
        }
    }

    @objc private func toggleAgree11() {
        agreed11.toggle()
        case11Label?.rebuild()
    }

    // MARK: - 阿拉伯语（RTL）用例

    /// 12. 阿拉伯语：按标签名区分样式与点击
    private func case12() {
        let name = "12. 阿拉伯语：按标签名区分样式与点击"
        addCase(name,
                source: "بتسجيل الدخول أو إنشاء حساب، فإنك توافق على "
                    + "<h1>اتفاقية المستخدم</h1> و<h2>سياسة الخصوصية</h2>.") { v in
            v.tagStyle = [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]
            v.tagStyles = [
                "h1": [.foregroundColor: UIColor.mBlue,
                       .underlineStyle: NSUnderlineStyle.single.rawValue],
                "h2": [.foregroundColor: UIColor.mDeepOrange],
            ]
            v.tagTapHandlers = [
                "h1": { [weak self] info in self?.onTap(name, info, action: "h1 handler → اتفاقية المستخدم") },
                "h2": { [weak self] info in self?.onTap(name, info, action: "h2 handler → سياسة الخصوصية") },
            ]
        }
    }

    /// 13. 阿拉伯语 + 英文混排（双向文本）
    private func case13() {
        addCase("13. 阿拉伯语 + 英文混排",
                source: "اقرأ <h1>Terms of Service</h1> ثم <h2>الأسئلة الشائعة</h2> "
                    + "وتواصل مع <h3>Support Team</h3> أو <h>نحن</h>.") { v in
            v.tagStyle = [.foregroundColor: UIColor.mBlue]
            v.tagStyles = [
                "h1": [.font: UIFont.boldSystemFont(ofSize: 15),
                       .underlineStyle: NSUnderlineStyle.single.rawValue],
                "h2": [.backgroundColor: UIColor(hex: 0xE0E0E0)],
                "h3": [.foregroundColor: UIColor.mGreen],
            ]
        }
    }

    /// 14. 阿拉伯语多行 + maxLines 省略
    private func case14() {
        addCase("14. 阿拉伯语 maxLines = 2 + 省略号",
                source: "هذا نص طويل جدًا لإظهار خاصية الحد الأقصى لعدد الأسطر. "
                    + "<h1>الرابط الأول</h1> بعض الكلمات الإضافية، "
                    + "<h2>الرابط الثاني</h2> والمزيد من الكلمات التي سيتم قطعها هنا "
                    + "<h3>مخفي</h3>.") { v in
            v.numberOfLines = 2
            v.lineBreakMode = .byTruncatingTail
            v.tagStyle = [.foregroundColor: UIColor.mBlue]
        }
    }

    /// 15. 阿拉伯语 + 按标签名自定义 View / 图标
    private func case15() {
        addCase("15. 阿拉伯语 + 自定义 Widget / 图标",
                source: "تابع: <h1>متابعة</h1>  جديد: <h2>موضوع رائج</h2>  "
                    + "مميز: <h3>علي</h3>  اقرأ <h4>الاتفاقية</h4>.") { v in
            v.tagStyle = [.foregroundColor: UIColor.mBlue]
            v.tagSpanBuilder = { info, style in
                guard info.name == "h4",
                      let image = UIImage(systemName: "doc.text.fill")?.withRenderingMode(.alwaysTemplate) else { return nil }
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
                let result = NSMutableAttributedString(attachment: attachment)
                result.addAttributes(style, range: NSRange(location: 0, length: result.length))
                result.append(NSAttributedString(string: "«\(info.text)»", attributes: style))
                return result
            }
            v.tagWidgetBuilder = { info, _ in
                switch info.name {
                case "h1": return DemoWidgets.button("+ \(info.text)")
                case "h2": return DemoWidgets.redDot(position: .before)
                case "h3": return DemoWidgets.vipBadge(position: .after)
                default: return nil
                }
            }
        }
    }

    /// 16. 阿拉伯语 + 勾选框（tappable: false）
    private func case16() {
        case16Label = addCase("16. 阿拉伯语 + 勾选框 (tappable: false)",
                              source: "<h0>check</h0> لقد قرأت وأوافق على "
                                  + "<h1>اتفاقية المستخدم</h1> و<h2>سياسة الخصوصية</h2>.") { v in
            v.tagStyle = [.foregroundColor: UIColor.mBlue]
            v.tagWidgetBuilder = { [weak self] info, _ in
                guard let self = self, info.name == "h0" else { return nil }
                return DemoWidgets.checkbox(checked: self.agreed16, target: self, action: #selector(self.toggleAgree16))
            }
        }
    }

    @objc private func toggleAgree16() {
        agreed16.toggle()
        case16Label?.rebuild()
    }

    // MARK: - 自定义正则规则用例

    /// 自定义规则点击 → 记录到点击面板
    private func onRuleTap(_ caseName: String, _ ctx: TagRichRuleContext, action: String) {
        let info = HTagInfo(index: ctx.match.index, name: "rule:\(ctx.ruleName)",
                            text: ctx.attributedString.string, raw: ctx.matchedText)
        onTap(caseName, info, action: action)
    }

    /// 17. 自定义规则（基类 ZLRichLabel）：@提及 / #话题# / 链接（NSDataDetector）
    private func case17() {
        let name = "17. ZLRichLabel 自定义规则：@提及 / #话题# / 链接"
        addRuleCase(name,
                    source: "Hi @alice and @bob_99, join #SwiftUI# talk: https://www.apple.com/swift") { v in
            // @提及
            try? v.addRule(name: "mention", pattern: "@\\w+", priority: 10) { [weak self] ctx in
                ctx.addAttributes([.foregroundColor: UIColor.mPurple,
                                   .font: UIFont.systemFont(ofSize: 15, weight: .semibold)])
                ctx.onTap = { self?.onRuleTap(name, ctx, action: "mention → 打开 \(ctx.matchedText) 的主页") }
            }
            // #话题#
            try? v.addRule(name: "topic", pattern: "#[^#\\s]+#", priority: 10) { [weak self] ctx in
                ctx.addAttributes([.foregroundColor: UIColor.mDeepOrange])
                ctx.highlightStyle = [.backgroundColor: UIColor(hex: 0xFFE0B2)]
                ctx.onTap = { self?.onRuleTap(name, ctx, action: "topic → 打开话题 \(ctx.matchedText)") }
            }
            // 链接：NSDataDetector 也是 NSRegularExpression，替换展示文字
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
                v.addRule(TagRichRule(name: "link", regex: detector, priority: 10) { [weak self] ctx in
                    let url = ctx.match.result.url?.absoluteString ?? ctx.matchedText
                    ctx.setText("🔗网页链接", attributes: [.foregroundColor: UIColor.mBlue,
                                                       .underlineStyle: NSUnderlineStyle.single.rawValue])
                    ctx.onTap = { self?.onRuleTap(name, ctx, action: "link → 打开 \(url)") }
                })
            }
        }
    }

    /// 18. 外部解析后替换内容（基类 ZLRichLabel）：表情图片 / 模板变量（命名捕获组）
    private func case18() {
        let name = "18. ZLRichLabel 外部解析替换：[smile] 表情 / {{变量}}"
        let symbols = ["smile": "face.smiling", "heart": "heart.fill", "star": "star.fill"]
        let colors: [String: UIColor] = ["smile": .mOrange, "heart": .mRed, "star": .mAmber]
        let variables = ["name": "Alice", "count": "3"]
        addRuleCase(name,
                    source: "Hello {{name}} [smile], you have {{count}} new messages [heart][star]. "
                        + "Unknown: {{foo}} [xxx].") { v in
            // 表情：把 [smile] 替换为图片（NSTextAttachment 会被自动转换为 View），点击图片也能响应
            try? v.addRule(name: "emoji", pattern: "\\[(smile|heart|star)\\]", priority: 5) { [weak self] ctx in
                guard let key = ctx.group(1), let symbol = symbols[key],
                      let image = UIImage(systemName: symbol)?.withRenderingMode(.alwaysTemplate) else { return }
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(x: 0, y: 0, width: 17, height: 17)
                let content = NSMutableAttributedString(attachment: attachment)
                content.addAttributes([.foregroundColor: colors[key] ?? UIColor.mGrey],
                                      range: NSRange(location: 0, length: content.length))
                ctx.attributedString.setAttributedString(content)
                ctx.onTap = { self?.onRuleTap(name, ctx, action: "emoji → \(key)") }
                
            }
            // 模板变量：命名捕获组取 key，外部查值后写回
            try? v.addRule(name: "variable", pattern: "\\{\\{(?<key>\\w+)\\}\\}", priority: 5) { ctx in
                let key = ctx.group(named: "key") ?? ""
                if let value = variables[key] {
                    ctx.setText(value, attributes: [.font: UIFont.boldSystemFont(ofSize: 15),
                                                    .foregroundColor: UIColor.mTeal])
                } else {
                    ctx.addAttributes([.foregroundColor: UIColor.mGrey,
                                       .strikethroughStyle: NSUnderlineStyle.single.rawValue])
                }
            }
        }
    }

    /// 19. 优先级：手机号规则(20) > <h> 标签(hTagPriority) > 数字规则(1)
    /// 需要和 <h> 标签比较优先级，所以这里用 ZLTagRichLabel
    private func case19() {
        let source = "Call <h1>13800138000</h1> or 400-123-4567, order 2024."
        let configure: (ZLTagRichLabel, String) -> Void = { [weak self] v, name in
            v.tagStyle = [.foregroundColor: UIColor.mBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
            try? v.addRule(name: "phone", pattern: "1\\d{10}", priority: 20) { ctx in
                ctx.addAttributes([.foregroundColor: UIColor.mGreen, .font: UIFont.boldSystemFont(ofSize: 15)])
                ctx.onTap = { self?.onRuleTap(name, ctx, action: "phone(20) → 拨打 \(ctx.matchedText)") }
            }
            try? v.addRule(name: "number", pattern: "\\d+", priority: 1) { ctx in
                ctx.addAttributes([.backgroundColor: UIColor(hex: 0xE0E0E0)])
            }
        }
        let nameA = "19a. 优先级：phone(20) > h1(0) > number(1)?"
        addCase(nameA, source: source) { v in
            v.hTagPriority = 0 // h1 与 phone 重叠，phone 优先级更高 → h1 整体作废，<h1> 原样显示
            configure(v, nameA)
        }
        let nameB = "19b. 优先级：h1(100) > phone(20) > number(1)"
        addCase(nameB, source: source) { v in
            v.hTagPriority = 100 // h1 优先，内部的手机号不再被规则处理
            configure(v, nameB)
        }
    }

    /// 20. 只用自定义规则（基类 ZLRichLabel，不解析 <h> 标签）：简易 Markdown
    private func case20() {
        addRuleCase("20. ZLRichLabel 简易 Markdown（<h> 不解析）",
                    source: "<h1>not parsed</h1>, **bold**, ~~strike~~, `code` and **nested `x`**.") { v in
            // 长的 **...** 先占位（同优先级位置靠前 / 更长优先），内部的 `x` 不会再被处理
            try? v.addRule(name: "bold", pattern: "\\*\\*(.+?)\\*\\*") { ctx in
                ctx.setText(ctx.group(1) ?? "", attributes: [.font: UIFont.boldSystemFont(ofSize: 15)])
            }
            try? v.addRule(name: "strike", pattern: "~~(.+?)~~") { ctx in
                ctx.setText(ctx.group(1) ?? "", attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
            }
            try? v.addRule(name: "code", pattern: "`([^`]+)`") { ctx in
                ctx.setText(ctx.group(1) ?? "", attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                    .backgroundColor: UIColor(hex: 0xEEEEEE),
                    .foregroundColor: UIColor.mPink,
                ])
            }
        }
    }
}


// MARK: - 自定义 Widget

private enum DemoWidgets {
    /// 按钮样式（替换文字）
    static func button(_ title: String) -> HTagWidget {
        let button = PaddingLabel(insets: UIEdgeInsets(top: 2, left: 10, bottom: 2, right: 10))
        button.text = title
        button.font = .systemFont(ofSize: 12)
        button.textColor = .white
        button.backgroundColor = .mBlue
        button.layer.cornerRadius = 12
        button.layer.masksToBounds = true
        return HTagWidget(view: button, size: button.intrinsicContentSize)
    }

    /// 红点（与文字间距 4）
    static func redDot(position: HTagWidgetPosition) -> HTagWidget {
        let container = UIView()
        let dot = UIView(frame: CGRect(x: 2, y: 0, width: 8, height: 8))
        dot.backgroundColor = .mRed
        dot.layer.cornerRadius = 4
        container.addSubview(dot)
        return HTagWidget(view: container, size: CGSize(width: 12, height: 8), position: position)
    }

    /// VIP 徽章（与文字间距 4）
    static func vipBadge(position: HTagWidgetPosition) -> HTagWidget {
        let badge = PaddingLabel(insets: UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4))
        badge.text = "VIP"
        badge.font = .boldSystemFont(ofSize: 10)
        badge.textColor = .white
        badge.backgroundColor = .mAmber
        badge.layer.cornerRadius = 4
        badge.layer.masksToBounds = true
        let size = badge.intrinsicContentSize
        badge.frame = CGRect(x: 2, y: 0, width: size.width, height: size.height)
        let container = UIView()
        container.addSubview(badge)
        return HTagWidget(view: container, size: CGSize(width: size.width + 4, height: size.height), position: position)
    }

    /// 勾选框（自己处理点击，不触发 onTagTap）
    static func checkbox(checked: Bool, target: Any, action: Selector) -> HTagWidget {
        let container = UIView()
        let icon = UIImageView(frame: CGRect(x: 2, y: 0, width: 18, height: 18))
        icon.image = UIImage(systemName: checked ? "checkmark.circle.fill" : "circle")
        icon.tintColor = checked ? .mGreen : .mGrey
        container.addSubview(icon)
        container.addGestureRecognizer(UITapGestureRecognizer(target: target, action: action))
        return HTagWidget(view: container, size: CGSize(width: 22, height: 18), tappable: false)
    }
}

// MARK: - UI 辅助组件

/// 顶部：最近一次点击得到的完整信息
private final class TapInfoPanel: UIView {

    var record: TapRecord? { didSet { update() } }

    private let titleLabel = UILabel()
    private let tableLabel = UILabel()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(hex: 0xF3F0FA)

        titleLabel.numberOfLines = 0
        tableLabel.numberOfLines = 0
        stack.axis = .vertical
        stack.spacing = 6
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(tableLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func update() {
        guard let r = record else {
            titleLabel.text = "👆 点击下方任意高亮文字，这里会显示点击得到的所有信息"
            titleLabel.font = .systemFont(ofSize: 14)
            titleLabel.textColor = UIColor(white: 0, alpha: 0.54)
            tableLabel.isHidden = true
            return
        }
        titleLabel.text = "最近点击 · \(r.caseName)\n动作：\(r.action)"
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.textColor = .black
        tableLabel.isHidden = false
        tableLabel.attributedText = InfoTable.make(r.info)
    }
}

/// HTagInfo 所有字段的表格展示（等宽字体对齐）
private enum InfoTable {
    static func make(_ info: HTagInfo) -> NSAttributedString {
        func q(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "null" }
        let rows: [(String, String)] = [
            ("index", "\(info.index)"),
            ("name", q(info.name)),
            ("level", info.level.map { "\($0)" } ?? "null"),
            ("text", q(info.text)),
            ("raw", q(info.raw)),
        ]
        let keyWidth = (rows.map { $0.0.count }.max() ?? 0) + 2
        let font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let result = NSMutableAttributedString()
        for (i, row) in rows.enumerated() {
            let key = row.0.padding(toLength: keyWidth, withPad: " ", startingAt: 0)
            result.append(NSAttributedString(string: key, attributes: [.font: font, .foregroundColor: UIColor.mDeepPurple]))
            result.append(NSAttributedString(string: row.1 + (i < rows.count - 1 ? "\n" : ""),
                                             attributes: [.font: font, .foregroundColor: UIColor.black]))
        }
        return result
    }
}

/// 卡片基类
private class CardView: UIView {
    let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)

        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func label(_ text: String, font: UIFont, color: UIColor = .black) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        return label
    }
}

/// 单个用例卡片：标题 + 原始字符串 + 渲染效果 + onParsed 结果
private final class DemoCard: CardView {

    var parsed: [HTagInfo]? { didSet { updateParsed() } }
    /// 基类 ZLRichLabel 用例：展示最终生效的规则命中
    var matches: [TagRichMatch]? { didSet { updateParsed() } }

    private let parsedTitle = CardView.label("", font: .systemFont(ofSize: 12), color: UIColor(white: 0, alpha: 0.45))
    private let parsedLabel = CardView.label("", font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                                             color: UIColor(white: 0, alpha: 0.54))

    init(title: String, source: String, content: UIView) {
        super.init(frame: .zero)

        let titleLabel = CardView.label(title, font: .boldSystemFont(ofSize: 15))
        let sourceTitle = CardView.label("原始字符串：", font: .systemFont(ofSize: 12), color: UIColor(white: 0, alpha: 0.45))

        // 可选中复制的原始字符串（对应 SelectableText）
        let sourceView = UITextView()
        sourceView.text = source
        sourceView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        sourceView.isEditable = false
        sourceView.isSelectable = true
        sourceView.isScrollEnabled = false
        sourceView.backgroundColor = UIColor(hex: 0xF5F5F5)
        sourceView.layer.cornerRadius = 6
        sourceView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)

        let renderTitle = CardView.label("渲染效果：", font: .systemFont(ofSize: 12), color: UIColor(white: 0, alpha: 0.45))

        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(8, after: titleLabel)
        stack.addArrangedSubview(sourceTitle)
        stack.setCustomSpacing(4, after: sourceTitle)
        stack.addArrangedSubview(sourceView)
        stack.setCustomSpacing(8, after: sourceView)
        stack.addArrangedSubview(renderTitle)
        stack.setCustomSpacing(4, after: renderTitle)
        stack.addArrangedSubview(content)
        stack.setCustomSpacing(8, after: content)
        stack.addArrangedSubview(parsedTitle)
        stack.setCustomSpacing(4, after: parsedTitle)
        stack.addArrangedSubview(parsedLabel)
        updateParsed()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateParsed() {
        if parsed == nil, let matches = matches {
            parsedTitle.isHidden = false
            parsedLabel.isHidden = matches.isEmpty
            parsedTitle.text = "规则命中 matches（共 \(matches.count) 个）："
            parsedLabel.text = matches.map { m in
                "#\(m.index)  [\(m.rule.name)]  text=\"\(m.text)\"  priority=\(m.rule.priority)"
            }.joined(separator: "\n")
            return
        }
        guard let parsed = parsed else {
            parsedTitle.isHidden = true
            parsedLabel.isHidden = true
            return
        }
        parsedTitle.isHidden = false
        parsedLabel.isHidden = parsed.isEmpty
        parsedTitle.text = "onParsed 回调（共 \(parsed.count) 个标签）："
        parsedLabel.text = parsed.map { t in
            "#\(t.index)  <\(t.name)>  text=\"\(t.text)\"  level=\(t.level.map { "\($0)" } ?? "null")"
        }.joined(separator: "\n")
    }
}

/// 点击历史
private final class HistoryCard: CardView {

    var history: [TapRecord] = [] { didSet { update() } }

    private let titleLabel = CardView.label("", font: .boldSystemFont(ofSize: 15))
    private let contentLabel = CardView.label("", font: .monospacedSystemFont(ofSize: 11, weight: .regular))

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.spacing = 6
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(contentLabel)
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func update() {
        titleLabel.text = "点击历史（\(history.count)）"
        if history.isEmpty {
            contentLabel.attributedText = nil
            contentLabel.text = "暂无"
            contentLabel.font = .systemFont(ofSize: 14)
            contentLabel.textColor = UIColor(white: 0, alpha: 0.45)
            return
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 4
        let text = history.map { r -> String in
            let caseNo = r.caseName.split(separator: " ").first.map(String.init) ?? ""
            return "\(HistoryCard.formatter.string(from: r.time))  \(caseNo) "
                + "<\(r.info.name)> index=\(r.info.index) text=\"\(r.info.text)\" "
                + "action=\(r.action)"
        }.joined(separator: "\n")
        contentLabel.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph,
        ])
    }
}

/// 带内边距的 UILabel（对应 Container + padding）
private final class PaddingLabel: UILabel {
    let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
        textAlignment = .center
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: ceil(size.width + insets.left + insets.right),
                      height: ceil(size.height + insets.top + insets.bottom))
    }
}

// MARK: - Material 颜色

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    static let mBlue = UIColor(hex: 0x2196F3)
    static let mDeepOrange = UIColor(hex: 0xFF5722)
    static let mRed = UIColor(hex: 0xF44336)
    static let mGreen = UIColor(hex: 0x4CAF50)
    static let mPurple = UIColor(hex: 0x9C27B0)
    static let mDeepPurple = UIColor(hex: 0x673AB7)
    static let mOrange = UIColor(hex: 0xFF9800)
    static let mGrey = UIColor(hex: 0x9E9E9E)
    static let mTeal = UIColor(hex: 0x009688)
    static let mPink = UIColor(hex: 0xE91E63)
    static let mIndigo = UIColor(hex: 0x3F51B5)
    static let mBrown = UIColor(hex: 0x795548)
    static let mAmber = UIColor(hex: 0xFFC107)
}
