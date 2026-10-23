//
//  ZLRichLabel+Selection.swift
//  ZLRichLabel
//
//  选中复制：长按选词 / 拖动扩展、两端拖柄、选中背景，「复制 / 复制原文 / 全选」菜单。
//  展示文字与原文按片段对应：普通文字逐字对应，规则命中只要选中一部分就对应整个命中的原文。
//

import UIKit

/// 展示文字中的一段与原文的对应关系
struct ZLDisplayPiece {
    /// 在展示文字（attributedText）中的范围
    let display: NSRange
    /// 在原文（rawText）中的范围
    let raw: NSRange
    /// 是否为规则命中（命中的展示内容可能被替换过，不能逐字对应）
    let isMatch: Bool
}

extension ZLRichLabel {

    // MARK: - 公开 API

    /// 是否有选中
    public var hasSelection: Bool {
        return selectedRange.location != NSNotFound && selectedRange.length > 0
    }

    /// 选中的展示文字（自定义 View / 图片的占位符会被去掉），没有选中时为 nil
    public var selectedText: String? {
        guard hasSelection, let attr = attributedText, NSMaxRange(selectedRange) <= attr.length else { return nil }
        return (attr.string as NSString).substring(with: selectedRange)
            .replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    /// 选中范围对应的原文：普通文字逐字对应；选中了规则命中的一部分时，取整个命中的原文（例如表情图片对应 `[smile]`）
    public var selectedRawText: String? {
        guard hasSelection else { return nil }
        return rawText(forDisplayRange: selectedRange)
    }

    /// 展示文字中某个范围对应的原文
    @objc(rawTextForDisplayRange:)
    public func rawText(forDisplayRange range: NSRange) -> String {
        let raw = rawText as NSString
        var result = ""
        for piece in displayPieces {
            let overlap = NSIntersectionRange(piece.display, range)
            // 长度为 0 的命中（展示内容为空）在选中范围内部时也带上原文
            let inside = piece.display.length == 0
                && piece.display.location > range.location && piece.display.location < NSMaxRange(range)
            guard overlap.length > 0 || inside else { continue }
            if piece.isMatch {
                result += raw.substring(with: piece.raw)
            } else {
                let offset = overlap.location - piece.display.location
                result += raw.substring(with: NSRange(location: piece.raw.location + offset, length: overlap.length))
            }
        }
        return result
    }

    /// 选中全部正文（不含展开后的「收起」）
    @objc public func selectAllText() {
        guard contentDisplayLength > 0 else { return }
        setSelection(NSRange(location: 0, length: contentDisplayLength))
    }

    /// 选中展示文字中的某个范围（超出正文的部分会被截掉），并显示拖柄
    @objc(selectRange:)
    public func select(range: NSRange) {
        setSelection(range)
    }

    /// 取消选中并关闭菜单
    @objc public func clearSelection() {
        selectionAnchor = nil
        guard selectedRange.location != NSNotFound else { return }
        selectedRange = NSRange(location: NSNotFound, length: 0)
        updateSelectionAppearance()
        hideSelectionMenu()
        if isFirstResponder { resignFirstResponder() }
        onSelectionChanged?(selectedRange)
    }

    /// 复制选中内容：`raw` 为 true 时复制原文，否则复制展示文字
    @objc(copySelectionRaw:)
    public func copySelection(raw: Bool) {
        guard let text = raw ? selectedRawText : selectedText else { return }
        UIPasteboard.general.string = text
        onCopy?(text, raw)
    }

    // MARK: - 长按选中

    /// 长按开始：选中一个词；在规则命中上则选中整个命中
    func beginSelection(at point: CGPoint) {
        var index = characterIndex(at: point)
        if index == NSNotFound { index = closestCaretIndex(at: point) }
        guard index != NSNotFound, contentDisplayLength > 0 else { return }
        let range = wordRange(at: min(index, contentDisplayLength - 1))
        selectionAnchor = range
        hideSelectionMenu()
        setSelection(range)
    }

    /// 长按拖动：以开始时的词为锚点向两边扩展
    func extendSelection(to point: CGPoint) {
        guard let anchor = selectionAnchor else { return }
        let caret = closestCaretIndex(at: point)
        guard caret != NSNotFound else { return }
        let start = min(anchor.location, caret)
        let end = max(NSMaxRange(anchor), caret)
        setSelection(NSRange(location: start, length: end - start))
    }

    /// 某个字符所在的词：规则命中整体选中；否则按系统分词（中文按词，英文按单词），找不到时选中单个字符
    func wordRange(at index: Int) -> NSRange {
        if let match = displayMatchRange(atCharacter: index) { return match }
        let string = (attributedText?.string ?? "") as NSString
        guard index < string.length else { return NSRange(location: NSNotFound, length: 0) }
        var result = string.rangeOfComposedCharacterSequence(at: index)
        let paragraph = string.paragraphRange(for: NSRange(location: index, length: 0))
        string.enumerateSubstrings(in: paragraph, options: [.byWords, .substringNotRequired]) { _, range, _, stop in
            if NSLocationInRange(index, range) {
                result = range
                stop.pointee = true
            } else if range.location > index {
                stop.pointee = true
            }
        }
        return result
    }

    func setSelection(_ range: NSRange) {
        guard range.location != NSNotFound, contentDisplayLength > 0 else {
            clearSelection()
            return
        }
        let start = max(0, min(range.location, contentDisplayLength))
        let end = max(start, min(NSMaxRange(range), contentDisplayLength))
        let clamped = NSRange(location: start, length: end - start)
        guard clamped.length > 0 else {
            clearSelection()
            return
        }
        guard !NSEqualRanges(clamped, selectedRange) else { return }
        selectedRange = clamped
        updateSelectionAppearance()
        onSelectionChanged?(clamped)
    }

    // MARK: - 选中背景与拖柄

    func updateSelectionAppearance() {
        guard hasSelection, bounds.width > 0 else {
            selectionLayer.removeFromSuperlayer()
            selectionHandles.forEach { $0.isHidden = true }
            return
        }
        let color = selectionColor ?? tintColor.withAlphaComponent(0.25)
        let path = UIBezierPath()
        for rect in selectionRects(for: selectedRange) { path.append(UIBezierPath(rect: rect)) }
        selectionLayer.path = path.cgPath
        selectionLayer.fillColor = color.cgColor
        if selectionLayer.superlayer == nil { layer.addSublayer(selectionLayer) }

        if selectionHandles.isEmpty {
            selectionHandles = [ZLSelectionHandleView(isStart: true), ZLSelectionHandleView(isStart: false)]
            for handle in selectionHandles {
                let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSelectionHandlePan(_:)))
                pan.delegate = ZLSelectionHandlePanDelegate.shared
                handle.addGestureRecognizer(pan)
                addSubview(handle)
            }
        }
        let handleColor = selectionColor?.withAlphaComponent(1) ?? tintColor ?? .systemBlue
        let caretStart = caretRect(at: selectedRange.location, preferringPreviousLine: false)
        let caretEnd = caretRect(at: NSMaxRange(selectedRange), preferringPreviousLine: true)
        for (handle, caret) in zip(selectionHandles, [caretStart, caretEnd]) {
            handle.color = handleColor
            handle.layout(caret: caret)
            handle.isHidden = caret.isNull
            bringSubviewToFront(handle)
        }
    }

    @objc private func handleSelectionHandlePan(_ pan: UIPanGestureRecognizer) {
        guard let handle = pan.view as? ZLSelectionHandleView, hasSelection else { return }
        switch pan.state {
        case .began:
            isAdjustingSelection = true
            hideSelectionMenu()
            // 记录手指到光标中心的偏移：手指按在圆点上拖动时，仍按光标位置计算
            let index = handle.isStart ? selectedRange.location : NSMaxRange(selectedRange)
            let caret = caretRect(at: index, preferringPreviousLine: !handle.isStart)
            let location = pan.location(in: self)
            handle.dragOffset = caret.isNull ? .zero : CGPoint(x: caret.midX - location.x, y: caret.midY - location.y)
        case .changed:
            let location = pan.location(in: self)
            let caret = closestCaretIndex(at: CGPoint(x: location.x + handle.dragOffset.x,
                                                      y: location.y + handle.dragOffset.y))
            guard caret != NSNotFound else { return }
            let start = selectedRange.location
            let end = NSMaxRange(selectedRange)
            if handle.isStart, caret < end {
                setSelection(NSRange(location: caret, length: end - caret))
            } else if !handle.isStart, caret > start {
                setSelection(NSRange(location: start, length: caret - start))
            }
        case .ended, .cancelled, .failed:
            isAdjustingSelection = false
            showSelectionMenu()
        default:
            break
        }
    }

    // MARK: - 几何

    /// 可见行的排版信息（label 坐标系）
    struct LineInfo {
        let line: CTLine
        let range: NSRange
        let top: CGFloat
        let bottom: CGFloat
        /// 行起点的 x（label 坐标系）
        let originX: CGFloat
        let width: CGFloat
    }

    func visibleLines() -> [LineInfo] {
        guard let attr = attributedText, attr.length > 0, bounds.width > 0 else { return [] }
        let lineLimit = numberOfLines
        let textRect = self.textRect(forBounds: bounds, limitedToNumberOfLines: lineLimit)
        let (lines, origins) = frameLines(for: attr, in: textRect)
        let count = lineLimit > 0 ? min(lineLimit, lines.count) : lines.count
        let fontDescender = (font ?? UIFont.systemFont(ofSize: 17)).descender
        var result: [LineInfo] = []
        for i in 0..<count {
            let line = lines[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let baselineY = textRect.minY + textRect.height - (origins[i].y - descent - fontDescender)
            let penOffset = CGFloat(CTLineGetPenOffsetForFlush(line, flushFactor, Double(textRect.width)))
            let cfRange = CTLineGetStringRange(line)
            result.append(LineInfo(line: line, range: NSRange(location: cfRange.location, length: cfRange.length),
                                   top: baselineY - ascent, bottom: baselineY + descent,
                                   originX: textInsets.left + penOffset, width: width))
        }
        return result
    }

    /// 离某个位置最近的光标位置（插入点下标）：先按 y 找最近的行，再按 x 找行内位置
    func closestCaretIndex(at point: CGPoint) -> Int {
        let lines = visibleLines()
        guard !lines.isEmpty else { return NSNotFound }
        let info = lines.min { distance(point.y, $0) < distance(point.y, $1) }!
        let x = point.x - info.originX
        var index = CTLineGetStringIndexForPosition(info.line, CGPoint(x: max(0, min(x, info.width)), y: 0))
        if index == kCFNotFound { return NSNotFound }
        // 行尾的换行符不作为光标位置
        let string = (attributedText?.string ?? "") as NSString
        let lineEnd = NSMaxRange(info.range)
        if index >= lineEnd, lineEnd > info.range.location,
           let scalar = UnicodeScalar(string.character(at: lineEnd - 1)), CharacterSet.newlines.contains(scalar) {
            index = lineEnd - 1
        }
        return min(max(index, 0), contentDisplayLength)
    }

    private func distance(_ y: CGFloat, _ info: LineInfo) -> CGFloat {
        if y < info.top { return info.top - y }
        if y > info.bottom { return y - info.bottom }
        return 0
    }

    /// 某个范围在 label 中的矩形（每行一个）
    func selectionRects(for range: NSRange) -> [CGRect] {
        var rects: [CGRect] = []
        for info in visibleLines() {
            let overlap = NSIntersectionRange(info.range, range)
            guard overlap.length > 0 else { continue }
            let x1 = CTLineGetOffsetForStringIndex(info.line, overlap.location, nil)
            let x2 = NSMaxRange(overlap) >= NSMaxRange(info.range)
                ? CGFloat(info.width)
                : CTLineGetOffsetForStringIndex(info.line, NSMaxRange(overlap), nil)
            let minX = info.originX + min(x1, x2)
            let maxX = info.originX + max(x1, x2)
            rects.append(CGRect(x: minX, y: info.top, width: max(1, maxX - minX), height: info.bottom - info.top))
        }
        return rects
    }

    /// 光标位置的矩形；`preferringPreviousLine` 为 true 时，位于行首的光标归到上一行行尾（用于选中范围的结尾）
    func caretRect(at index: Int, preferringPreviousLine: Bool) -> CGRect {
        let lines = visibleLines()
        var target: LineInfo?
        for info in lines {
            let start = info.range.location
            let end = NSMaxRange(info.range)
            if preferringPreviousLine ? (index > start && index <= end) : (index >= start && index < end) {
                target = info
                break
            }
        }
        if target == nil, let last = lines.last, index >= NSMaxRange(last.range) { target = last }
        guard let info = target else { return .null }
        let offset = index >= NSMaxRange(info.range)
            ? CGFloat(info.width)
            : CTLineGetOffsetForStringIndex(info.line, index, nil)
        return CGRect(x: info.originX + offset, y: info.top, width: 2, height: info.bottom - info.top)
    }

    /// 选中范围的外接矩形（用于菜单定位）
    var selectionBoundingRect: CGRect {
        let rects = selectionRects(for: selectedRange)
        return rects.reduce(CGRect.null) { $0.union($1) }
    }

    // MARK: - 菜单

    func showSelectionMenu() {
        guard hasSelection, window != nil else { return }
        let rect = selectionBoundingRect
        guard !rect.isNull else { return }
        if #available(iOS 16.0, *) {
            let menu = (selectionEditMenu as? ZLSelectionEditMenu) ?? {
                let created = ZLSelectionEditMenu(label: self)
                selectionEditMenu = created
                return created
            }()
            menu.present(at: CGPoint(x: rect.midX, y: rect.minY))
        } else {
            becomeFirstResponder()
            let controller = UIMenuController.shared
            controller.menuItems = [UIMenuItem(title: copyRawMenuTitle, action: #selector(zl_copyRawText(_:)))]
            if menuHideObserver == nil {
                menuHideObserver = NotificationCenter.default.addObserver(
                    forName: UIMenuController.didHideMenuNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.selectionMenuDidHide()
                }
            }
            controller.showMenu(from: self, rect: rect)
        }
    }

    func hideSelectionMenu() {
        if #available(iOS 16.0, *) {
            (selectionEditMenu as? ZLSelectionEditMenu)?.dismiss()
        } else if isFirstResponder {
            UIMenuController.shared.hideMenu(from: self)
        }
    }

    /// 菜单关闭：点了「全选」则重新弹出；拖动拖柄时保留选中；其他情况（复制后、点击别处）取消选中
    func selectionMenuDidHide() {
        if reshowsSelectionMenu {
            reshowsSelectionMenu = false
            DispatchQueue.main.async { [weak self] in self?.showSelectionMenu() }
            return
        }
        guard !isAdjustingSelection, selectionAnchor == nil else { return }
        clearSelection()
    }
}

// MARK: - iOS 16+ 菜单

@available(iOS 16.0, *)
final class ZLSelectionEditMenu: NSObject, UIEditMenuInteractionDelegate {
    private weak var label: ZLRichLabel?
    /// UIEditMenuInteraction 的 delegate 只能在初始化时传入
    private lazy var interaction = UIEditMenuInteraction(delegate: self)
    private var isPresented = false

    init(label: ZLRichLabel) {
        self.label = label
        super.init()
        label.addInteraction(interaction)
    }

    func present(at point: CGPoint) {
        interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
        isPresented = true
    }

    func dismiss() {
        guard isPresented else { return }
        interaction.dismissMenu()
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let label = label, label.hasSelection else { return nil }
        var actions: [UIMenuElement] = [
            UIAction(title: label.copyMenuTitle) { [weak label] _ in label?.copySelection(raw: false) },
            UIAction(title: label.copyRawMenuTitle) { [weak label] _ in label?.copySelection(raw: true) },
        ]
        if label.selectedRange.length < label.contentDisplayLength {
            actions.append(UIAction(title: label.selectAllMenuTitle) { [weak label] _ in
                label?.reshowsSelectionMenu = true
                label?.selectAllText()
            })
        }
        return UIMenu(children: actions)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        return label?.selectionBoundingRect ?? .null
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration,
                             animator: UIEditMenuInteractionAnimating) {
        isPresented = false
        animator.addCompletion { [weak self] in
            self?.label?.selectionMenuDidHide()
        }
    }
}

// MARK: - 拖柄

/// 拖柄手势优先于外层 UIScrollView 的滚动：按在拖柄上拖动时调整选中范围而不是滚动
final class ZLSelectionHandlePanDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = ZLSelectionHandlePanDelegate()

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        return other.view is UIScrollView
    }
}

/// 选中范围两端的拖柄：竖线 + 圆点（开始拖柄圆点在上，结束拖柄在下），触摸区域比可见部分大
final class ZLSelectionHandleView: UIView {
    let isStart: Bool
    var color: UIColor = .systemBlue { didSet { setNeedsDisplay() } }
    /// 拖动开始时手指到光标中心的偏移
    var dragOffset: CGPoint = .zero

    private static let dot: CGFloat = 10
    private static let touchWidth: CGFloat = 28

    init(isStart: Bool) {
        self.isStart = isStart
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 按光标矩形摆放：竖线与光标重合，圆点在光标上方（开始）或下方（结束）
    func layout(caret: CGRect) {
        guard !caret.isNull else { return }
        let dot = ZLSelectionHandleView.dot
        let width = ZLSelectionHandleView.touchWidth
        let height = caret.height + dot + 8
        let y = isStart ? caret.minY - dot - 4 : caret.minY
        frame = CGRect(x: caret.minX - width / 2, y: y, width: width, height: height)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let dot = ZLSelectionHandleView.dot
        color.setFill()
        let midX = bounds.midX
        if isStart {
            UIBezierPath(ovalIn: CGRect(x: midX - dot / 2 + 1, y: 4, width: dot, height: dot)).fill()
            UIRectFill(CGRect(x: midX, y: 4 + dot / 2, width: 2, height: bounds.height - 8 - dot / 2))
        } else {
            UIRectFill(CGRect(x: midX, y: 0, width: 2, height: bounds.height - dot - 4))
            UIBezierPath(ovalIn: CGRect(x: midX - dot / 2 + 1, y: bounds.height - dot - 4, width: dot, height: dot)).fill()
        }
    }
}
