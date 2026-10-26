//
//  ZLRichLabel+Gesture.swift
//  ZLRichLabel
//
//  ZLRichLabel 的手势与点击：长按、双击、点击取消选中、内嵌 View 的触摸、按坐标查找命中
//

import UIKit
import CoreText

extension ZLRichLabel {

    @objc private func handleSelectionDismissTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        clearSelection()
    }

    func setupGestures() {
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

    func updateDoubleTapGesture() {
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

    @objc func handleRichLongPress(_ gesture: UILongPressGestureRecognizer) {
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
}

/// label 自己添加的手势的代理（基类的链接长按手势有自己的代理，这里单独处理）：
/// - 「展开」点击：只接收按钮区域内的触摸，其他位置交给 ZLAttributedLabel 处理链接
/// - 长按：有 `onLongPress` 或该位置的命中设置了 `ctx.onLongPress` 时才开始
final class RichGestureDelegate: NSObject, UIGestureRecognizerDelegate {
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
final class TagTapGestureRecognizer: UITapGestureRecognizer {
    var tapAction: (() -> Void)?
}
