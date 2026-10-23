//
//  ZLRichDefines.swift
//  ZLRichLabel
//
//  基础类型：文本样式、自定义 View（Widget）配置
//

import UIKit

/// 文本样式（等价于 Flutter 的 TextStyle），后设置的会覆盖前面的（merge）
public typealias HTagTextStyle = [NSAttributedString.Key: Any]

/// 自定义 View 相对于文字的位置
@objc public enum HTagWidgetPosition: Int {
    /// 用 View 替换文字
    case replace
    /// View 显示在文字前面（文字保留）
    case before
    /// View 显示在文字后面（文字保留）
    case after
}

/// 自定义 View 与文字的对齐方式（对应 Flutter 的 PlaceholderAlignment）
@objc public enum HTagWidgetAlignment: Int {
    /// View 底部与基线对齐
    case baseline
    /// View 底部与基线对齐（同 baseline）
    case aboveBaseline
    /// View 顶部与基线对齐
    case belowBaseline
    /// View 顶部与文字顶部（ascender）对齐
    case top
    /// View 底部与文字底部（descender）对齐
    case bottom
    /// View 中心与文字中心对齐
    case middle
}

/// 内嵌自定义 View 配置
@objcMembers
public final class HTagWidget: NSObject {
    /// 要展示的 View
    public let view: UIView
    /// View 尺寸，为 `.zero` 时自动计算（systemLayoutSizeFitting / sizeThatFits / frame）
    public let size: CGSize
    /// View 位置，默认替换文字（由使用方解释，例如 `ZLTagRichLabel` 的 tagWidgetBuilder）
    public let position: HTagWidgetPosition
    /// 与文字的对齐方式
    public let alignment: HTagWidgetAlignment
    /// 是否自动给 View 加点击（点击时触发所在规则命中的 onTap）；View 内部自己处理点击时设为 false
    public let tappable: Bool

    /// - Parameter size: View 尺寸，`.zero`（默认）时自动计算
    /// Objective-C：`[[HTagWidget alloc] initWithView:size:position:alignment:tappable:]`
    /// 或便捷方法 `[HTagWidget widgetWithView:size:position:]`
    public init(view: UIView,
                size: CGSize = .zero,
                position: HTagWidgetPosition = .replace,
                alignment: HTagWidgetAlignment = .middle,
                tappable: Bool = true) {
        self.view = view
        self.size = size
        self.position = position
        self.alignment = alignment
        self.tappable = tappable
        super.init()
    }

    /// 便捷构造（middle 对齐、可点击），主要给 Objective-C 使用
    @objc(widgetWithView:size:position:)
    public static func widget(view: UIView, size: CGSize, position: HTagWidgetPosition) -> HTagWidget {
        return HTagWidget(view: view, size: size, position: position)
    }
}
