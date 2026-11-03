//
//  ZLBracketLabel.swift
//  ZLRichLabel
//
//  用 `[` `]` 包裹标签的 `ZLTagRichLabel`：`[h1]用户协议[/h1]`、`[h2]隐私政策[h2/]`。
//  除了开始 / 结束符号，其他用法（样式、点击、属性、嵌套、自闭合、容错）与 `ZLTagRichLabel` 完全一致。
//

import UIKit

/// 标签写作 `[h1]文字[/h1]` 的标签 Label
///
/// ```swift
/// let label = ZLBracketLabel(frame: .zero)
/// label.tagStyles = ["h1": .color(.systemBlue).underline()]
/// label.onTagTap = { info in print(info.name, info.text) }
/// label.text = "同意 [h1]用户协议[/h1] 和 [h2]隐私政策[/h2]"
/// ```
///
/// Objective-C：`ZLBracketLabel *label = [[ZLBracketLabel alloc] initWithFrame:CGRectZero];`
@objcMembers
open class ZLBracketLabel: ZLTagRichLabel {

    /// 默认的开始符号 `[`
    public static let defaultOpenDelimiter = "["
    /// 默认的结束符号 `]`
    public static let defaultCloseDelimiter = "]"

    public override init(frame: CGRect) {
        super.init(frame: frame)
        applyBracketDelimiters()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyBracketDelimiters()
    }

    private func applyBracketDelimiters() {
        tagOpenDelimiter = ZLBracketLabel.defaultOpenDelimiter
        tagCloseDelimiter = ZLBracketLabel.defaultCloseDelimiter
    }
}
