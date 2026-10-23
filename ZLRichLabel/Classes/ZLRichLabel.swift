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

    /// 收起时的行数（即设置的 `numberOfLines`，展开时也不变）
    public var collapsedNumberOfLines: Int { return super.numberOfLines }

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

    /// 某个文字宽度下实际使用的行数：展开时为 0；设置了 `collapseThreshold` 且内容不超过它时为 0（完整显示）
    func effectiveNumberOfLines(forTextWidth width: CGFloat) -> Int {
        if isExpanded { return 0 }
        let collapsed = super.numberOfLines
        guard collapsed > 0, collapseThreshold > collapsed, width > 0,
              let attr = attributedText, attr.length > 0 else { return collapsed }
        return lineCount(of: attr, width: width) <= collapseThreshold ? 0 : collapsed
    }

    /// 当前内容是否被截断（最近一次布局的结果）
    public private(set) var isTruncated: Bool = false

    /// 「展开」按钮的可点击区域（label 坐标系，已适当扩大），没有显示时为 `.zero`
    public private(set) var expandTokenRect: CGRect = .zero

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
    public private(set) var richDoubleTapGesture: UITapGestureRecognizer?

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

    /// 切换展开状态并回调 `onExpandChanged`，与点击「展开 / 收起」的效果相同
    open func toggleExpanded() {
        isExpanded.toggle()
        onExpandChanged?(isExpanded)
    }

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
    private static let attachmentChar: unichar = 0xFFFC

    private final class Attachment {
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

    private var attachments: [Int: Attachment] = [:]
    private var nextAttachmentId = 0
    private var batchUpdateDepth = 0
    private var isRebuilding = false

    /// 渲染 / 排版统计（观察缓存效果）
    public let statistics = ZLRichLabelStatistics()

    /// 单个命中的渲染结果（handler / builder 的输出 + 创建的 View），下次渲染时直接复用
    private final class RenderedMatch {
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
    private var displayMatches: [(range: NSRange, rendered: RenderedMatch)] = []

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
        setupExpandGesture()
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
            linkItems.append((range, nil, { [weak self] in self?.toggleExpanded() }))
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
    private func externallyResizedAttachments() -> [Int: CGSize] {
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
    private func applyAttachmentSizes(_ sizes: [Int: CGSize]) {
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

    private var lastLayoutWidth: CGFloat = 0

    open override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastLayoutWidth {
            lastLayoutWidth = bounds.width
            // 宽度变化后高度可能变化（Auto Layout 自适应高度）
            invalidateIntrinsicContentSize()
        }
        layoutAttachmentViews()
        layoutExpandToken()
        if hasSelection { updateSelectionAppearance() }
    }

    /// 支持 Auto Layout 自适应高度：宽度由约束决定，高度根据内容计算
    open override var intrinsicContentSize: CGSize {
        let width = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : bounds.width
        guard width > 0, attributedText != nil else { return super.intrinsicContentSize }
        let size = sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(size.height))
    }

    /// 尺寸失效时回调（SwiftUI 封装 `ZLRichText` 用它在内容变化后重新计算高度）
    var intrinsicSizeObserver: (() -> Void)?

    open override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        intrinsicSizeObserver?()
    }

    open override var bounds: CGRect {
        didSet { if bounds.size != oldValue.size { setNeedsLayout() } }
    }

    /// 展开时读取为 0（显示全部）；设置的值保存为收起时的行数（`collapsedNumberOfLines`）。
    /// 设置了 `collapseThreshold` 且内容（按当前宽度）不超过它时也读取为 0
    open override var numberOfLines: Int {
        get { return effectiveNumberOfLines(forTextWidth: bounds.width - textInsets.left - textInsets.right) }
        set {
            super.numberOfLines = newValue
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// `.natural` 默认按界面方向对齐，阿拉伯语 / 希伯来语等 RTL 文本在 LTR 界面中会错误地靠左。
    /// 这里把 `.natural` 按内容的书写方向解析为 `.left` / `.right`
    open override var textAlignment: NSTextAlignment {
        get {
            let value = super.textAlignment
            guard value == .natural else { return value }
            return isRightToLeft ? .right : .left
        }
        set {
            super.textAlignment = newValue
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// 当前内容是否为从右到左（RTL）书写
    /// 规则与 CoreText 自然段落方向一致：取第一个强方向字符；没有强方向字符时跟随界面布局方向
    public private(set) var isRightToLeft: Bool = false

    private static func detectRightToLeft(_ string: String) -> Bool? {
        for scalar in string.unicodeScalars {
            let v = scalar.value
            // Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan, Mandaic, Arabic Ext, 表现形式
            if (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
                || (0x10800...0x10FFF).contains(v) || (0x1E800...0x1EFFF).contains(v) {
                // 阿拉伯-印度数字（0660–0669、06F0–06F9）是弱方向字符，跳过
                if (0x0660...0x0669).contains(v) || (0x06F0...0x06F9).contains(v) { continue }
                return true
            }
            if CharacterSet.letters.contains(scalar) {
                return false
            }
        }
        return nil
    }

    /// 与 ZLAttributedLabel 的绘制逻辑保持一致，计算自定义 View 的位置
    private func layoutAttachmentViews() {
        // 外部直接修改了 View 的尺寸（例如点击后展开）：先更新占位尺寸再布局
        let resized = externallyResizedAttachments()
        if !resized.isEmpty { applyAttachmentSizes(resized) }

        attachments.values.forEach { $0.view.isHidden = true }
        guard !attachments.isEmpty,
              let attr = attributedText, attr.length > 0,
              bounds.width > 0, bounds.height > 0 else { return }

        let textRect = self.textRect(forBounds: bounds, limitedToNumberOfLines: numberOfLines)
        let (lines, origins) = frameLines(for: attr, in: textRect)
        guard !lines.isEmpty else { return }

        let count = numberOfLines > 0 ? min(numberOfLines, lines.count) : lines.count

        let truncateLastLine = lineBreakMode == .byTruncatingHead
            || lineBreakMode == .byTruncatingMiddle
            || lineBreakMode == .byTruncatingTail
        let fontDescender = (font ?? UIFont.systemFont(ofSize: 17)).descender
        let width = Double(textRect.width)

        for lineIndex in 0..<count {
            var line = lines[lineIndex]
            var lineString: NSAttributedString = attr

            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, nil, &descent, nil)

            if lineIndex == count - 1 && truncateLastLine,
               let truncated = truncatedLine(for: line, in: attr, lineCount: count, width: width) {
                line = truncated.line
                lineString = truncated.string
            }

            let penOffset = CGFloat(CTLineGetPenOffsetForFlush(line, flushFactor, width))
            let baselineCT = origins[lineIndex].y - descent - fontDescender
            let baselineY = textRect.minY + textRect.height - baselineCT
            let string = lineString.string as NSString

            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { continue }
            for run in runs {
                let attrs = CTRunGetAttributes(run) as NSDictionary
                guard let id = attrs[ZLRichLabel.attachmentKey.rawValue] as? Int,
                      let attachment = attachments[id] else { continue }
                let range = CTRunGetStringRange(run)
                guard range.location >= 0, range.location < string.length,
                      string.character(at: range.location) == ZLRichLabel.attachmentChar,
                      CTRunGetGlyphCount(run) > 0 else { continue }

                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)

                attachment.view.frame = CGRect(x: textInsets.left + penOffset + position.x,
                                               y: baselineY - attachment.ascent,
                                               width: attachment.size.width,
                                               height: attachment.size.height)
                attachment.appliedSize = attachment.view.bounds.size
                attachment.view.isHidden = false
            }
        }
    }

    // MARK: 展开 / 收起

    private static let expandTokenKey = NSAttributedString.Key("ZLRichLabelExpandToken")

    /// 按钮富文本：先铺普通文本样式，再覆盖按钮自己的属性
    private static func styledToken(_ token: NSAttributedString, baseStyle: ZLTextStyle) -> NSMutableAttributedString {
        let styled = NSMutableAttributedString(string: token.string, attributes: baseStyle)
        token.enumerateAttributes(in: NSRange(location: 0, length: token.length), options: []) { attrs, range, _ in
            styled.addAttributes(attrs, range: range)
        }
        return styled
    }

    private lazy var gestureDelegate = RichGestureDelegate(label: self)
    /// 有选中时点击 label：取消选中（同时吞掉这次点击，不触发链接）
    fileprivate var selectionDismissTap: UITapGestureRecognizer?

    @objc private func handleSelectionDismissTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        clearSelection()
    }
    private var expandTapGesture: UITapGestureRecognizer?

    private func setupExpandGesture() {
        // 基类的链接长按只作用于链接，这里统一由 richLongPressGesture 处理
        longPressGestureRecognizer?.isEnabled = false
        addGestureRecognizer(richLongPressGesture)

        let dismiss = UITapGestureRecognizer(target: self, action: #selector(handleSelectionDismissTap(_:)))
        dismiss.delegate = gestureDelegate
        selectionDismissTap = dismiss
        addGestureRecognizer(dismiss)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleExpandTap(_:)))
        tap.delegate = gestureDelegate
        expandTapGesture = tap
        // 只接收「展开」按钮区域内的触摸；延迟下发，避免按钮下方被截断的链接先出现按下高亮
        tap.delaysTouchesBegan = true
        addGestureRecognizer(tap)
    }

    private func updateDoubleTapGesture() {
        if onDoubleTap == nil {
            if let gesture = richDoubleTapGesture { removeGestureRecognizer(gesture) }
            richDoubleTapGesture = nil
            return
        }
        guard richDoubleTapGesture == nil else { return }
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleRichDoubleTap(_:)))
        gesture.numberOfTapsRequired = 2
        gesture.delegate = gestureDelegate
        // 默认 delaysTouchesEnded = true：双击成功时取消链接点击，失败后再交给链接
        addGestureRecognizer(gesture)
        expandTapGesture?.require(toFail: gesture)
        richDoubleTapGesture = gesture
    }

    @objc private func handleRichLongPress(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            if let handler = longPressHandler(at: location) {
                handler()
                return
            }
            if isSelectable {
                beginSelection(at: location)
                return
            }
            onLongPress?(gestureInfo(at: location))
        case .changed:
            if selectionAnchor != nil { extendSelection(to: location) }
        case .ended, .cancelled:
            if selectionAnchor != nil {
                selectionAnchor = nil
                showSelectionMenu()
            }
        default:
            break
        }
    }

    @objc private func handleRichDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        onDoubleTap?(gestureInfo(at: gesture.location(in: self)))
    }

    /// 长按是否需要开始：有 `onLongPress` 或该位置的命中设置了 `ctx.onLongPress`
    fileprivate func shouldBeginLongPress(at location: CGPoint) -> Bool {
        if onLongPress != nil || isSelectable { return true }
        return longPressHandler(at: location) != nil
    }

    /// 某个位置的命中长按：先找覆盖该位置的分段（后添加的优先），再用命中整体的 onLongPress
    private func longPressHandler(at point: CGPoint) -> (() -> Void)? {
        guard let item = displayMatch(at: point) else { return nil }
        let index = characterIndex(at: point)
        if index != NSNotFound {
            let offset = index - item.range.location
            if let link = item.rendered.links.last(where: { $0.onLongPress != nil && NSLocationInRange(offset, $0.range) }),
               let handler = link.onLongPress {
                return { handler(item.rendered.matchInfo) }
            }
        }
        guard let handler = item.rendered.onLongPress else { return nil }
        return { handler(item.rendered.matchInfo) }
    }

    // MARK: UIResponder（选中复制菜单）

    /// 只在有选中时成为第一响应者
    open override var canBecomeFirstResponder: Bool {
        return isSelectable && hasSelection
    }

    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard isSelectable, hasSelection else { return false }
        if action == #selector(copy(_:)) || action == #selector(zl_copyRawText(_:)) { return true }
        if action == #selector(selectAll(_:)) { return selectedRange.length < contentDisplayLength }
        return false
    }

    /// 复制选中的展示文字
    open override func copy(_ sender: Any?) {
        copySelection(raw: false)
    }

    open override func selectAll(_ sender: Any?) {
        reshowsSelectionMenu = true
        selectAllText()
    }

    /// 复制选中范围对应的原文（菜单项「复制原文」）
    @objc open func zl_copyRawText(_ sender: Any?) {
        copySelection(raw: true)
    }

    /// 基类在点位有链接时直接返回 label 自身，内嵌的自定义 View（自带手势 / UIControl）收不到触摸。
    /// 这里先让「自己处理交互」的子 View 命中；没有自己交互的 View（以及只带内部点击的 View）仍交给链接处理
    open override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if isUserInteractionEnabled, !isHidden, alpha >= 0.01, self.point(inside: point, with: event) {
            for subview in subviews.reversed()
            where !subview.isHidden && subview.isUserInteractionEnabled && subview.alpha >= 0.01 {
                guard let hit = subview.hitTest(convert(point, to: subview), with: event),
                      handlesOwnTouches(hit) else { continue }
                return hit
            }
        }
        return super.hitTest(point, with: event)
    }

    /// 从命中的 View 向上到 label（不含），是否有 View 自己处理触摸（UIControl 或有外部添加的手势）
    private func handlesOwnTouches(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let v = current, v !== self {
            if v is UIControl { return true }
            if v.gestureRecognizers?.contains(where: { $0.isEnabled && !($0 is TagTapGestureRecognizer) }) == true {
                return true
            }
            current = v.superview
        }
        return false
    }

    /// 选中时拖柄在 bounds 外，也要能接收触摸
    open override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        return selectionHandles.contains { !$0.isHidden && $0.frame.contains(point) }
    }

    // MARK: 按坐标定位

    /// 某个位置的手势信息（字符下标、所在命中等）
    @objc(gestureInfoAtPoint:)
    open func gestureInfo(at point: CGPoint) -> ZLRichGestureInfo {
        let index = characterIndex(at: point)
        let item = displayMatch(at: point)
        let display = (attributedText?.string ?? "") as NSString
        let matchText = item.map { NSMaxRange($0.range) <= display.length ? display.substring(with: $0.range) : "" }
        return ZLRichGestureInfo(location: point, characterIndex: index, match: item?.rendered.matchInfo,
                                 matchDisplayText: matchText, rawText: rawText, displayText: display as String)
    }

    /// 某个位置所在的规则命中，不在命中上时为 nil。
    /// `extendsLinkTouchArea` 为 true 时，可交互的命中（有 onTap / onLongPress）点击区域向四周扩大最多 15pt
    @objc(matchAtPoint:)
    open func match(at point: CGPoint) -> ZLRichMatch? {
        return displayMatch(at: point)?.rendered.matchInfo
    }

    private func displayMatch(at point: CGPoint) -> (range: NSRange, rendered: RenderedMatch)? {
        let index = characterIndex(at: point)
        // 按在文字上时以这个字为准：不再向四周扩大查找，避免按在普通文字上却命中了上下行的链接
        guard index == NSNotFound else { return displayMatch(atCharacter: index) }
        guard extendsLinkTouchArea else { return nil }
        // 与 ZLAttributedLabel.link(at:) 一致：由近到远在 8 个方向上查找可交互的命中
        for radius: CGFloat in [2.5, 5, 7.5, 12.5, 15] {
            let diagonal = (2 * radius * radius).squareRoot()
            let deltas = [CGPoint(x: 0, y: -radius), CGPoint(x: 0, y: radius), CGPoint(x: -radius, y: 0),
                          CGPoint(x: radius, y: 0), CGPoint(x: -diagonal, y: -diagonal), CGPoint(x: -diagonal, y: diagonal),
                          CGPoint(x: diagonal, y: diagonal), CGPoint(x: diagonal, y: -diagonal)]
            for delta in deltas {
                let candidate = CGPoint(x: point.x + delta.x, y: point.y + delta.y)
                if let item = displayMatch(atCharacter: characterIndex(at: candidate)),
                   item.rendered.onTap != nil || item.rendered.onLongPress != nil || !item.rendered.links.isEmpty {
                    return item
                }
            }
        }
        return nil
    }

    /// 某个字符所在命中在展示文字中的范围
    func displayMatchRange(atCharacter index: Int) -> NSRange? {
        return displayMatch(atCharacter: index)?.range
    }

    private func displayMatch(atCharacter index: Int) -> (range: NSRange, rendered: RenderedMatch)? {
        guard index != NSNotFound else { return nil }
        // displayMatches 按位置排序：二分查找
        var low = 0
        var high = displayMatches.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let range = displayMatches[mid].range
            if index < range.location { high = mid - 1 } else if index >= NSMaxRange(range) { low = mid + 1 } else {
                return displayMatches[mid]
            }
        }
        return nil
    }

    @objc private func handleExpandTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, !isExpanded, expandTokenRect.contains(gesture.location(in: self)) else { return }
        toggleExpanded()
    }

    /// 计算是否被截断，以及「展开」按钮在 label 中的位置（与绘制的截断行一致）
    private func layoutExpandToken() {
        isTruncated = false
        expandTokenRect = .zero
        let lineLimit = numberOfLines
        guard lineLimit > 0, let attr = attributedText, attr.length > 0, bounds.width > 0, bounds.height > 0 else { return }

        let textRect = self.textRect(forBounds: bounds, limitedToNumberOfLines: lineLimit)
        let (lines, origins) = frameLines(for: attr, in: textRect)
        guard !lines.isEmpty else { return }
        let count = min(lineLimit, lines.count)
        let lastLine = lines[count - 1]
        let lastRange = CTLineGetStringRange(lastLine)
        isTruncated = lastRange.location + lastRange.length < attr.length
        guard isTruncated, !isExpanded, expandToken != nil,
              let truncated = truncatedLine(for: lastLine, in: attr, lineCount: count, width: Double(textRect.width))
        else { return }

        var descent: CGFloat = 0
        CTLineGetTypographicBounds(lastLine, nil, &descent, nil)
        let fontDescender = (font ?? UIFont.systemFont(ofSize: 17)).descender
        let penOffset = CGFloat(CTLineGetPenOffsetForFlush(truncated.line, flushFactor, Double(textRect.width)))
        let baselineY = textRect.minY + textRect.height - (origins[count - 1].y - descent - fontDescender)

        var rect = CGRect.null
        for run in (CTLineGetGlyphRuns(truncated.line) as? [CTRun]) ?? [] {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            guard attrs[ZLRichLabel.expandTokenKey.rawValue] != nil, CTRunGetGlyphCount(run) > 0 else { continue }
            var position = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
            var ascent: CGFloat = 0
            var runDescent: CGFloat = 0
            let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &runDescent, nil))
            rect = rect.union(CGRect(x: textInsets.left + penOffset + position.x, y: baselineY - ascent,
                                     width: width, height: ascent + runDescent))
        }
        guard !rect.isNull else { return }
        // 适当扩大点击区域
        expandTokenRect = rect.insetBy(dx: -8, dy: -6)
    }

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

/// label 自己添加的手势的代理（基类的链接长按手势有自己的代理，这里单独处理）：
/// - 「展开」点击：只接收按钮区域内的触摸，其他位置交给 ZLAttributedLabel 处理链接
/// - 长按：有 `onLongPress` 或该位置的命中设置了 `ctx.onLongPress` 时才开始
private final class RichGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var label: ZLRichLabel?

    init(label: ZLRichLabel) {
        self.label = label
        super.init()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let label = label else { return false }
        if gestureRecognizer === label.richLongPressGesture || gestureRecognizer === label.richDoubleTapGesture {
            return true
        }
        if gestureRecognizer === label.selectionDismissTap {
            // 只在有选中、且没有点到拖柄时接收
            guard label.hasSelection else { return false }
            return !label.selectionHandles.contains { !$0.isHidden && $0.frame.contains(touch.location(in: label)) }
        }
        guard !label.isExpanded, label.expandTokenRect != .zero else { return false }
        return label.expandTokenRect.contains(touch.location(in: label))
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let label = label else { return false }
        if gestureRecognizer === label.richLongPressGesture {
            return label.shouldBeginLongPress(at: gestureRecognizer.location(in: label))
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return false
    }
}

/// 自定义 View 的点击手势（携带点击动作）
private final class TagTapGestureRecognizer: UITapGestureRecognizer {
    var tapAction: (() -> Void)?
}
