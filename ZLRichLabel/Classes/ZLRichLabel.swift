//
//  ZLRichLabel.swift
//  ZLRichLabel
//
//  富文本基类（基于 ZLAttributedLabel）：
//  - 基于正则规则（`ZLRichRule`）解析文本，重叠时按优先级取舍
//  - 命中内容交给规则 handler 渲染（样式 / 替换文字 / 图片 / 自定义 View / 点击 / 按下高亮）
//  - 负责渲染、内嵌 View 布局、截断、Auto Layout 自适应高度、RTL
//
//  子类通过重写 `builtInRules` 提供内置规则，例如 `ZLTagRichLabel` 的 `<h>` 标签。
//

import UIKit
import CoreText

// MARK: - 解析片段

/// 解析结果片段：普通文本（`match` 为 nil）或规则命中（`match` 不为 nil）
@objcMembers
public final class ZLRichSegment: NSObject {
    /// 原始文字
    public let text: String
    /// 规则命中，普通文本为 nil
    public let match: ZLRichMatch?

    public init(text: String, match: ZLRichMatch?) {
        self.text = text
        self.match = match
        super.init()
    }

    public var isRuleMatch: Bool { return match != nil }
}

// MARK: - 组件

/// 基于正则规则的富文本基类
///
/// ```swift
/// let label = ZLRichLabel(frame: .zero)
/// label.numberOfLines = 0
/// label.style = [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.gray]
/// try? label.addRule(name: "mention", pattern: "@\\w+", priority: 10) { ctx in
///     ctx.addAttributes([.foregroundColor: UIColor.purple])
///     ctx.onTap = { match in print("@", match.text) }
/// }
/// label.text = "hello @alice"
/// ```
/// 长按 / 双击的位置信息
@objcMembers
public final class ZLRichGestureInfo: NSObject {
    /// 手势位置（label 坐标系）
    public let location: CGPoint
    /// 手势位置对应的字符下标（展示文字中），不在文字上时为 `NSNotFound`
    public let characterIndex: Int
    /// 手势位置所在的规则命中，不在命中上时为 nil
    public let match: ZLRichMatch?
    /// 命中在 label 上展示的文字（规则可能替换过文字），不在命中上时为 nil
    public let matchDisplayText: String?
    /// 原始字符串（`rawText`）
    public let rawText: String
    /// 展示文字（渲染后的文字，自定义 View / 图片为占位符 U+FFFC）
    public let displayText: String

    init(location: CGPoint, characterIndex: Int, match: ZLRichMatch?, matchDisplayText: String?,
         rawText: String, displayText: String) {
        self.location = location
        self.characterIndex = characterIndex
        self.match = match
        self.matchDisplayText = matchDisplayText
        self.rawText = rawText
        self.displayText = displayText
        super.init()
    }

    public override var description: String {
        return "ZLRichGestureInfo(location: \(location), characterIndex: \(characterIndex), "
            + "match: \(match?.description ?? "nil"), matchDisplayText: \(matchDisplayText ?? "nil"))"
    }
}

/// 渲染 / 排版统计，用于观察缓存效果（调试用，数值只增不减，可调用 `reset()` 清零）
@objcMembers
public final class ZLRichLabelStatistics: NSObject {
    /// 渲染次数（拼装富文本并交给 ZLAttributedLabel 绘制）
    public internal(set) var renders = 0
    /// 执行规则 handler 的次数（未命中渲染缓存）
    public internal(set) var handlerCalls = 0
    /// 直接复用缓存渲染结果的命中数（没有执行 handler，也没有重建 View）
    public internal(set) var reusedMatches = 0
    /// 创建 CTFramesetter 的次数（每份新的 attributedText 一次）
    public internal(set) var framesetterCreations = 0
    /// `sizeThatFits` / `intrinsicContentSize` 命中缓存的次数
    public internal(set) var sizeCacheHits = 0

    public func reset() {
        renders = 0
        handlerCalls = 0
        reusedMatches = 0
        framesetterCreations = 0
        sizeCacheHits = 0
    }

    public override var description: String {
        return "renders: \(renders), handlerCalls: \(handlerCalls), reusedMatches: \(reusedMatches), "
            + "framesetterCreations: \(framesetterCreations), sizeCacheHits: \(sizeCacheHits)"
    }
}

@objcMembers
open class ZLRichLabel: ZLAttributedLabel {

    /// 原始文本（与直接设置 `text = "..."` 等价），按规则解析后渲染
    open var rawText: String = "" {
        didSet {
            guard !isPassingThrough, rawText != oldValue else { return }
            setNeedsReparse()
        }
    }

    /// 设置 `text`：按规则解析并渲染（等同于设置 `rawText`），xib / storyboard 中设置的文字同样会被解析；`nil` 清空。
    ///
    /// 读取 `text` 得到的是渲染后的展示文字；原始字符串请读 `rawText`
    open override var text: String? {
        get { return super.text }
        set {
            if let string = newValue {
                rawText = string
            } else if rawText.isEmpty {
                // rawText 已为空时 didSet 不会触发，需要手动刷新
                segments = []
                didParse()
                rebuild()
            } else {
                rawText = ""
            }
        }
    }

    /// 设置 `attributedText`：不解析，按 ZLAttributedLabel 原有逻辑直接展示；`nil` 清空
    open override var attributedText: NSAttributedString? {
        get { return super.attributedText }
        set {
            // rebuild() 内部设置渲染结果时直接交给 ZLAttributedLabel
            if isRebuilding {
                super.attributedText = newValue
                return
            }
            guard let attributed = newValue else {
                text = nil
                return
            }
            // 外部直接传富文本：清空解析状态，按普通 ZLAttributedLabel 处理
            isPassingThrough = true
            rawText = ""
            segments = []
            isPassingThrough = false
            didParse()
            removeAttachmentViews()
            super.attributedText = attributed
        }
    }

    private var isPassingThrough = false

    /// 普通文本样式（未设置 font / foregroundColor 时使用 label 的 font / textColor）
    open var style: ZLTextStyle = [:] { didSet { setNeedsRebuild() } }

    /// 可点击内容按下时的默认高亮样式（为空则不高亮），规则可通过 `context.highlightStyle` 单独指定
    open var highlightStyle: ZLTextStyle = [:] { didSet { setNeedsRender() } }

    /// 截断时使用的省略符，nil 时使用 "…"（带普通文本样式）
    open var truncationToken: NSAttributedString? { didSet { setNeedsRender() } }

    // MARK: 展开 / 收起

    /// 「展开」按钮，例如 `"… 全文"`。设置后，内容超过 `numberOfLines` 行被截断时，
    /// 用它代替省略符显示在最后一行末尾，点击后展开全部内容。
    /// 没有设置的属性（字体、颜色等）使用普通文本样式。为 nil（默认）时不支持展开
    open var expandToken: NSAttributedString? { didSet { setNeedsRender() } }

    /// 「收起」按钮，例如 `" 收起"`。展开后拼接在内容末尾，点击后恢复为 `numberOfLines` 行。为 nil 时展开后不能收起
    open var collapseToken: NSAttributedString? { didSet { setNeedsRender() } }

    /// 是否已展开。展开时显示全部内容（`numberOfLines` 读取为 0），收起时按设置的行数截断。
    /// 直接设置不会回调 `onExpandChanged`；列表中复用 cell 时按数据设置即可
    open var isExpanded: Bool = false {
        didSet {
            guard isExpanded != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsRender()
        }
    }

    /// 点击「展开 / 收起」后回调，参数为新的展开状态。
    /// 列表中可在这里记录状态并刷新行高（例如 `tableView.performBatchUpdates(nil)`）
    open var onExpandChanged: ((Bool) -> Void)?

    /// 点击「展开 / 收起」按钮的外部处理，参数为 label 和这次点击想要的状态（点「展开」为 true，点「收起」为 false）。
    /// - 为 nil（默认）：内部自动切换展开状态并回调 `onExpandChanged`
    /// - 设置后：只回调这里，不自动切换（也不回调 `onExpandChanged`），由外部决定，例如：
    ///   跳转详情页、先请求完整内容，或者设置 `isExpanded` / 调用 `toggleExpanded()` 按默认方式切换
    open var onExpandTokenTap: ((_ label: ZLRichLabel, _ wantsExpand: Bool) -> Void)?

    /// 超过多少行才折叠，默认 0（等于 `numberOfLines`：超过 `numberOfLines` 行就折叠）。
    /// 例如 `numberOfLines = 3`、`collapseThreshold = 5`：内容不超过 5 行时完整显示（没有「展开」按钮），
    /// 超过 5 行时才折叠为 3 行并显示「展开」。小于等于 `numberOfLines` 时不生效。按当前宽度计算行数
    open var collapseThreshold: Int = 0 {
        didSet {
            guard collapseThreshold != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// 当前内容是否被截断（最近一次布局的结果）
    public internal(set) var isTruncated: Bool = false

    /// 「展开」按钮的可点击区域（label 坐标系，已适当扩大），没有显示时为 `.zero`
    public internal(set) var expandTokenRect: CGRect = .zero

    // MARK: 长按 / 双击

    /// 长按回调（例如弹出「复制 / 举报」菜单）。长按位置所在的命中设置了 `ctx.onLongPress` 时只回调后者。
    /// 长按会取消按下高亮和点击，不会同时触发 `onTap`
    open var onLongPress: ((ZLRichGestureInfo) -> Void)?

    /// 双击回调。设置后单击链接要等双击判定失败才触发（约 0.3 秒延迟），不需要时请保持为 nil
    open var onDoubleTap: ((ZLRichGestureInfo) -> Void)? {
        didSet { updateDoubleTapGesture() }
    }

    /// 长按手势（可调整 `minimumPressDuration` 等）
    public private(set) lazy var richLongPressGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleRichLongPress(_:)))
        gesture.minimumPressDuration = 0.5
        gesture.delegate = gestureDelegate
        return gesture
    }()

    /// 双击手势，`onDoubleTap` 为 nil 时为 nil
    public internal(set) var richDoubleTapGesture: UITapGestureRecognizer?

    // MARK: 选中复制（实现见 ZLRichLabel+Selection.swift）

    /// 是否可以选中复制，默认 false。开启后长按文字选中一个词（命中则选中整个命中），
    /// 拖动手指或两端的拖柄调整范围，松手后弹出「复制 / 复制原文 / 全选」菜单。
    /// 开启后长按普通文字用于选中，不再回调 `onLongPress`（命中自己的 `ctx.onLongPress` 仍然优先）
    open var isSelectable: Bool = false {
        didSet { if !isSelectable { clearSelection() } }
    }

    /// 当前选中范围（展示文字中），没有选中时 `location` 为 `NSNotFound`
    public internal(set) var selectedRange = NSRange(location: NSNotFound, length: 0)

    /// 选中背景色，nil 时使用 `tintColor` 的 25% 透明度
    open var selectionColor: UIColor? { didSet { updateSelectionAppearance() } }

    /// 选中范围变化（包括清除，此时 `location` 为 `NSNotFound`）
    open var onSelectionChanged: ((NSRange) -> Void)?

    /// 通过菜单复制后回调：复制的文字，以及是否为原文
    open var onCopy: ((_ text: String, _ isRawText: Bool) -> Void)?

    /// 菜单标题
    open var copyMenuTitle = "复制"
    open var copyRawMenuTitle = "复制原文"
    open var selectAllMenuTitle = "全选"

    /// 展示文字与原文的对应关系（render 时生成）
    var displayPieces: [ZLDisplayPiece] = []
    /// 展示文字中属于正文的长度（不含展开后拼接的「收起」）
    var contentDisplayLength = 0
    /// 当前内容是否包含胶囊背景 / 渐变文字（见 ZLRichLabel+Decoration.swift）
    var hasTextBackgrounds = false
    var hasTextGradients = false

    open override func drawText(in rect: CGRect) {
        drawDecoratedText(in: rect) { super.drawText(in: $0) }
    }
    /// 长按开始时选中的范围（拖动时以它为锚点扩展）
    var selectionAnchor: NSRange?
    /// 正在拖动拖柄（期间菜单隐藏，不清除选中）
    var isAdjustingSelection = false
    /// 菜单关闭后需要重新弹出（例如点了「全选」）
    var reshowsSelectionMenu = false
    lazy var selectionLayer = CAShapeLayer()
    var selectionHandles: [ZLSelectionHandleView] = []
    /// iOS 16+ 的 UIEditMenuInteraction 封装
    var selectionEditMenu: AnyObject?
    var menuHideObserver: NSObjectProtocol?

    // MARK: 规则

    /// 外部添加的规则（命中内容交给规则 handler 处理），重叠时按优先级取舍，见 `ZLRichRule`
    open var rules: [ZLRichRule] = [] { didSet { setNeedsReparse() } }

    /// 子类内置规则（默认为空）。同优先级时排在 `rules` 之前。
    /// 内置规则的配置变化后，子类需要调用 `setNeedsReparse()`
    open var builtInRules: [ZLRichRule] { return [] }

    /// 实际参与解析的所有规则：`builtInRules + rules`
    public var allRules: [ZLRichRule] { return builtInRules + rules }

    /// 添加规则（同名规则会被替换）
    open func addRule(_ rule: ZLRichRule) {
        if let i = rules.firstIndex(where: { $0.name == rule.name }) {
            rules[i] = rule
        } else {
            rules.append(rule)
        }
    }

    /// 便捷添加规则：正则非法时抛出错误
    open func addRule(name: String, pattern: String, options: NSRegularExpression.Options = [], priority: Int = 0,
                      handler: @escaping (ZLRichRuleContext) -> Void) throws {
        addRule(try ZLRichRule(name: name, pattern: pattern, options: options, priority: priority, handler: handler))
    }

    /// 按名称移除规则（Objective-C：`[label removeRuleNamed:@"mention"]`）
    @objc(removeRuleNamed:)
    open func removeRule(named name: String) {
        rules.removeAll { $0.name == name }
    }

    /// 移除所有外部添加的规则（不影响 `builtInRules`）
    open func removeAllRules() {
        rules.removeAll()
    }

    /// 当前解析出的片段
    public private(set) var segments: [ZLRichSegment] = []

    /// 当前所有生效的规则命中（含内置规则），按位置排序
    public var matches: [ZLRichMatch] { return segments.compactMap { $0.match } }

    // MARK: Private

    static let attachmentKey = NSAttributedString.Key("ZLRichLabelAttachmentID")
    static let attachmentChar: unichar = 0xFFFC

    final class Attachment {
        let id: Int
        let view: UIView
        let alignment: ZLRichWidgetAlignment
        /// 所在位置的字体（用于按对齐方式计算 ascent / descent）
        var font: UIFont
        /// 创建时的字体（Dynamic Type 每次渲染都从它重新缩放，避免复用时重复缩放）
        let originalFont: UIFont
        /// `ZLRichWidget.size == .zero`：尺寸由 View 自身计算，内容变化后可重新测量
        let autoSize: Bool
        /// 是否给 View 加点击（触发所在范围的 onTap）
        var tappable = true
        private(set) var size: CGSize = .zero
        private(set) var ascent: CGFloat = 0
        private(set) var descent: CGFloat = 0
        /// 最近一次布局时设置给 View 的尺寸，用于检测外部修改了 View 的尺寸
        var appliedSize: CGSize?

        init(id: Int, view: UIView, alignment: ZLRichWidgetAlignment, font: UIFont, autoSize: Bool, size: CGSize) {
            self.id = id
            self.view = view
            self.alignment = alignment
            self.font = font
            self.originalFont = font
            self.autoSize = autoSize
            update(size: size)
        }

        /// 更新尺寸并按对齐方式重新计算 ascent / descent
        func update(size: CGSize) {
            self.size = size
            let height = size.height
            switch alignment {
            case .baseline, .aboveBaseline:
                ascent = height
                descent = 0
            case .belowBaseline:
                ascent = 0
                descent = height
            case .top:
                ascent = font.ascender
                descent = height - font.ascender
            case .bottom:
                descent = -font.descender
                ascent = height - descent
            case .middle:
                let mid = (font.ascender + font.descender) / 2
                ascent = height / 2 + mid
                descent = height / 2 - mid
            }
        }
    }

    /// CTRunDelegate 的 refCon
    private final class RunMetrics {
        let ascent: CGFloat
        let descent: CGFloat
        let width: CGFloat
        init(ascent: CGFloat, descent: CGFloat, width: CGFloat) {
            self.ascent = ascent
            self.descent = descent
            self.width = width
        }
    }

    var attachments: [Int: Attachment] = [:]
    private var nextAttachmentId = 0
    private var batchUpdateDepth = 0
    private var isRebuilding = false

    /// 渲染 / 排版统计（观察缓存效果）
    public let statistics = ZLRichLabelStatistics()

    /// 单个命中的渲染结果（handler / builder 的输出 + 创建的 View），下次渲染时直接复用
    final class RenderedMatch {
        let rule: ZLRichRule
        let range: NSRange
        let index: Int
        let text: String
        let content: NSAttributedString
        let onTap: ((ZLRichMatch) -> Void)?
        let onLongPress: ((ZLRichMatch) -> Void)?
        let highlightStyle: ZLTextStyle?
        let attachments: [Attachment]
        /// 分段点击 / 长按（范围相对 content，后面的优先）
        let links: [ZLRuleLink]

        init(match: ZLRichMatch, content: NSAttributedString, onTap: ((ZLRichMatch) -> Void)?, onLongPress: ((ZLRichMatch) -> Void)?,
             highlightStyle: ZLTextStyle?, attachments: [Attachment], links: [ZLRuleLink]) {
            self.matchInfo = match
            self.rule = match.rule
            self.range = match.range
            self.index = match.index
            self.text = match.text
            self.content = content
            self.onTap = onTap
            self.onLongPress = onLongPress
            self.links = links
            self.highlightStyle = highlightStyle
            self.attachments = attachments
        }

        /// 生成这份结果的命中（复用时规则 / 位置 / 序号 / 文字都相同）
        let matchInfo: ZLRichMatch

        /// 同一条规则、同一位置、同一序号、同样的文字才能复用
        func isValid(for match: ZLRichMatch) -> Bool {
            return rule === match.rule && index == match.index && NSEqualRanges(range, match.range) && text == match.text
        }
    }

    private struct RenderKey: Hashable {
        let location: Int
        let length: Int
        let index: Int
    }

    /// 命中的渲染缓存：文本变化只重新渲染变化的命中；样式等配置变化时按范围作废
    private var renderCache: [RenderKey: RenderedMatch] = [:]

    /// 每个命中在展示文字（attributedText）中的范围，按位置排序，用于手势定位
    var displayMatches: [(range: NSRange, rendered: RenderedMatch)] = []

    /// 排版缓存在 ZLAttributedLabel 中，这里只统计
    override func didCreateFramesetter() {
        statistics.framesetterCreations += 1
    }

    override func didHitSizeCache() {
        statistics.sizeCacheHits += 1
    }

    /// 按要计算的宽度决定行数（collapseThreshold 与宽度有关，不能直接用当前 bounds 下的 numberOfLines）
    override func numberOfLines(forTextWidth width: CGFloat) -> Int {
        return effectiveNumberOfLines(forTextWidth: width)
    }

    // MARK: Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        enabledTextCheckingTypes = 0
        linkAttributes = [:]
        activeLinkAttributes = [:]
        inactiveLinkAttributes = nil
        isUserInteractionEnabled = true
        setupGestures()
        // xib / storyboard 中设置的 text 会在 super.init(coder:) 期间就被解析，
        // 此时链接样式还是默认的（蓝色下划线），这里按最终配置重新渲染一次
        if !rawText.isEmpty { rebuild() }
    }

    // MARK: 批量更新

    /// 开始批量修改：直到 `endUpdates()` 前不会重新渲染（可嵌套）
    open func beginUpdates() {
        batchUpdateDepth += 1
    }

    /// 结束批量修改，最外层结束时重新渲染一次
    open func endUpdates() {
        guard batchUpdateDepth > 0 else { return }
        batchUpdateDepth -= 1
        if batchUpdateDepth == 0 { render() }
    }

    /// Objective-C：`[label update:^(ZLRichLabel *v) { ... }]`
    /// Swift 请使用 `label.update { v in ... }`（v 为 label 的实际类型）
    @available(swift, obsoleted: 1.0)
    @objc(update:)
    public func objc_update(_ block: (ZLRichLabel) -> Void) {
        beginUpdates()
        block(self)
        endUpdates()
    }

    /// 外部设置的字体（rebuild 内部为了基线修正 / Dynamic Type 会改 `font`，不能作为下次渲染的基准）
    private var configuredFont: UIFont?

    open override var font: UIFont! {
        didSet {
            if !isRebuilding { configuredFont = font }
            setNeedsRebuild()
        }
    }

    // MARK: 深色模式 / Dynamic Type

    /// 为 true 时按系统「文字大小」设置缩放所有字体（使用 `UIFontMetrics.default`，iOS 11+），
    /// 系统字号变化时自动重新渲染。已经是 `UIFont.preferredFont(forTextStyle:)` 的字体不会重复缩放
    /// 自己存储，不交给 UILabel（UILabel 开启后会自行替换 `font`，与这里的渲染冲突）
    open override var adjustsFontForContentSizeCategory: Bool {
        get { return adjustsFontForContentSizeCategoryStorage }
        set {
            guard newValue != adjustsFontForContentSizeCategoryStorage else { return }
            adjustsFontForContentSizeCategoryStorage = newValue
            setNeedsRebuild()
        }
    }

    private var adjustsFontForContentSizeCategoryStorage = false

    /// 深色 / 浅色切换、系统字号变化时重新渲染（规则 handler / builder 会重新执行，可在其中按当前外观返回样式）
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard !rawText.isEmpty else { return }
        var changed = false
        if #available(iOS 13.0, *), traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            changed = true
        }
        if adjustsFontForContentSizeCategory,
           previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            changed = true
        }
        if changed { setNeedsRebuild() }
    }

    /// 按当前系统字号缩放字体；未开启 `adjustsFontForContentSizeCategory` 或已是 Dynamic Type 字体时原样返回
    public func scaledFont(_ font: UIFont) -> UIFont {
        guard adjustsFontForContentSizeCategory, !ZLRichLabel.isDynamicTypeFont(font) else { return font }
        if #available(iOS 11.0, *) {
            return UIFontMetrics.default.scaledFont(for: font, compatibleWith: traitCollection)
        }
        return font
    }

    /// 是否为 `UIFont.preferredFont(forTextStyle:)` 创建的字体。
    /// 注意 `systemFont(ofSize:)` 的描述符同样带 `.textStyle`（值为 `CTFontRegularUsage` 等），需要按值区分
    private static func isDynamicTypeFont(_ font: UIFont) -> Bool {
        guard let style = font.fontDescriptor.object(forKey: .textStyle) as? String else { return false }
        return style.hasPrefix("UICTFontTextStyle")
    }

    /// 缩放富文本中的所有字体，并按缩放后的字体更新自定义 View 的对齐
    private func applyContentSizeScaling(to result: NSMutableAttributedString, includesAttachments: Bool = true) {
        var cache: [UIFont: UIFont] = [:]
        let scale: (UIFont) -> UIFont = { font in
            if let scaled = cache[font] { return scaled }
            let scaled = self.scaledFont(font)
            cache[font] = scaled
            return scaled
        }
        if adjustsFontForContentSizeCategory {
            let full = NSRange(location: 0, length: result.length)
            result.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
                if let font = value as? UIFont { result.addAttribute(.font, value: scale(font), range: range) }
            }
        }
        guard includesAttachments, !attachments.isEmpty else { return }
        // 复用的 View 也要按当前设置重新计算对齐（未开启时 scale 原样返回）
        for attachment in attachments.values {
            attachment.font = scale(attachment.originalFont)
            attachment.update(size: attachment.size)
        }
        // 缓存中的占位符带的是旧尺寸的 CTRunDelegate，统一按当前尺寸替换
        replaceRunDelegates(in: result, ids: nil)
    }

    open override var textColor: UIColor! {
        didSet { setNeedsRebuild() }
    }

    // MARK: Parse

    /// 规则 / 解析配置变化后重新解析并渲染（子类内置规则变化时调用）
    public final func setNeedsReparse() {
        guard !isPassingThrough else { return }
        parse()
        setNeedsRender()
    }

    private func parse() {
        let source = rawText
        let ns = source as NSString
        var result: [ZLRichSegment] = []
        var cursor = 0
        for match in ZLRichParser.resolve(source, rules: allRules) {
            if match.range.location > cursor {
                let text = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                result.append(ZLRichSegment(text: text, match: nil))
            }
            result.append(ZLRichSegment(text: match.text, match: match))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result.append(ZLRichSegment(text: ns.substring(from: cursor), match: nil))
        }
        segments = result
        didParse()
    }

    /// 解析完成（`segments` 已更新）后调用，子类可重写以整理自己的解析结果。默认空实现
    open func didParse() {}

    // MARK: Build

    /// 配置变化后重新渲染：清空渲染缓存，所有命中重新执行 handler（批量更新中会推迟到 `endUpdates()`）
    public final func setNeedsRebuild() {
        guard !isRebuilding else { return }
        renderCache.removeAll()
        setNeedsRender()
    }

    /// 只作废某条规则的渲染缓存并重新渲染：其他规则的命中直接复用上次结果（不执行 handler、不重建 View）。
    /// 子类中只影响内置规则的配置变化时使用（例如 `ZLTagRichLabel.tagStyle`）；
    /// 外部规则 handler 依赖的数据变化后也可以调用它代替 `rebuild()`
    @objc(setNeedsRebuildForRuleNamed:)
    public final func setNeedsRebuild(forRuleNamed name: String) {
        guard !isRebuilding else { return }
        invalidateRenderCache(forRuleNamed: name)
        setNeedsRender()
    }

    /// 只作废某条规则的渲染缓存，不触发渲染（子类在 `didParse()` 中使用）
    func invalidateRenderCache(forRuleNamed name: String) {
        renderCache = renderCache.filter { $0.value.rule.name != name }
    }

    /// 重新渲染并复用缓存：用于不影响 handler 输出的配置（按下高亮、省略符）和重新解析后
    private func setNeedsRender() {
        guard batchUpdateDepth == 0, !isRebuilding else { return }
        render()
    }

    /// 普通文本样式：label 的 font / textColor + `style`
    public var resolvedBaseStyle: ZLTextStyle {
        var baseStyle: ZLTextStyle = [:]
        if let font = configuredFont ?? font { baseStyle[.font] = font }
        if let color = textColor { baseStyle[.foregroundColor] = color }
        baseStyle.merge(style) { $1 }
        return baseStyle
    }

    /// 强制重新渲染：清空渲染缓存，所有规则 handler / builder 都会重新执行。
    /// handler / builder 依赖的外部数据变化后调用；只影响某条规则时可用 `setNeedsRebuild(forRuleNamed:)`
    open func rebuild() {
        guard !isRebuilding else { return }
        renderCache.removeAll()
        render()
    }

    /// 渲染：命中的结果优先从缓存复用，只对缓存中没有的命中执行 handler
    private func render() {
        guard !isRebuilding else { return }
        isRebuilding = true
        defer { isRebuilding = false }
        statistics.renders += 1

        let baseStyle = resolvedBaseStyle
        // 绘制时用 label.font 的 descender 修正基线，保持与正文字体一致
        if let baseFont = baseStyle[.font] as? UIFont, baseFont != font {
            font = baseFont
        }

        let previousAttachments = attachments
        let result = NSMutableAttributedString()
        /// (范围, 按下高亮样式, 点击)
        var linkItems: [(NSRange, ZLTextStyle?, () -> Void)] = []
        var nextCache: [RenderKey: RenderedMatch] = [:]
        var live: [Int: Attachment] = [:]
        var nextDisplayMatches: [(range: NSRange, rendered: RenderedMatch)] = []
        var pieces: [ZLDisplayPiece] = []
        var rawCursor = 0

        for seg in segments {
            guard let match = seg.match else {
                let length = (seg.text as NSString).length
                pieces.append(ZLDisplayPiece(display: NSRange(location: result.length, length: length),
                                             raw: NSRange(location: rawCursor, length: length), isMatch: false))
                rawCursor += length
                result.append(NSAttributedString(string: seg.text, attributes: baseStyle))
                continue
            }
            let key = RenderKey(location: match.range.location, length: match.range.length, index: match.index)
            let rendered: RenderedMatch
            if let cached = renderCache[key], cached.isValid(for: match) {
                rendered = cached
                statistics.reusedMatches += 1
            } else {
                rendered = renderMatch(match, baseStyle: baseStyle)
                statistics.handlerCalls += 1
            }
            nextCache[key] = rendered
            rendered.attachments.forEach { live[$0.id] = $0 }

            let range = NSRange(location: result.length, length: rendered.content.length)
            result.append(rendered.content)
            if range.length > 0 { nextDisplayMatches.append((range, rendered)) }
            pieces.append(ZLDisplayPiece(display: range, raw: match.range, isMatch: true))
            rawCursor = NSMaxRange(match.range)
            // 点击时把本次解析的命中传给回调
            if let onTap = rendered.onTap, range.length > 0 {
                linkItems.append((range, rendered.highlightStyle, { onTap(match) }))
            }
            for link in rendered.links {
                guard let onTap = link.onTap else { continue }
                linkItems.append((NSRange(location: range.location + link.range.location, length: link.range.length),
                                  link.highlightStyle, { onTap(match) }))
            }
        }
        renderCache = nextCache
        displayMatches = nextDisplayMatches
        displayPieces = pieces
        contentDisplayLength = result.length
        // 胶囊背景 / 渐变文字：预留内边距、隐藏原文字颜色（只改属性，不改变字符和下标）
        prepareDecorations(in: result, boundaries: nextDisplayMatches.map { $0.range })
        // 内容变了，之前的选中不再有效
        clearSelection()

        // 移除不再使用的 View（同一个 View 可能被新的命中复用，不能误删）
        let liveViews = Set(live.values.map { ObjectIdentifier($0.view) })
        for (id, attachment) in previousAttachments
            where live[id] == nil && !liveViews.contains(ObjectIdentifier(attachment.view)) {
            attachment.view.removeFromSuperview()
        }
        attachments = live

        // 根据最终渲染内容判断书写方向（与 CoreText 的自然段落方向一致；占位符 U+FFFC 为中性字符）
        isRightToLeft = ZLRichLabel.detectRightToLeft(result.string)
            ?? (effectiveUserInterfaceLayoutDirection == .rightToLeft)

        // Dynamic Type：缩放所有字体（含 label.font，绘制时用它修正基线）
        applyContentSizeScaling(to: result)
        if let baseFont = baseStyle[.font] as? UIFont {
            let scaled = scaledFont(baseFont)
            if scaled != font { font = scaled }
        }

        // 收起状态：截断时显示「展开」；展开状态：末尾拼接「收起」（可点击）
        let token: NSMutableAttributedString
        if !isExpanded, let expand = expandToken {
            token = ZLRichLabel.styledToken(expand, baseStyle: baseStyle)
            token.addAttribute(ZLRichLabel.expandTokenKey, value: true, range: NSRange(location: 0, length: token.length))
            if !(lineBreakMode == .byTruncatingTail) { lineBreakMode = .byTruncatingTail }
        } else {
            token = NSMutableAttributedString(
                attributedString: truncationToken ?? NSAttributedString(string: "\u{2026}", attributes: baseStyle))
        }
        if isExpanded, let collapse = collapseToken, collapse.length > 0 {
            let styled = ZLRichLabel.styledToken(collapse, baseStyle: baseStyle)
            applyContentSizeScaling(to: styled, includesAttachments: false)
            let range = NSRange(location: result.length, length: styled.length)
            result.append(styled)
            linkItems.append((range, nil, { [weak self] in self?.expandTokenTapped(wantsExpand: false) }))
        }
        applyContentSizeScaling(to: token, includesAttachments: false)
        attributedTruncationToken = token
        activeLinkAttributes = highlightStyle.isEmpty ? [:] : highlightStyle

        attributedText = result

        for (range, highlight, tapAction) in linkItems {
            // 按下高亮：为 nil 时使用 activeLinkAttributes（即 highlightStyle）
            let link = ZLLabelLink(range: range, activeAttributes: highlight)
            link.onTap = { _, _ in tapAction() }
            addLink(link)
        }

        for attachment in attachments.values.sorted(by: { $0.id < $1.id }) {
            attachment.view.isHidden = true
            addSubview(attachment.view)
        }

        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
    }

    // MARK: Attachments

    private func removeAttachmentViews() {
        attachments.values.forEach { $0.view.removeFromSuperview() }
        attachments.removeAll()
        renderCache.removeAll()
        displayMatches = []
        displayPieces = []
        contentDisplayLength = 0
        clearSelection()
    }

    /// 执行规则 handler，生成单个命中的渲染结果
    private func renderMatch(_ match: ZLRichMatch, baseStyle: ZLTextStyle) -> RenderedMatch {
        // 本次创建的 View 的 id 都 >= firstId（id 只增不减，复用的 View 不会冲突）
        let firstId = nextAttachmentId
        let context = ZLRichRuleContext(match: match, baseStyle: baseStyle) { [unowned self] widget, style in
            let attachment = self.makeAttachment(widget: widget, style: style)
            return self.makeAttachmentString(attachment, style: style)
        }
        match.rule.handler(context)
        context.attachmentFactory = nil

        let onTap = context.onTap
        // CoreText 不绘制 NSTextAttachment，这里转换成 View 承载
        let content = convertTextAttachments(in: context.attributedString, style: baseStyle, tapAction: nil)
        let created = attachments.values.filter { $0.id >= firstId }.sorted { $0.id < $1.id }

        // 自定义 View / 图片的点击：位于哪一段 addLink 的范围内就触发哪一段（后添加的优先），否则触发整体 onTap
        if created.contains(where: { $0.tappable }) {
            var locations: [Int: Int] = [:]
            content.enumerateAttribute(ZLRichLabel.attachmentKey, in: NSRange(location: 0, length: content.length),
                                       options: []) { value, range, _ in
                if let id = value as? Int { locations[id] = range.location }
            }
            for attachment in created where attachment.tappable {
                let link = locations[attachment.id].flatMap { location in
                    context.links.last { $0.onTap != nil && NSLocationInRange(location, $0.range) }
                }
                if let action = link?.onTap ?? onTap { addTap(to: attachment.view, action: { action(match) }) }
            }
        }
        return RenderedMatch(match: match,
                             content: NSAttributedString(attributedString: content),
                             onTap: onTap,
                             onLongPress: context.onLongPress,
                             highlightStyle: context.highlightStyle,
                             attachments: created,
                             links: context.links.filter { NSMaxRange($0.range) <= content.length })
    }

    /// 计算 View 的尺寸：systemLayoutSizeFitting → sizeThatFits → bounds
    private static func measure(_ view: UIView) -> CGSize {
        let fitting = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        if fitting.width > 0, fitting.height > 0 { return fitting }
        let fits = view.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return (fits.width > 0 && fits.height > 0) ? fits : view.bounds.size
    }

    private func makeAttachment(widget: ZLRichWidget, style: ZLTextStyle) -> Attachment {
        let view = widget.view
        let autoSize = widget.size == .zero
        let size = autoSize ? ZLRichLabel.measure(view) : widget.size
        let font = (style[.font] as? UIFont) ?? self.font ?? UIFont.systemFont(ofSize: 17)

        // View 可能被复用：移除之前添加的点击
        view.gestureRecognizers?.filter { $0 is TagTapGestureRecognizer }.forEach { view.removeGestureRecognizer($0) }

        let attachment = Attachment(id: nextAttachmentId, view: view, alignment: widget.alignment,
                                    font: font, autoSize: autoSize, size: size)
        attachment.tappable = widget.tappable
        nextAttachmentId += 1
        attachments[attachment.id] = attachment
        return attachment
    }

    private func addTap(to view: UIView, action: @escaping () -> Void) {
        view.isUserInteractionEnabled = true
        let tap = TagTapGestureRecognizer(target: self, action: #selector(handleAttachmentTap(_:)))
        tap.tapAction = action
        view.addGestureRecognizer(tap)
    }

    private static let runDelegateKey = NSAttributedString.Key(kCTRunDelegateAttributeName as String)

    private func makeAttachmentString(_ attachment: Attachment, style: ZLTextStyle) -> NSAttributedString {
        guard let delegate = makeRunDelegate(attachment) else { return NSAttributedString() }
        var attrs = style
        attrs[.foregroundColor] = UIColor.clear
        attrs[.underlineStyle] = nil
        attrs[.strikethroughStyle] = nil
        attrs[.backgroundColor] = nil
        attrs[ZLRichLabel.runDelegateKey] = delegate
        attrs[ZLRichLabel.attachmentKey] = attachment.id
        return NSAttributedString(string: String(utf16CodeUnits: [ZLRichLabel.attachmentChar], count: 1), attributes: attrs)
    }

    /// 按 Attachment 当前尺寸生成占位用的 CTRunDelegate
    private func makeRunDelegate(_ attachment: Attachment) -> CTRunDelegate? {
        let metrics = RunMetrics(ascent: attachment.ascent, descent: attachment.descent, width: attachment.size.width)
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { ref in
                Unmanaged<RunMetrics>.fromOpaque(ref).release()
            },
            getAscent: { ref in
                return Unmanaged<RunMetrics>.fromOpaque(ref).takeUnretainedValue().ascent
            },
            getDescent: { ref in
                return Unmanaged<RunMetrics>.fromOpaque(ref).takeUnretainedValue().descent
            },
            getWidth: { ref in
                return Unmanaged<RunMetrics>.fromOpaque(ref).takeUnretainedValue().width
            })
        let refCon = Unmanaged.passRetained(metrics).toOpaque()
        guard let delegate = CTRunDelegateCreate(&callbacks, refCon) else {
            Unmanaged<RunMetrics>.fromOpaque(refCon).release()
            return nil
        }
        return delegate
    }

    // MARK: 自定义 View 尺寸变化

    /// 自定义 View 的尺寸 / 内容变化后，刷新排版（不会重新执行规则 handler / builder）。
    ///
    /// - 外部修改了 View 的 frame / bounds 尺寸：使用新尺寸
    /// - `ZLRichWidget.size` 为 `.zero`（自动尺寸）且尺寸没被外部修改：重新测量（适用于 View 内容变化，如 UILabel 换了文字）
    ///
    /// 直接修改 View 的 frame 尺寸时 label 下次布局会自动检测并刷新，一般无需调用；
    /// 也可以在 View 内部调用 `zl_setNeedsRichLabelLayout()`
    @objc(invalidateLayoutForAttachmentView:)
    open func invalidateLayout(forAttachmentView view: UIView) {
        guard let attachment = attachments.values.first(where: { $0.view === view }) else { return }
        if let size = resolvedSize(of: attachment) {
            applyAttachmentSizes([attachment.id: size])
        }
    }

    /// 刷新所有自定义 View 的尺寸与排版，规则同 `invalidateLayout(forAttachmentView:)`
    open func invalidateAttachmentLayout() {
        var changes: [Int: CGSize] = [:]
        for attachment in attachments.values {
            if let size = resolvedSize(of: attachment) { changes[attachment.id] = size }
        }
        applyAttachmentSizes(changes)
    }

    /// View 应有的新尺寸：外部改过尺寸用当前尺寸；自动尺寸的重新测量
    private func resolvedSize(of attachment: Attachment) -> CGSize? {
        let current = attachment.view.bounds.size
        if let applied = attachment.appliedSize, current != applied { return current }
        return attachment.autoSize ? ZLRichLabel.measure(attachment.view) : nil
    }

    /// 外部直接修改了 View 尺寸（与上次布局设置的不同）的 Attachment
    func externallyResizedAttachments() -> [Int: CGSize] {
        var changes: [Int: CGSize] = [:]
        for attachment in attachments.values {
            let current = attachment.view.bounds.size
            if let applied = attachment.appliedSize, current != applied { changes[attachment.id] = current }
        }
        return changes
    }

    /// 按 Attachment 当前尺寸重新生成占位符的 CTRunDelegate（ids 为 nil 时处理全部）
    private func replaceRunDelegates(in string: NSMutableAttributedString, ids: Set<Int>?) {
        string.enumerateAttribute(ZLRichLabel.attachmentKey,
                                  in: NSRange(location: 0, length: string.length), options: []) { value, range, _ in
            guard let id = value as? Int, ids?.contains(id) ?? true,
                  let attachment = attachments[id], let delegate = makeRunDelegate(attachment) else { return }
            string.addAttribute(ZLRichLabel.runDelegateKey, value: delegate, range: range)
        }
    }

    /// 更新占位尺寸：只替换对应占位符的 CTRunDelegate，链接与其他内容不变
    func applyAttachmentSizes(_ sizes: [Int: CGSize]) {
        var changed = Set<Int>()
        for (id, size) in sizes {
            guard let attachment = attachments[id] else { continue }
            attachment.appliedSize = nil
            guard size != attachment.size else { continue }
            attachment.update(size: size)
            changed.insert(id)
        }
        guard !changed.isEmpty, let attr = attributedText, attr.length > 0 else {
            setNeedsLayout()
            return
        }

        let mutable = NSMutableAttributedString(attributedString: attr)
        replaceRunDelegates(in: mutable, ids: changed)
        // 只替换了 CTRunDelegate：保留已添加的链接
        replaceAttributedTextKeepingLinks(mutable)

        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// 把内容中的 NSTextAttachment（图片）转换为 UIImageView 占位
    private func convertTextAttachments(in string: NSAttributedString,
                                        style: ZLTextStyle,
                                        tapAction: (() -> Void)?) -> NSAttributedString {
        var found: [(NSRange, NSTextAttachment)] = []
        string.enumerateAttribute(.attachment, in: NSRange(location: 0, length: string.length), options: []) { value, range, _ in
            if let att = value as? NSTextAttachment { found.append((range, att)) }
        }
        guard !found.isEmpty else { return string }

        let mutable = NSMutableAttributedString(attributedString: string)
        for (range, att) in found.reversed() {
            guard let image = att.image ?? att.image(forBounds: att.bounds, textContainer: nil, characterIndex: range.location) else {
                mutable.deleteCharacters(in: range)
                continue
            }
            let size = att.bounds.size == .zero ? image.size : att.bounds.size
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            if let color = mutable.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor {
                imageView.tintColor = color
            }

            var attrs = style
            mutable.attributes(at: range.location, effectiveRange: nil).forEach { attrs[$0.key] = $0.value }
            attrs[.attachment] = nil

            let widget = ZLRichWidget(view: imageView, size: size, position: .replace, alignment: .middle, tappable: true)
            let attachment = makeAttachment(widget: widget, style: attrs)
            if let tapAction = tapAction { addTap(to: imageView, action: tapAction) }
            mutable.replaceCharacters(in: range, with: makeAttachmentString(attachment, style: attrs))
        }
        return mutable
    }

    @objc private func handleAttachmentTap(_ gesture: TagTapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        gesture.tapAction?()
    }

    // MARK: Layout

    var richLastLayoutWidth: CGFloat = 0

    /// 尺寸失效时回调（SwiftUI 封装 `ZLRichText` 用它在内容变化后重新计算高度）
    var intrinsicSizeObserver: (() -> Void)?

    open override var bounds: CGRect {
        didSet { if bounds.size != oldValue.size { setNeedsLayout() } }
    }

    /// 当前内容是否为从右到左（RTL）书写
    /// 规则与 CoreText 自然段落方向一致：取第一个强方向字符；没有强方向字符时跟随界面布局方向
    public private(set) var isRightToLeft: Bool = false

    lazy var gestureDelegate = RichGestureDelegate(label: self)
    /// 有选中时点击 label：取消选中（同时吞掉这次点击，不触发链接）
    var selectionDismissTap: UITapGestureRecognizer?

    var expandTapGesture: UITapGestureRecognizer?

}

// MARK: - 批量更新（Swift）

/// 让 `update { v in ... }` 中的 `v` 为 label 的实际类型（例如 `ZLTagRichLabel`）
public protocol ZLRichLabelUpdatable: AnyObject {}

extension ZLRichLabel: ZLRichLabelUpdatable {}

public extension ZLRichLabelUpdatable where Self: ZLRichLabel {
    /// 批量修改属性，只在最后刷新一次
    func update(_ block: (Self) -> Void) {
        beginUpdates()
        block(self)
        endUpdates()
    }
}

// MARK: - 自定义 View 尺寸变化

public extension UIView {
    /// 当前 View（或其子 View）作为自定义 View 内嵌在 `ZLRichLabel` 中时，
    /// 尺寸 / 内容变化后调用，让所在的 label 重新排版
    @objc(zl_setNeedsRichLabelLayout)
    func zl_setNeedsRichLabelLayout() {
        var child: UIView = self
        var parent = superview
        while let current = parent {
            if let label = current as? ZLRichLabel {
                label.invalidateLayout(forAttachmentView: child)
                return
            }
            child = current
            parent = current.superview
        }
    }
}
