//
//  AttributedLabelDemoPage.swift
//  ZLRichLabel_Example
//
//  底层富文本 Label `ZLAttributedLabel` 的全部功能演示（不涉及规则 / 标签，直接设置文字与链接）：
//   1. 纯文本：跟随 font / textColor / textAlignment 变化
//   2. 富文本属性：颜色、字体、下划线、背景色、删除线、字间距、行距、阴影
//   3. 内边距 textInsets + 垂直对齐 verticalAlignment
//   4. 行数与截断：numberOfLines、lineBreakMode（头 / 中 / 尾）、attributedTruncationToken
//   5. 链接：.link 属性、addLink(to:range:)、addLink(range:onTap:)、自定义 ZLLabelLink 样式
//   6. 自动识别：enabledTextCheckingTypes（网址 / 电话 / 日期 / 地址）+ delegate
//   7. 长按链接：link.onLongPress / delegate
//   8. 扩大点击热区：extendsLinkTouchArea
//   9. 失活样式：inactiveLinkAttributes（弹出 alert 时）
//  10. 高亮：isHighlighted + highlightedTextColor
//  11. 尺寸与定位：sizeThatFits、characterIndex(at:)、boundingRect(forCharacterRange:)
//  12. VoiceOver：每个链接单独作为无障碍元素
//  13. 字号自适应：adjustsFontSizeToFitWidth + minimumScaleFactor（单行按宽度、多行按行数 / 高度）
//

import UIKit
import ZLRichLabel

final class AttributedLabelDemoPage: UIViewController, ZLAttributedLabelDelegate {

    private let stack = UIStackView()
    /// 顶部事件记录
    private let eventLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ZLAttributedLabel"
        view.backgroundColor = UIColor(hex: 0xFEF7FF)
        setupLayout()

        demoPlainText()
        demoAttributes()
        demoInsetsAndAlignment()
        demoTruncation()
        demoLinks()
        demoDataDetector()
        demoLongPress()
        demoExtendedTouchArea()
        demoInactiveLinks()
        demoHighlighted()
        demoGeometry()
        demoAccessibility()
        demoAdjustsFontSize()
    }

    // MARK: - 布局

    private func setupLayout() {
        eventLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        eventLabel.numberOfLines = 0
        eventLabel.text = "点击 / 长按链接，这里显示回调"
        eventLabel.backgroundColor = UIColor(hex: 0xF3EDF7)
        eventLabel.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(eventLabel)
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            eventLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            eventLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            eventLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            eventLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            scroll.topAnchor.constraint(equalTo: eventLabel.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    /// 添加一个用例卡片：标题、说明、内容
    private func addCard(_ title: String, _ detail: String, _ views: [UIView]) {
        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 12
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.08
        card.layer.shadowRadius = 4
        card.layer.shadowOffset = CGSize(width: 0, height: 1)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.numberOfLines = 0
        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = UIColor(white: 0, alpha: 0.5)
        detailLabel.numberOfLines = 0

        let content = UIStackView(arrangedSubviews: [titleLabel, detailLabel] + views)
        content.axis = .vertical
        content.spacing = 8
        content.setCustomSpacing(12, after: detailLabel)
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
        ])
        stack.addArrangedSubview(card)
    }

    private func makeLabel(lines: Int = 0) -> ZLAttributedLabel {
        let label = ZLAttributedLabel()
        label.numberOfLines = lines
        label.font = .systemFont(ofSize: 15)
        label.textColor = UIColor(white: 0.13, alpha: 1)
        label.delegate = self
        return label
    }

    private func segmented(_ items: [String], selected: Int, onChange: @escaping (Int) -> Void) -> UISegmentedControl {
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = selected
        control.addAction(UIAction { _ in onChange(control.selectedSegmentIndex) }, for: .valueChanged)
        return control
    }

    private func button(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func log(_ text: String) {
        eventLabel.text = " " + text
        print("[ZLAttributedLabel] \(text)")
    }

    private func relayout() {
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    // MARK: - 1. 纯文本

    private func demoPlainText() {
        let label = makeLabel()
        label.text = "通过 text 设置纯文本：使用 label 的 font、textColor、textAlignment、lineBreakMode。"
            + "之后修改这些属性，文字会自动按新属性重新生成。"
        let fonts = segmented(["15", "18 粗体", "13"], selected: 0) { [weak self] index in
            label.font = [UIFont.systemFont(ofSize: 15), .boldSystemFont(ofSize: 18), .systemFont(ofSize: 13)][index]
            self?.relayout()
        }
        let colors = segmented(["深灰", "紫色", "橙色"], selected: 0) { index in
            label.textColor = [UIColor(white: 0.13, alpha: 1), .mDeepPurple, .mDeepOrange][index]
        }
        let alignments = segmented(["左", "中", "右"], selected: 0) { index in
            label.textAlignment = [.left, .center, .right][index]
        }
        addCard("1. 纯文本 text", "label.text = \"...\"；修改 font / textColor / textAlignment 后自动更新",
                [fonts, colors, alignments, label])
    }

    // MARK: - 2. 富文本属性

    private func demoAttributes() {
        let text = NSMutableAttributedString()
        func add(_ string: String, _ attrs: [NSAttributedString.Key: Any] = [:]) {
            text.append(NSAttributedString(string: string, attributes: attrs))
        }
        add("颜色", [.foregroundColor: UIColor.mPink])
        add("、")
        add("粗体", [.font: UIFont.boldSystemFont(ofSize: 15)])
        add("、")
        add("大字号", [.font: UIFont.systemFont(ofSize: 22)])
        add("、")
        add("下划线", [.underlineStyle: NSUnderlineStyle.single.rawValue])
        add("、")
        add("背景色", [.backgroundColor: UIColor.mAmber.withAlphaComponent(0.4)])
        add("、")
        add("删除线", [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
        add("、")
        add("红色双删除线", [.strikethroughStyle: NSUnderlineStyle.double.rawValue, .strikethroughColor: UIColor.mRed])
        add("、")
        add("字间距 kern", [.kern: 4])
        add("、")
        add("阴影", [.foregroundColor: UIColor.mBlue])
        add("（label.shadowColor 作用于整段）。\n第二段：段落样式设置了行距 8、首行缩进 30，长文字折行后可以看到行距效果，未设置字体颜色的部分使用 label 的 font / textColor。")

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 8
        paragraph.firstLineHeadIndent = 30
        let secondParagraph = (text.string as NSString).range(of: "第二段")
        text.addAttribute(.paragraphStyle, value: paragraph,
                          range: NSRange(location: secondParagraph.location, length: text.length - secondParagraph.location))

        let label = makeLabel()
        label.attributedText = text
        label.shadowColor = UIColor(white: 0, alpha: 0.25)
        label.shadowOffset = CGSize(width: 0, height: 1)
        label.shadowRadius = 2
        addCard("2. 富文本属性 attributedText",
                "CoreText 不绘制的 .backgroundColor、.strikethroughStyle / .strikethroughColor 由 label 补充绘制；"
                    + "shadowColor / shadowOffset / shadowRadius 为整段阴影",
                [label])
    }

    // MARK: - 3. 内边距 + 垂直对齐

    private func demoInsetsAndAlignment() {
        let label = makeLabel()
        label.text = "textInsets 内边距：背景铺满整个 label，文字在内边距以内排版。label 固定高度 120，verticalAlignment 决定文字在垂直方向的位置。"
        label.backgroundColor = UIColor(hex: 0xEADDFF)
        label.layer.cornerRadius = 12
        label.layer.masksToBounds = true
        label.textInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        label.verticalAlignment = .top
        label.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let insets: [UIEdgeInsets] = [.zero, UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16),
                                      UIEdgeInsets(top: 24, left: 32, bottom: 24, right: 32)]
        let insetControl = segmented(["0", "12 / 16", "24 / 32"], selected: 1) { index in label.textInsets = insets[index] }
        let alignControl = segmented(["top", "center", "bottom"], selected: 0) { index in
            label.verticalAlignment = [.top, .center, .bottom][index]
        }
        addCard("3. 内边距 textInsets + 垂直对齐 verticalAlignment",
                "sizeThatFits / intrinsicContentSize 包含内边距；点击、截断、字符定位都按内边距偏移",
                [insetControl, alignControl, label])
    }

    // MARK: - 4. 行数与截断

    private func demoTruncation() {
        let long = "numberOfLines 限制行数，超出时按 lineBreakMode 截断最后一行：尾部（默认）、头部或中间。"
            + "attributedTruncationToken 可以自定义截断符，例如「…更多」。这段文字足够长，会被截断。"
        let label = makeLabel(lines: 2)
        label.lineBreakMode = .byTruncatingTail
        label.text = long

        let lineControl = segmented(["1 行", "2 行", "不限"], selected: 1) { [weak self] index in
            label.numberOfLines = [1, 2, 0][index]
            self?.relayout()
        }
        let modeControl = segmented(["尾部", "头部", "中间"], selected: 0) { index in
            label.lineBreakMode = [.byTruncatingTail, .byTruncatingHead, .byTruncatingMiddle][index]
        }
        let tokenControl = segmented(["…", "…更多"], selected: 0) { index in
            label.attributedTruncationToken = index == 0 ? nil : NSAttributedString(
                string: "…更多", attributes: [.foregroundColor: UIColor.mBlue, .font: UIFont.systemFont(ofSize: 15)])
        }
        addCard("4. 行数与截断", "多行时只截断最后一行（固定为尾部截断）；单行时头 / 中 / 尾都可用",
                [lineControl, modeControl, tokenControl, label])
    }

    // MARK: - 5. 链接

    private func demoLinks() {
        let string = "1) .link 属性：Apple 官网。2) addLink(to:range:)：GitHub。"
            + "3) addLink(range:onTap:)：点我计数。4) 自定义样式的 ZLLabelLink：橙色胶囊，按下变深。"
        let text = NSMutableAttributedString(string: string)
        let ns = string as NSString
        text.addAttribute(.link, value: URL(string: "https://www.apple.com")!, range: ns.range(of: "Apple 官网"))

        let label = makeLabel()
        // 默认链接样式 / 按下样式
        label.linkAttributes = [.foregroundColor: UIColor.mBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
        label.activeLinkAttributes = [.foregroundColor: UIColor.mBlue.withAlphaComponent(0.4)]
        label.attributedText = text   // .link 属性自动成为链接

        label.addLink(to: URL(string: "https://github.com/FPJack/ZLRichLabel")!, range: ns.range(of: "GitHub"))

        var count = 0
        label.addLink(range: ns.range(of: "点我计数")) { [weak self] _, _ in
            count += 1
            self?.log("addLink(range:onTap:) 点击第 \(count) 次")
        }

        let custom = ZLLabelLink(range: ns.range(of: "橙色胶囊"),
                                 attributes: [.foregroundColor: UIColor.white,
                                              .backgroundColor: UIColor.mDeepOrange],
                                 activeAttributes: [.backgroundColor: UIColor(hex: 0xBF360C)])
        custom.onTap = { [weak self] _, link in self?.log("自定义 ZLLabelLink 点击，range = \(link.range)") }
        label.addLink(custom)

        addCard("5. 链接", "URL 链接回调 delegate 的 didSelectLinkWith url；设置了 onTap 的链接只回调 onTap。"
                    + "links 中后添加的优先响应", [label])
    }

    // MARK: - 6. 自动识别

    private func demoDataDetector() {
        let label = makeLabel()
        label.enabledTextCheckingTypes = NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.date.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue
        label.linkAttributes = [.foregroundColor: UIColor.mTeal, .underlineStyle: NSUnderlineStyle.single.rawValue]
        label.text = "网址 https://developer.apple.com，电话 010-12345678，日期 2026年10月1日 下午3点，"
            + "地址 1 Infinite Loop, Cupertino, CA 95014。"
        addCard("6. 自动识别 enabledTextCheckingTypes",
                "NSDataDetector 识别网址 / 电话 / 日期 / 地址，点击回调 delegate 的 didSelect link（link.result 为识别结果）",
                [label])
    }

    // MARK: - 7. 长按

    private func demoLongPress() {
        let string = "长按 这个链接 触发 onLongPress；长按 另一个链接 回调 delegate 的 didLongPress。轻点仍然是点击。"
        let ns = string as NSString
        let label = makeLabel()
        label.text = string
        let first = label.addLink(range: ns.range(of: "这个链接")) { [weak self] _, _ in self?.log("点击「这个链接」") }
        first.onLongPress = { [weak self] _, _ in self?.log("onLongPress：长按「这个链接」") }
        // 第二个链接没有设置 onLongPress：长按回调 delegate 的 didLongPress
        label.addLink(range: ns.range(of: "另一个链接")) { [weak self] _, _ in self?.log("点击「另一个链接」") }
        label.longPressGestureRecognizer.minimumPressDuration = 0.4
        addCard("7. 长按链接", "longPressGestureRecognizer 只在按在链接上时开始，可调整 minimumPressDuration", [label])
    }

    // MARK: - 8. 扩大点击热区

    private func demoExtendedTouchArea() {
        let label = makeLabel()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 14
        let string = "行距较大时，按在两行之间的空白处不容易点中链接。打开 extendsLinkTouchArea 后，"
            + "手指没有按在文字上时会向四周最多 15pt 查找 链接 ；按在普通文字上仍然只认这个字。"
        label.attributedText = NSAttributedString(string: string, attributes: [.paragraphStyle: paragraph])
        label.addLink(range: (string as NSString).range(of: "链接 ；")) { [weak self] _, _ in self?.log("点中了小链接") }
        let toggle = UISwitch()
        toggle.addAction(UIAction { [weak self] _ in
            label.extendsLinkTouchArea = toggle.isOn
            self?.log("extendsLinkTouchArea = \(toggle.isOn)")
        }, for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [UILabel.small("extendsLinkTouchArea"), toggle])
        row.alignment = .center
        addCard("8. 扩大点击热区 extendsLinkTouchArea", "默认关闭；开启后点击小链接上下的空白也能命中", [row, label])
    }

    // MARK: - 9. 失活样式

    private func demoInactiveLinks() {
        let string = "弹出 alert / action sheet 时 tintAdjustmentMode 变为 dimmed，链接 显示为 inactiveLinkAttributes（灰色）。"
        let label = makeLabel()
        label.text = string
        label.inactiveLinkAttributes = [.foregroundColor: UIColor.systemGray, .underlineStyle: 0]
        label.addLink(range: (string as NSString).range(of: "链接")) { [weak self] _, _ in self?.log("点击失活示例链接") }
        let show = button("弹出 alert 查看失活样式") { [weak self] in
            let alert = UIAlertController(title: "链接变灰了吗？", message: "关闭后恢复", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
            self?.present(alert, animated: true)
        }
        addCard("9. 失活样式 inactiveLinkAttributes", "为 nil 或空时失活不改变样式；单个链接可用 ZLLabelLink.inactiveAttributes",
                [show, label])
    }

    // MARK: - 10. 高亮

    private func demoHighlighted() {
        let label = makeLabel()
        label.attributedText = NSAttributedString(
            string: "isHighlighted = true 时，全部文字使用 highlightedTextColor（例如 cell 选中时）。",
            attributes: [.foregroundColor: UIColor.mIndigo])
        label.highlightedTextColor = .white
        label.backgroundColor = .clear
        let container = UIView()
        container.layer.cornerRadius = 8
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
        ])
        let toggle = UISwitch()
        toggle.addAction(UIAction { _ in
            label.isHighlighted = toggle.isOn
            container.backgroundColor = toggle.isOn ? .mIndigo : .clear
        }, for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [UILabel.small("isHighlighted"), toggle])
        row.alignment = .center
        addCard("10. 高亮 highlightedTextColor", "与 UILabel 行为一致", [row, container])
    }

    // MARK: - 11. 尺寸与定位

    private var geometryLabel: ZLAttributedLabel?
    private let markerLayer = CAShapeLayer()

    private func demoGeometry() {
        let string = "点击任意文字：characterIndex(at:) 得到字符下标，boundingRect(forCharacterRange:) 框出这个字所在的词。"
            + "Frame 布局时用 sizeThatFits 计算高度。"
        let label = makeLabel()
        label.text = string
        label.textInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        label.layer.borderColor = UIColor(white: 0, alpha: 0.1).cgColor
        label.layer.borderWidth = 1
        markerLayer.fillColor = UIColor.mAmber.withAlphaComponent(0.3).cgColor
        markerLayer.strokeColor = UIColor.mDeepOrange.cgColor
        markerLayer.lineWidth = 1
        label.layer.addSublayer(markerLayer)
        let tap = UITapGestureRecognizer(target: self, action: #selector(geometryTapped(_:)))
        label.addGestureRecognizer(tap)
        geometryLabel = label

        // Frame 布局：sizeThatFits
        let frameLabel = makeLabel()
        frameLabel.text = "这个 label 没有使用 Auto Layout，高度由 sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)) 计算。"
        frameLabel.backgroundColor = UIColor(hex: 0xF3EDF7)
        frameLabel.textInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let frameHost = FrameHostView(label: frameLabel)

        addCard("11. 尺寸与定位", "sizeThatFits / intrinsicContentSize 按「宽度 + 行数」缓存", [label, frameHost])
    }

    @objc private func geometryTapped(_ gesture: UITapGestureRecognizer) {
        guard let label = geometryLabel, let text = label.attributedText else { return }
        let point = gesture.location(in: label)
        let index = label.characterIndex(at: point)
        guard index != NSNotFound else {
            markerLayer.path = nil
            log("characterIndex = NSNotFound（没有按在文字上）")
            return
        }
        // 取这个字所在的词
        var wordRange = NSRange(location: index, length: 1)
        (text.string as NSString).enumerateSubstrings(in: NSRange(location: 0, length: text.length),
                                                      options: .byWords) { _, range, _, stop in
            if NSLocationInRange(index, range) { wordRange = range; stop.pointee = true }
        }
        let rect = label.boundingRect(forCharacterRange: wordRange)
        markerLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 3).cgPath
        let word = (text.string as NSString).substring(with: wordRange)
        log("characterIndex = \(index)，词「\(word)」rect = \(NSCoder.string(for: rect.integral))")
    }

    // MARK: - 12. 无障碍

    private func demoAccessibility() {
        let string = "开启 VoiceOver 后，这段文字是一个元素，用户协议 和 隐私政策 分别是可以单独聚焦、双击触发的链接。"
        let ns = string as NSString
        let label = makeLabel()
        label.text = string
        label.addLink(range: ns.range(of: "用户协议")) { [weak self] _, _ in self?.log("打开用户协议") }
        let privacy = label.addLink(range: ns.range(of: "隐私政策")) { [weak self] _, _ in self?.log("打开隐私政策") }
        privacy.accessibilityHintText = "打开隐私政策页面"
        let inspect = button("打印 accessibilityElements") { [weak self] in
            let elements = (label.accessibilityElements ?? []).compactMap { $0 as? UIAccessibilityElement }
            let names = elements.map { "\($0.accessibilityLabel ?? "")\($0.accessibilityTraits.contains(.link) ? "（链接）" : "")" }
            self?.log("\(elements.count) 个元素：" + names.joined(separator: " | "))
        }
        addCard("12. VoiceOver", "有链接时 label 作为容器：整段文字 + 每个链接；ZLLabelLink.accessibilityHintText 为附加说明",
                [inspect, label])
    }

    // MARK: - 13. 字号自适应

    private func demoAdjustsFontSize() {
        // 单行：宽度不够时缩小，带链接验证缩小后点击位置正确
        let single = makeLabel(lines: 1)
        let singleString = "单行标题：宽度不够时整体缩小字号，链接 仍可点击"
        single.text = singleString
        single.font = .boldSystemFont(ofSize: 22)
        single.adjustsFontSizeToFitWidth = true
        single.minimumScaleFactor = 0.5
        single.backgroundColor = UIColor(hex: 0xF3EDF7)
        single.addLink(range: (singleString as NSString).range(of: "链接")) { [weak self] label, _ in
            self?.log("缩小后点击链接，scale = \(String(format: "%.2f", label.currentFontScaleFactor))")
        }

        // 多行：限制 2 行，放不下时缩小
        let multi = makeLabel(lines: 2)
        multi.text = "多行（numberOfLines = 2）：超过 2 行时缩小字号，尽量在 2 行内显示完整；"
            + "缩到 minimumScaleFactor 仍放不下时按尾部截断。这段文字比较长，用来观察缩放效果。"
        multi.font = .systemFont(ofSize: 18)
        multi.adjustsFontSizeToFitWidth = true
        multi.minimumScaleFactor = 0.5
        multi.backgroundColor = UIColor(hex: 0xF3EDF7)

        // 不限行数 + 固定高度：按高度缩小
        let fixed = makeLabel(lines: 0)
        fixed.text = "不限行数（numberOfLines = 0）+ 固定高度 60：文字高度超过 label 高度时缩小字号。"
            + "富文本中的各段字体按同一比例缩小。"
        fixed.font = .systemFont(ofSize: 18)
        fixed.verticalAlignment = .top
        fixed.adjustsFontSizeToFitWidth = true
        fixed.minimumScaleFactor = 0.4
        fixed.backgroundColor = UIColor(hex: 0xF3EDF7)
        fixed.heightAnchor.constraint(equalToConstant: 60).isActive = true

        let labels = [single, multi, fixed]
        let info = UILabel.small("")
        info.numberOfLines = 0
        let refreshInfo: () -> Void = { [weak self, weak info] in
            self?.view.layoutIfNeeded()
            info?.text = labels.enumerated().map { index, label in
                "label\(index + 1): adjusts = \(label.adjustsFontSizeToFitWidth), "
                    + "min = \(String(format: "%.1f", label.minimumScaleFactor)), scale = \(String(format: "%.2f", label.currentFontScaleFactor))"
            }.joined(separator: "\n")
            print("[ZLAttributedLabel] 13.\n\(info?.text ?? "")")
        }

        // 宽度：通过左右间距改变 label 宽度
        let container = UIStackView(arrangedSubviews: labels)
        container.axis = .vertical
        container.spacing = 8
        container.isLayoutMarginsRelativeArrangement = true
        let widths: [CGFloat] = [0, 40, 80]
        let widthControl = segmented(["宽", "中", "窄"], selected: 0) { [weak self] index in
            container.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: widths[index])
            self?.relayout()
            refreshInfo()
        }
        let toggle = UISwitch()
        toggle.isOn = true
        toggle.addAction(UIAction { _ in
            labels.forEach { $0.adjustsFontSizeToFitWidth = toggle.isOn }
            refreshInfo()
        }, for: .valueChanged)
        let toggleRow = UIStackView(arrangedSubviews: [UILabel.small("adjustsFontSizeToFitWidth"), toggle])
        toggleRow.alignment = .center
        let minimums: [CGFloat] = [0.3, 0.5, 0.8, 0]
        let minControl = segmented(["min 0.3", "0.5", "0.8", "0(不缩)"], selected: 1) { index in
            labels.forEach { $0.minimumScaleFactor = minimums[index] }
            refreshInfo()
        }
        addCard("13. 字号自适应 adjustsFontSizeToFitWidth",
                "单行按宽度、多行按行数与高度缩小字体，最小到 minimumScaleFactor（为 0 时不缩小，与 UILabel 相同）；"
                    + "sizeThatFits 仍按原字号计算。切换宽度 / 开关 / 最小比例观察 scale",
                [widthControl, toggleRow, minControl, container, info])
        DispatchQueue.main.async { refreshInfo() }
    }

    // MARK: - ZLAttributedLabelDelegate

    func attributedLabel(_ label: ZLAttributedLabel, didSelectLinkWith url: URL) {
        log("delegate didSelectLinkWith url: \(url.absoluteString)")
    }

    func attributedLabel(_ label: ZLAttributedLabel, didSelect link: ZLLabelLink) {
        let text = (label.attributedText?.string as NSString?)?.substring(with: link.range) ?? ""
        let type: String
        switch link.result?.resultType {
        case .phoneNumber?: type = "电话 \(link.result?.phoneNumber ?? "")"
        case .date?: type = "日期 \(link.result?.date.map { "\($0)" } ?? "")"
        case .address?: type = "地址"
        default: type = "链接"
        }
        log("delegate didSelect：\(type)「\(text)」")
    }

    func attributedLabel(_ label: ZLAttributedLabel, didLongPress link: ZLLabelLink, at point: CGPoint) {
        let text = (label.attributedText?.string as NSString?)?.substring(with: link.range) ?? ""
        log("delegate didLongPress「\(text)」at \(NSCoder.string(for: point))")
    }
}

// MARK: - 辅助

/// Frame 布局示例：layoutSubviews 中用 sizeThatFits 计算 label 高度
private final class FrameHostView: UIView {
    let label: ZLAttributedLabel

    init(label: ZLAttributedLabel) {
        self.label = label
        super.init(frame: .zero)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = label.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height
        label.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        if lastHeight != height {
            lastHeight = height
            invalidateIntrinsicContentSize()
        }
    }

    private var lastHeight: CGFloat = 0

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: lastHeight)
    }
}

private extension UILabel {
    static func small(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        return label
    }
}
