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
    let info: ZLTagInfo
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
    /// 用例 21 的状态（label rebuild 时 builder 会按状态重新创建 View）
    private var boxWidth21: CGFloat = 24
    private var likes21 = 0
    /// 用例 22：外观 / 字号覆盖只作用在预览区域
    private weak var case22Preview: UIView?
    private weak var case22Label: ZLTagRichLabel?
    /// 用例 23：性能（渲染缓存 / 排版缓存）
    private weak var case23Label: ZLRichLabel?
    private weak var case23Stats: UILabel?
    private var mentionPurple23 = true
    private var highlightYellow23 = true
    private var appended23 = 0
    /// 用例 25：长按菜单从手势位置弹出
    private weak var case25Label: ZLTagRichLabel?

    private static let baseStyle: ZLTextStyle = [
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
        // 自定义 View 尺寸变化
        case21()
        // 深色模式 / Dynamic Type
        case22()
        // 性能：渲染缓存 / 排版缓存
        case23()
        // 展开 / 收起
        case24()
        // 长按 / 双击 / 扩大点击热区
        case25()
        // 选中复制
        case26()
        // 通用标签：任意标签名 / 属性 / 嵌套
        case27()
        // 胶囊背景 / 渐变文字
        case28()
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
        let swiftUI = UIBarButtonItem(title: "SwiftUI", style: .plain, target: self, action: #selector(openSwiftUIDemo))
        navigationItem.rightBarButtonItems = [clear, swiftUI]
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "OC", style: .plain,
                                                           target: self, action: #selector(openOCDemo))
    }

    /// SwiftUI 示例页（SwiftUIDemoPage.swift）：ZLRichText 封装
    @objc private func openSwiftUIDemo() {
        navigationController?.pushViewController(SwiftUIDemo.makeViewController(), animated: true)
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

    private func onTap(_ caseName: String, _ info: ZLTagInfo, action: String = "onTagTap（兜底）") {
        let record = TapRecord(caseName: caseName, info: info, action: action)
        last = record
        history.insert(record, at: 0)
        if history.count > 20 { history.removeLast() }
        print("[\(caseName)] \(action) -> \(info)")
        refreshTapViews()
    }

    private func onParsed(_ caseName: String, _ tags: [ZLTagInfo]) {
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
    /// 规则点击：onTap 的参数就是这次点击的命中，不需要（也不要）在回调里引用 ctx
    private func onRuleTap(_ caseName: String, _ match: ZLRichMatch, action: String) {
        onTap(caseName, ruleInfo(match), action: action)
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
                ctx.onTap = { match in self?.onRuleTap(name, match, action: "mention → 打开 \(match.text) 的主页") }
            }
            // #话题#
            try? v.addRule(name: "topic", pattern: "#[^#\\s]+#", priority: 10) { [weak self] ctx in
                ctx.addAttributes([.foregroundColor: UIColor.mDeepOrange])
                ctx.highlightStyle = [.backgroundColor: UIColor(hex: 0xFFE0B2)]
                ctx.onTap = { match in self?.onRuleTap(name, match, action: "topic → 打开话题 \(match.text)") }
            }
            // 链接：NSDataDetector 也是 NSRegularExpression，替换展示文字
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
                v.addRule(ZLRichRule(name: "link", regex: detector, priority: 10) { [weak self] ctx in
                    ctx.setText("🔗网页链接", attributes: [.foregroundColor: UIColor.mBlue,
                                                       .underlineStyle: NSUnderlineStyle.single.rawValue])
                    ctx.onTap = { match in
                        let url = match.result.url?.absoluteString ?? match.text
                        self?.onRuleTap(name, match, action: "link → 打开 \(url)")
                    }
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
                ctx.onTap = { match in self?.onRuleTap(name, match, action: "emoji → \(match.group(1) ?? "")") }
                
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

    /// 19. 优先级：手机号规则(20) > <h> 标签(tagPriority) > 数字规则(1)
    /// 需要和 <h> 标签比较优先级，所以这里用 ZLTagRichLabel
    private func case19() {
        let source = "Call <h1>13800138000</h1> or 400-123-4567, order 2024."
        let configure: (ZLTagRichLabel, String) -> Void = { [weak self] v, name in
            v.tagStyle = [.foregroundColor: UIColor.mBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
            try? v.addRule(name: "phone", pattern: "1\\d{10}", priority: 20) { ctx in
                ctx.addAttributes([.foregroundColor: UIColor.mGreen, .font: UIFont.boldSystemFont(ofSize: 15)])
                ctx.onTap = { match in self?.onRuleTap(name, match, action: "phone(20) → 拨打 \(match.text)") }
            }
            try? v.addRule(name: "number", pattern: "\\d+", priority: 1) { ctx in
                ctx.addAttributes([.backgroundColor: UIColor(hex: 0xE0E0E0)])
            }
        }
        let nameA = "19a. 优先级：phone(20) > h1(0) > number(1)?"
        addCase(nameA, source: source) { v in
            v.tagPriority = 0 // h1 与 phone 重叠，phone 优先级更高 → h1 整体作废，<h1> 原样显示
            configure(v, nameA)
        }
        let nameB = "19b. 优先级：h1(100) > phone(20) > number(1)"
        addCase(nameB, source: source) { v in
            v.tagPriority = 100 // h1 优先，内部的手机号不再被规则处理
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

    // MARK: - 自定义 View 尺寸变化

    /// 21. 自定义 View 尺寸 / 内容变化后，label 自动重新排版
    private func case21() {
        addCase("21. 自定义 View 尺寸变化，自动刷新排版",
                source: "Tap the box <h1>box</h1> to resize it, tap <h2>like</h2> to add likes, "
                    + "the following text reflows automatically.") { v in
            v.tagStyle = [.foregroundColor: UIColor.mBlue]
            v.tagWidgetBuilder = { [weak self] info, _ in
                guard let self = self else { return nil }
                switch info.name {
                case "h1":
                    return DemoWidgets.growBox(width: self.boxWidth21, target: self, action: #selector(self.growBox21(_:)))
                case "h2":
                    return DemoWidgets.likeCounter(self.likes21, target: self, action: #selector(self.like21(_:)))
                default:
                    return nil
                }
            }
        }
    }

    /// 直接修改 View 的 frame 尺寸：label 下次布局时自动检测并重新排版，无需额外调用
    @objc private func growBox21(_ gesture: UITapGestureRecognizer) {
        guard let box = gesture.view else { return }
        boxWidth21 = boxWidth21 >= 120 ? 24 : boxWidth21 + 32
        box.frame.size.width = boxWidth21
    }

    /// 自动尺寸（size == .zero）的 View 内容变化：调用 zl_setNeedsRichLabelLayout() 重新测量
    @objc private func like21(_ gesture: UITapGestureRecognizer) {
        guard let counter = gesture.view as? UILabel else { return }
        likes21 += 1
        counter.text = DemoWidgets.likeText(likes21)
        counter.zl_setNeedsRichLabelLayout()
    }

    // MARK: - 深色模式 / Dynamic Type

    /// 22. 深色模式自动重新渲染 + 按系统文字大小缩放（adjustsFontForContentSizeCategory）
    private func case22() {
        let name = "22. 深色模式 / Dynamic Type"
        let source = "Appearance: {mode}. Read the <h1>User Agreement</h1> <h2>NEW</h2>, "
            + "text, tags and the badge follow dark mode and the system text size."

        let label = ZLTagRichLabel(frame: .zero)
        label.numberOfLines = 0
        label.verticalAlignment = .top
        label.update { [weak label] v in
            v.adjustsFontForContentSizeCategory = true
            // 动态颜色：深色 / 浅色切换后自动适配
            v.style = [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.label]
            v.tagStyle = [
                .foregroundColor: UIColor.dynamic(light: .mBlue, dark: UIColor(hex: 0x90CAF9)),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
            v.onTagTap = { [weak self] info in self?.onTap(name, info) }
            v.onParsed = { [weak self] tags in self?.onParsed(name, tags) }
            // 自定义 View：builder 在外观 / 字号变化时会重新执行，用 scaledFont 让 View 字号一起变化
            v.tagWidgetBuilder = { info, _ in
                guard info.name == "h2", let label = label else { return nil }
                let badge = PaddingLabel(insets: UIEdgeInsets(top: 1, left: 5, bottom: 1, right: 5))
                badge.text = info.text
                badge.font = label.scaledFont(.boldSystemFont(ofSize: 10))
                badge.textColor = .white
                badge.backgroundColor = .dynamic(light: .mDeepOrange, dark: UIColor(hex: 0xFF8A65))
                badge.layer.cornerRadius = 4
                badge.layer.masksToBounds = true
                return ZLRichWidget(view: badge)
            }
            // 规则 handler 也会重新执行：按当前外观返回不同内容
            try? v.addRule(name: "mode", pattern: "\\{mode\\}") { ctx in
                let dark = label?.traitCollection.userInterfaceStyle == .dark
                ctx.setText(dark ? "🌙 Dark" : "☀️ Light",
                            attributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.secondaryLabel])
            }
            v.text = source
        }

        // 预览区域：外观 / 字号的覆盖只作用在这里，不影响整个页面
        let preview = UIView()
        preview.backgroundColor = .secondarySystemBackground
        preview.layer.cornerRadius = 8
        label.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: preview.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -10),
        ])
        case22Preview = preview
        case22Label = label

        let appearance = UISegmentedControl(items: ["跟随系统", "浅色", "深色"])
        appearance.selectedSegmentIndex = 0
        appearance.addTarget(self, action: #selector(appearanceChanged22(_:)), for: .valueChanged)

        let sizes = UISegmentedControl(items: Self.sizeCategories22.map { $0.0 })
        sizes.selectedSegmentIndex = 0
        sizes.addTarget(self, action: #selector(sizeChanged22(_:)), for: .valueChanged)
        let sizeHint = CardView.label("", font: .systemFont(ofSize: 11), color: UIColor(white: 0, alpha: 0.45))
        if #available(iOS 17.0, *) {
            sizeHint.text = "文字大小只覆盖预览区域；选「系统」则跟随 设置 › 显示与亮度 › 文字大小"
        } else {
            sizes.isEnabled = false
            sizeHint.text = "iOS 17 以下请在 设置 › 显示与亮度 › 文字大小 中调整"
        }

        let scaleSwitch = UISwitch()
        scaleSwitch.isOn = true
        scaleSwitch.addTarget(self, action: #selector(scaleSwitchChanged22(_:)), for: .valueChanged)
        let switchRow = UIStackView(arrangedSubviews: [
            CardView.label("adjustsFontForContentSizeCategory", font: .monospacedSystemFont(ofSize: 12, weight: .regular)),
            scaleSwitch,
        ])
        switchRow.alignment = .center

        let content = UIStackView(arrangedSubviews: [appearance, sizes, sizeHint, switchRow, preview])
        content.axis = .vertical
        content.spacing = 8

        let card = DemoCard(title: name, source: source, content: content)
        cards[name] = card
        stackView.addArrangedSubview(card)
    }

    private static let sizeCategories22: [(String, UIContentSizeCategory?)] = [
        ("系统", nil), ("XS", .extraSmall), ("L", .large), ("XXXL", .extraExtraExtraLarge), ("AX3", .accessibilityExtraLarge),
    ]

    @objc private func appearanceChanged22(_ sender: UISegmentedControl) {
        let styles: [UIUserInterfaceStyle] = [.unspecified, .light, .dark]
        case22Preview?.overrideUserInterfaceStyle = styles[sender.selectedSegmentIndex]
    }

    @objc private func sizeChanged22(_ sender: UISegmentedControl) {
        guard #available(iOS 17.0, *), let preview = case22Preview else { return }
        if let category = Self.sizeCategories22[sender.selectedSegmentIndex].1 {
            preview.traitOverrides.preferredContentSizeCategory = category
        } else {
            preview.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
        }
    }

    @objc private func scaleSwitchChanged22(_ sender: UISwitch) {
        case22Label?.adjustsFontForContentSizeCategory = sender.isOn
    }

    // MARK: - 通用标签

    /// 27. 通用标签：任意标签名、标签属性、嵌套、自闭合
    private func case27() {
        let name = "27. 通用标签（任意标签名 / 属性 / 嵌套）"
        let source = "支持 <b>粗体</b>、<i>斜体</i>、<u>下划线</u>、<color value=\"#E91E63\">任意颜色</color>、"
            + "<size value=\"20\">字号</size>。可以嵌套：<b>粗体里 <color value=\"#2196F3\">蓝色 <u>加下划线</u></color></b>。"
            + "链接 <a href=\"https://github.com\">GitHub</a>，图标 <icon name=\"star.fill\" color=\"orange\"/>，"
            + "换行<br/>容错：<b>未闭合的 <i>标签</b> 原样显示，多余的 </u> 也原样显示。"

        addCase(name, source: source) { [weak self] v in
            // 识别任意标签名，支持嵌套和自闭合（默认只识别 <h> / <hN>）
            v.tagConfiguration = .anyTags
            v.tagStyles = [
                "b": [.font: UIFont.boldSystemFont(ofSize: 15)],
                "i": [.font: UIFont.italicSystemFont(ofSize: 15)],
                "u": [.underlineStyle: NSUnderlineStyle.single.rawValue],
                "a": [.foregroundColor: UIColor.mBlue, .underlineStyle: NSUnderlineStyle.single.rawValue],
            ]
            // 按属性设置样式：<color value="…">、<size value="…">
            v.tagStyleBuilder = { info in
                var style: ZLTextStyle = [:]
                if info.name == "color", let color = info.colorAttribute("value") {
                    style[.foregroundColor] = color
                }
                if info.name == "size", let size = info.attribute("value").flatMap(Double.init) {
                    style[.font] = UIFont.systemFont(ofSize: CGFloat(size))
                }
                return style
            }
            // 自闭合标签：<br/> 换行
            v.tagSpanBuilder = { info, style in
                info.name == "br" ? NSAttributedString(string: "\n", attributes: style) : nil
            }
            // 自闭合标签：<icon name="…" color="…"/> 显示 SF Symbol
            v.tagWidgetBuilder = { info, _ in
                guard info.name == "icon", let symbol = info.attribute("name") else { return nil }
                let icon = UIImageView(image: UIImage(systemName: symbol))
                icon.tintColor = info.colorAttribute("color") ?? .mGrey
                icon.contentMode = .scaleAspectFit
                return ZLRichWidget(view: icon, size: CGSize(width: 16, height: 16))
            }
            // <a> 读取 href；其他标签走 onTagTap（内层标签优先响应点击）
            v.tagTapHandlers = ["a": { info in
                self?.onTap(name, info, action: "打开 \(info.attribute("href") ?? "")")
            }]
            v.onTagTap = { info in
                let path = sequence(first: info) { $0.parent }.map { "<\($0.name)>" }.reversed().joined(separator: " › ")
                self?.onTap(name, info, action: "onTagTap  \(path)")
            }
            v.tagHighlightStyles = ["br": [:], "icon": [:]]
        }
    }

    // MARK: - 胶囊背景 / 渐变文字

    /// 28. 胶囊背景（圆角背景 / 边框 / 内边距）与渐变文字，由 label 自己绘制
    private func case28() {
        let name = "28. 胶囊背景 / 渐变文字"
        let source = "<grad>Swift 富文本</grad> <new>NEW</new>\n"
            + "话题：#iOS开发# #SwiftUI##UIKit# 点击胶囊有按下效果。"
            + "行内代码 `label.text = value` 和 `rebuild()`。"
            + "<tag>只有边框</tag> <tag>Tag</tag> "
            + "<rainbow>竖向渐变 + 跨行的长胶囊也能正确绘制，每一行单独一段</rainbow>，"
            + "<pill>很长的胶囊文字在折行时会分成两段分别绘制</pill>。"

        addCase(name, source: source) { [weak self] v in
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 6   // 胶囊的垂直内边距不占行高，加一点行距避免上下行重叠
            v.style = HTagDemoPage.baseStyle.merging([.paragraphStyle: paragraph]) { $1 }
            v.tagConfiguration = .anyTags
            v.tagStyles = [
                // 渐变标题
                "grad": [.font: UIFont.boldSystemFont(ofSize: 22),
                         .zlGradient: ZLTextGradient(colors: [.mPink, .mOrange, .mDeepPurple])],
                // 实心小徽章
                "new": [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.white,
                        .baselineOffset: 3,
                        .zlBackground: ZLTextBackground(fillColor: .mDeepOrange, cornerRadius: 4,
                                                        padding: UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4))],
                // 只有边框
                "tag": [.foregroundColor: UIColor.mTeal, .font: UIFont.systemFont(ofSize: 13),
                        .zlBackground: ZLTextBackground(strokeColor: .mTeal, lineWidth: 1, cornerRadius: -1)],
                // 竖向渐变
                "rainbow": [.font: UIFont.boldSystemFont(ofSize: 15),
                            .zlGradient: ZLTextGradient(colors: [.mBlue, .mGreen], startPoint: CGPoint(x: 0.5, y: 0),
                                                        endPoint: CGPoint(x: 0.5, y: 1))],
                // 跨行的胶囊
                "pill": [.foregroundColor: UIColor.mIndigo,
                         .zlBackground: ZLTextBackground.capsule(.mIndigo)],
            ]
            // 按下高亮：换成更深的胶囊
            v.tagHighlightStyles = [
                "tag": [.zlBackground: ZLTextBackground(fillColor: UIColor.mTeal.withAlphaComponent(0.15),
                                                        strokeColor: .mTeal, cornerRadius: -1)],
                "pill": [.zlBackground: ZLTextBackground(fillColor: UIColor.mIndigo.withAlphaComponent(0.3))],
            ]
            // #话题#：胶囊 + 点击
            try? v.addRule(name: "topic", pattern: "#[^#\\s]+#") { ctx in
                ctx.addAttributes([.foregroundColor: UIColor.mPurple, .zlBackground: ZLTextBackground.capsule(.mPurple)])
                ctx.highlightStyle = [.zlBackground: ZLTextBackground(fillColor: UIColor.mPurple.withAlphaComponent(0.3))]
                ctx.onTap = { match in self?.onRuleTap(name, match, action: "点击话题") }
            }
            // `代码`：去掉反引号，等宽字体 + 灰色背景 + 细边框
            try? v.addRule(name: "code", pattern: "`([^`]+)`") { ctx in
                ctx.setText(ctx.group(1) ?? "", attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: UIColor.mDeepOrange,
                    .zlBackground: ZLTextBackground.code,
                ])
            }
        }
    }

    // MARK: - 选中复制

    /// 26. 选中复制：长按选词、拖动 / 拖柄调整范围，菜单「复制 / 复制原文 / 全选」
    private func case26() {
        let name = "26. 选中复制（isSelectable）"
        let source = "长按选中一个词，拖动手指或两端的拖柄调整范围 [smile]，松手弹出菜单："
            + "「复制」得到展示文字，「复制原文」得到 @alice 和 [smile] 的原始写法。"
            + "点击 <h1>用户协议</h1> 仍然可以跳转，点击文字取消选中。"

        let label = ZLTagRichLabel(frame: .zero)
        label.numberOfLines = 0
        label.verticalAlignment = .top
        let status = CardView.label("长按文字开始选中", font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                                    color: UIColor(white: 0, alpha: 0.6))
        label.update { [weak label, weak status] v in
            v.style = HTagDemoPage.baseStyle
            v.isSelectable = true
            v.tagStyle = [.foregroundColor: UIColor.mBlue]
            v.onTagTap = { [weak self] info in self?.onTap(name, info) }
            // 表情：选中后「复制」得到空（图片），「复制原文」得到 [smile]
            try? v.addRule(name: "emoji", pattern: "\\[smile\\]") { ctx in
                let attachment = NSTextAttachment()
                attachment.image = UIImage(systemName: "face.smiling")?.withRenderingMode(.alwaysTemplate)
                attachment.bounds = CGRect(x: 0, y: 0, width: 17, height: 17)
                let content = NSMutableAttributedString(attachment: attachment)
                content.addAttributes([.foregroundColor: UIColor.mOrange], range: NSRange(location: 0, length: content.length))
                ctx.attributedString.setAttributedString(content)
            }
            // @提及：展示为 👤alice，原文为 @alice（长按命中时整体选中）
            try? v.addRule(name: "mention", pattern: "@\\w+") { ctx in
                ctx.setText("👤" + ctx.matchedText.dropFirst(), attributes: [.foregroundColor: UIColor.mPurple])
            }
            v.onSelectionChanged = { range in
                guard let label = label else { return }
                status?.text = range.location == NSNotFound ? "未选中" :
                    "selectedRange   = {\(range.location), \(range.length)}\n"
                    + "selectedText    = \"\(label.selectedText ?? "")\"\n"
                    + "selectedRawText = \"\(label.selectedRawText ?? "")\""
            }
            v.onCopy = { [weak self] text, isRaw in
                let info = ZLTagInfo(index: 0, name: isRaw ? "copy-raw" : "copy", text: text, raw: "")
                self?.onTap(name, info, action: isRaw ? "onCopy → 复制原文" : "onCopy → 复制展示文字")
            }
            v.text = source
        }

        let content = UIStackView(arrangedSubviews: [label, status])
        content.axis = .vertical
        content.spacing = 8
        let card = DemoCard(title: name, source: source, content: content)
        cards[name] = card
        stackView.addArrangedSubview(card)
    }

    // MARK: - 长按 / 双击 / 扩大点击热区

    /// 25. 长按菜单（复制 / 举报）、按命中区分的长按、双击、扩大点击热区
    private func case25() {
        let name = "25. 长按菜单 / 双击 / 扩大点击热区"
        let source = "Long press blank text to copy or report. Long press <h1>User Agreement</h1> or @alice "
            + "for their own menus, double tap to like ❤️. Tap slightly below @bob: extendsLinkTouchArea "
            + "expands the touch area by up to 15pt."
        case25Label = addCase(name, source: source) { v in
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 10
            v.style = HTagDemoPage.baseStyle.merging([.paragraphStyle: paragraph]) { $1 }
            v.tagStyle = [.foregroundColor: UIColor.mBlue]
            v.tagHighlightStyle = [.backgroundColor: UIColor(white: 0, alpha: 0.08)]
            v.extendsLinkTouchArea = true

            // 规则命中自己的长按：只回调它，不再回调 onLongPress
            try? v.addRule(name: "mention", pattern: "@\\w+") { [weak self] ctx in
                ctx.addAttributes([.foregroundColor: UIColor.mPurple, .font: UIFont.boldSystemFont(ofSize: 15)])
                ctx.onTap = { match in self?.onRuleTap(name, match, action: "mention onTap → 打开 \(match.text) 的主页") }
                ctx.onLongPress = { match in
                    guard let self = self else { return }
                    let user = match.text
                    let info = self.ruleInfo(match)
                    self.showMenu25(title: user, items: [
                        ("复制 \(user)", { [weak self] in self?.copy25(user, caseName: name, info: info) }),
                        ("举报 \(user)", { [weak self] in self?.onTap(name, info, action: "ctx.onLongPress → 举报 \(user)") }),
                    ])
                }
            }
            // 标签的长按
            v.onTagLongPress = { [weak self] info in
                self?.showMenu25(title: "<\(info.name)> \(info.text)", items: [
                    ("复制「\(info.text)」", { self?.copy25(info.text, caseName: name, info: info) }),
                ])
            }
            // 其他位置的长按：复制原文 / 展示文字、举报
            v.onLongPress = { [weak self] gesture in
                let info = ZLTagInfo(index: gesture.characterIndex, name: "long-press",
                                    text: gesture.displayText, raw: gesture.rawText)
                self?.showMenu25(title: "长按位置字符下标：\(gesture.characterIndex)", items: [
                    ("复制原文（rawText）", { self?.copy25(gesture.rawText, caseName: name, info: info) }),
                    ("复制展示文字（displayText）", { self?.copy25(gesture.displayText, caseName: name, info: info) }),
                    ("举报", { self?.onTap(name, info, action: "onLongPress → 举报") }),
                ])
            }
            // 双击：设置后单击链接会等双击判定失败才触发（约 0.3 秒）
            v.onDoubleTap = { [weak self] gesture in
                guard let self = self, let label = self.case25Label else { return }
                let info = ZLTagInfo(index: gesture.characterIndex, name: "double-tap",
                                    text: gesture.matchDisplayText ?? "", raw: gesture.match?.text ?? "")
                self.onTap(name, info, action: "onDoubleTap → 点赞 ❤️（位置 \(Int(gesture.location.x)), \(Int(gesture.location.y))）")
                self.showHeart25(in: label, at: gesture.location)
            }
        }
    }

    /// 在长按位置弹出菜单（iPad 上以 popover 显示）
    private func showMenu25(title: String, items: [(String, () -> Void)]) {
        guard let label = case25Label else { return }
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (itemTitle, action) in items {
            sheet.addAction(UIAlertAction(title: itemTitle, style: .default) { _ in action() })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        let location = label.richLongPressGesture.location(in: label)
        sheet.popoverPresentationController?.sourceView = label
        sheet.popoverPresentationController?.sourceRect = CGRect(origin: location, size: CGSize(width: 1, height: 1))
        present(sheet, animated: true)
    }

    private func copy25(_ text: String, caseName: String, info: ZLTagInfo) {
        UIPasteboard.general.string = text
        onTap(caseName, info, action: "已复制：\(text.prefix(40))\(text.count > 40 ? "…" : "")")
    }

    private func showHeart25(in label: UIView, at point: CGPoint) {
        let heart = UILabel()
        heart.text = "❤️"
        heart.font = .systemFont(ofSize: 28)
        heart.sizeToFit()
        heart.center = point
        label.addSubview(heart)
        UIView.animate(withDuration: 0.6, animations: {
            heart.transform = CGAffineTransform(scaleX: 1.6, y: 1.6).translatedBy(x: 0, y: -12)
            heart.alpha = 0
        }, completion: { _ in heart.removeFromSuperview() })
    }

    // MARK: - 展开 / 收起

    /// 24. 展开 / 收起：超过 numberOfLines 行时末尾显示可点击的「… 全文」，展开后末尾显示「收起」
    private func case24() {
        let long = "<h1>ZLRichLabel</h1> 支持「展开 / 收起」：内容超过 numberOfLines 行时，最后一行末尾显示可点击的「… 全文」，"
            + "点击后展开全部内容，末尾出现「收起」。适用于动态、评论、商品详情等场景。"
            + "展开状态可以保存在数据里，列表复用 cell 时直接设置 isExpanded，不会触发 onExpandChanged。"
            + "<h2>#标签#</h2> 的点击和按下高亮不受影响。"
        let cases = [
            ("24. 展开 / 收起（收起时 3 行）", long),
            ("24b. 内容不足 3 行：不显示「全文」", "<h1>短内容</h1> 不会被截断，也不显示按钮。"),
        ]
        // collapseThreshold：超过阈值才折叠
        let fourLines = "<h1>collapseThreshold = 5</h1>：numberOfLines 仍为 3，但内容不超过 5 行时完整显示、"
            + "不出现「全文」，避免只折叠掉一两行。这段文字在手机宽度下大约 4 行，所以完整显示。"
        let thresholdCases: [(String, String, Int)] = cases.map { ($0.0, $0.1, 0) } + [
            ("24c. collapseThreshold = 5：不超过 5 行完整显示", fourLines, 5),
            ("24d. collapseThreshold = 5：超过 5 行才折叠为 3 行", long + long, 5),
        ]
        for (title, text, threshold) in thresholdCases {
            addCase(title, source: text) { v in
                v.numberOfLines = 3
                v.collapseThreshold = threshold
                v.tagStyle = [.foregroundColor: UIColor.mBlue]
                v.tagHighlightStyle = [.backgroundColor: UIColor(white: 0, alpha: 0.08)]
                let tokenStyle: ZLTextStyle = [.foregroundColor: UIColor.mDeepOrange,
                                                 .font: UIFont.systemFont(ofSize: 15, weight: .semibold)]
                v.expandToken = NSAttributedString(string: "… 全文", attributes: tokenStyle)
                v.collapseToken = NSAttributedString(string: " 收起", attributes: tokenStyle)
                v.onExpandChanged = { [weak self] expanded in
                    guard let self = self else { return }
                    let info = ZLTagInfo(index: 0, name: "expand", text: expanded ? "全文" : "收起", raw: "")
                    self.onTap(title, info, action: "onExpandChanged(\(expanded))")
                    UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
                }
            }
        }
    }

    // MARK: - 性能

    /// 23. 性能：命中的渲染结果按命中缓存、排版结果按「文本 + 宽度」缓存
    private func case23() {
        let name = "23. 性能：渲染缓存 / 排版缓存"
        let count = 200
        let source = (0..<count).map { "@user\($0) [smile] #topic\($0 % 10)# " }.joined()
        let shownSource = "@user0 [smile] #topic0# @user1 [smile] #topic1# …（重复 \(count) 次，共 \(count * 3) 个命中）"

        let label = ZLRichLabel(frame: .zero)
        label.numberOfLines = 4
        label.lineBreakMode = .byTruncatingTail
        label.verticalAlignment = .top
        case23Label = label
        label.update { v in
            v.style = HTagDemoPage.baseStyle
            v.highlightStyle = [.backgroundColor: UIColor.mAmber.withAlphaComponent(0.4)]
            try? v.addRule(name: "mention", pattern: "@\\w+") { [weak self] ctx in
                let purple = self?.mentionPurple23 ?? true
                ctx.addAttributes([.foregroundColor: purple ? UIColor.mPurple : UIColor.mGreen])
                ctx.onTap = { match in self?.onRuleTap(name, match, action: "rule onTap") }
            }
            try? v.addRule(name: "emoji", pattern: "\\[smile\\]") { ctx in
                let attachment = NSTextAttachment()
                attachment.image = UIImage(systemName: "face.smiling")?.withRenderingMode(.alwaysTemplate)
                attachment.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
                ctx.attributedString.setAttributedString(NSAttributedString(attachment: attachment))
                ctx.addAttributes([.foregroundColor: UIColor.mOrange])
            }
            try? v.addRule(name: "topic", pattern: "#\\w+#") { ctx in
                ctx.addAttributes([.foregroundColor: UIColor.mBlue])
            }
        }

        let stats = CardView.label("", font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                                   color: UIColor(white: 0, alpha: 0.7))
        stats.numberOfLines = 0
        case23Stats = stats

        let buttons: [(String, Selector)] = [
            ("改按下高亮", #selector(highlight23)),
            ("末尾追加文字", #selector(append23)),
            ("只刷新 @提及", #selector(recolorMentions23)),
            ("rebuild()", #selector(rebuild23)),
            ("sizeThatFits ×100", #selector(measureSize23)),
            ("解析 1.5 万命中", #selector(parse23)),
        ]
        let rows = stride(from: 0, to: buttons.count, by: 3).map { start -> UIStackView in
            let row = UIStackView(arrangedSubviews: buttons[start..<min(start + 3, buttons.count)].map { title, action in
                var config = UIButton.Configuration.tinted()
                config.title = title
                config.buttonSize = .mini
                let button = UIButton(configuration: config)
                button.titleLabel?.adjustsFontSizeToFitWidth = true
                button.addTarget(self, action: action, for: .touchUpInside)
                return button
            })
            row.distribution = .fillEqually
            row.spacing = 6
            return row
        }

        let content = UIStackView(arrangedSubviews: [label] + rows + [stats])
        content.axis = .vertical
        content.spacing = 8

        let card = DemoCard(title: name, source: shownSource, content: content)
        cards[name] = card
        stackView.addArrangedSubview(card)

        measure23("首次渲染") { label.text = source }
    }

    /// 规则命中 → 点击面板展示的信息（不要在 onTap 里强引用 ctx）
    private func ruleInfo(_ match: ZLRichMatch) -> ZLTagInfo {
        return ZLTagInfo(index: match.index, name: "rule:\(match.rule.name)", text: match.text, raw: match.text)
    }

    /// 执行操作并展示耗时与缓存统计
    private func measure23(_ title: String, _ block: () -> Void) {
        guard let label = case23Label else { return }
        label.statistics.reset()
        let start = CACurrentMediaTime()
        block()
        label.superview?.layoutIfNeeded()
        let ms = (CACurrentMediaTime() - start) * 1000
        let s = label.statistics
        case23Stats?.text = String(format: "%@：%.2f ms\n", title, ms)
            + "handler 执行 \(s.handlerCalls) 次，复用 \(s.reusedMatches) 个命中\n"
            + "渲染 \(s.renders) 次，创建 framesetter \(s.framesetterCreations) 次，尺寸缓存命中 \(s.sizeCacheHits) 次\n"
            + "当前命中 \(label.matches.count) 个，自定义 View \(label.subviews.filter { $0 is UIImageView }.count) 个"
    }

    /// 按下高亮不影响 handler 输出：全部复用
    @objc private func highlight23() {
        highlightYellow23.toggle()
        measure23("改按下高亮") {
            case23Label?.highlightStyle = [.backgroundColor: (highlightYellow23 ? UIColor.mAmber : UIColor.mBlue)
                .withAlphaComponent(0.4)]
        }
    }

    /// 末尾追加：前面命中的位置和内容都没变，只渲染新增的命中
    @objc private func append23() {
        appended23 += 1
        measure23("末尾追加 @new\(appended23)") {
            guard let label = case23Label else { return }
            label.text = label.rawText + "@new\(appended23) "
        }
    }

    /// handler 依赖的外部数据变了，只作废这条规则：表情图片和话题直接复用
    @objc private func recolorMentions23() {
        mentionPurple23.toggle()
        measure23("只刷新 @提及（setNeedsRebuild(forRuleNamed:)）") {
            case23Label?.setNeedsRebuild(forRuleNamed: "mention")
        }
    }

    /// 强制全部重新执行（对比用）
    @objc private func rebuild23() {
        measure23("rebuild() 全部重新执行") { case23Label?.rebuild() }
    }

    /// 同一宽度重复计算尺寸：只有第一次真正排版
    @objc private func measureSize23() {
        measure23("sizeThatFits ×100") {
            guard let label = case23Label else { return }
            let fitting = CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)
            for _ in 0..<100 { _ = label.sizeThatFits(fitting) }
        }
    }

    /// 解析器：1.5 万个命中按优先级去重（原来 O(n²)，现在二分查找 O(n log n)）
    @objc private func parse23() {
        let text = String(repeating: "@user #tag# word ", count: 5000)
        let rules = [
            try! ZLRichRule(name: "mention", pattern: "@\\w+") { _ in },
            try! ZLRichRule(name: "topic", pattern: "#\\w+#") { _ in },
            try! ZLRichRule(name: "word", pattern: "\\w+", priority: -1) { _ in },
        ]
        let start = CACurrentMediaTime()
        let matches = ZLRichParser.resolve(text, rules: rules)
        let ms = (CACurrentMediaTime() - start) * 1000
        case23Stats?.text = String(format: "ZLRichParser.resolve：%.2f ms\n", ms)
            + "文本 \((text as NSString).length) 字符，3 条规则，生效命中 \(matches.count) 个\n"
            + "（含正则匹配耗时；label 未参与）"
    }
}


// MARK: - 自定义 Widget

private enum DemoWidgets {
    /// 可变宽度的色块（固定尺寸，点击时外部直接改 frame）
    static func growBox(width: CGFloat, target: Any, action: Selector) -> ZLRichWidget {
        let box = UIView()
        box.backgroundColor = .mOrange
        box.layer.cornerRadius = 4
        box.addGestureRecognizer(UITapGestureRecognizer(target: target, action: action))
        return ZLRichWidget(view: box, size: CGSize(width: width, height: 16), tappable: false)
    }

    static func likeText(_ likes: Int) -> String { "👍 \(likes)" }

    /// 点赞计数（size 传 .zero 自动计算，文字变化后重新测量）
    static func likeCounter(_ likes: Int, target: Any, action: Selector) -> ZLRichWidget {
        let counter = PaddingLabel(insets: UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6))
        counter.text = likeText(likes)
        counter.font = .systemFont(ofSize: 12)
        counter.textColor = .white
        counter.backgroundColor = .mPink
        counter.layer.cornerRadius = 9
        counter.layer.masksToBounds = true
        counter.isUserInteractionEnabled = true
        counter.addGestureRecognizer(UITapGestureRecognizer(target: target, action: action))
        return ZLRichWidget(view: counter, tappable: false)
    }

    /// 按钮样式（替换文字）
    static func button(_ title: String) -> ZLRichWidget {
        let button = PaddingLabel(insets: UIEdgeInsets(top: 2, left: 10, bottom: 2, right: 10))
        button.text = title
        button.font = .systemFont(ofSize: 12)
        button.textColor = .white
        button.backgroundColor = .mBlue
        button.layer.cornerRadius = 12
        button.layer.masksToBounds = true
        return ZLRichWidget(view: button, size: button.intrinsicContentSize)
    }

    /// 红点（与文字间距 4）
    static func redDot(position: ZLRichWidgetPosition) -> ZLRichWidget {
        let container = UIView()
        let dot = UIView(frame: CGRect(x: 2, y: 0, width: 8, height: 8))
        dot.backgroundColor = .mRed
        dot.layer.cornerRadius = 4
        container.addSubview(dot)
        return ZLRichWidget(view: container, size: CGSize(width: 12, height: 8), position: position)
    }

    /// VIP 徽章（与文字间距 4）
    static func vipBadge(position: ZLRichWidgetPosition) -> ZLRichWidget {
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
        return ZLRichWidget(view: container, size: CGSize(width: size.width + 4, height: size.height), position: position)
    }

    /// 勾选框（自己处理点击，不触发 onTagTap）
    static func checkbox(checked: Bool, target: Any, action: Selector) -> ZLRichWidget {
        let container = UIView()
        let icon = UIImageView(frame: CGRect(x: 2, y: 0, width: 18, height: 18))
        icon.image = UIImage(systemName: checked ? "checkmark.circle.fill" : "circle")
        icon.tintColor = checked ? .mGreen : .mGrey
        container.addSubview(icon)
        container.addGestureRecognizer(UITapGestureRecognizer(target: target, action: action))
        return ZLRichWidget(view: container, size: CGSize(width: 22, height: 18), tappable: false)
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

/// ZLTagInfo 所有字段的表格展示（等宽字体对齐）
private enum InfoTable {
    static func make(_ info: ZLTagInfo) -> NSAttributedString {
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

    var parsed: [ZLTagInfo]? { didSet { updateParsed() } }
    /// 基类 ZLRichLabel 用例：展示最终生效的规则命中
    var matches: [ZLRichMatch]? { didSet { updateParsed() } }

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
            // 嵌套的标签按深度缩进，有属性时一并显示
            let indent = String(repeating: "    ", count: t.depth)
            let attrs = t.attributes.isEmpty ? "" : "  attributes=" + t.attributes.sorted { $0.key < $1.key }
                .map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " ")
            let level = t.name.hasPrefix("h") ? "  level=\(t.level.map { "\($0)" } ?? "null")" : ""
            return "\(indent)#\(t.index)  <\(t.name)>  text=\"\(t.text)\"\(level)\(attrs)"
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

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return intrinsicContentSize
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: ceil(size.width + insets.left + insets.right),
                      height: ceil(size.height + insets.top + insets.bottom))
    }
}

// MARK: - Material 颜色

private extension UIColor {
    static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

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
