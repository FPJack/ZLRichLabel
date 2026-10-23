//
//  ZLRichLabel+Deprecated.swift
//  ZLRichLabel
//
//  旧名字的过渡：统一使用 ZL 前缀后，旧的类型名 / 属性名仍可在 Swift 中使用（编译时提示改为新名字）。
//  Objective-C 不支持类型别名，请直接使用新类名。
//

import UIKit

// MARK: - 基础类型

@available(*, deprecated, renamed: "ZLTextStyle")
public typealias HTagTextStyle = ZLTextStyle

@available(*, deprecated, renamed: "ZLRichWidget")
public typealias HTagWidget = ZLRichWidget

@available(*, deprecated, renamed: "ZLRichWidgetPosition")
public typealias HTagWidgetPosition = ZLRichWidgetPosition

@available(*, deprecated, renamed: "ZLRichWidgetAlignment")
public typealias HTagWidgetAlignment = ZLRichWidgetAlignment

// MARK: - 规则

@available(*, deprecated, renamed: "ZLRichRule")
public typealias TagRichRule = ZLRichRule

@available(*, deprecated, renamed: "ZLRichMatch")
public typealias TagRichMatch = ZLRichMatch

@available(*, deprecated, renamed: "ZLRichRuleContext")
public typealias TagRichRuleContext = ZLRichRuleContext

@available(*, deprecated, renamed: "ZLRichParser")
public typealias TagRichParser = ZLRichParser

// MARK: - 标签

@available(*, deprecated, renamed: "ZLTagInfo")
public typealias HTagInfo = ZLTagInfo

@available(*, deprecated, renamed: "ZLTagSegment")
public typealias HTagSegment = ZLTagSegment

@available(*, deprecated, renamed: "ZLTagParser")
public typealias HTagParser = ZLTagParser

@available(*, deprecated, renamed: "ZLTagStyleBuilder")
public typealias HTagStyleBuilder = ZLTagStyleBuilder

@available(*, deprecated, renamed: "ZLTagSpanBuilder")
public typealias HTagSpanBuilder = ZLTagSpanBuilder

@available(*, deprecated, renamed: "ZLTagWidgetBuilder")
public typealias HTagWidgetBuilder = ZLTagWidgetBuilder

@available(*, deprecated, renamed: "ZLTagTapCallback")
public typealias HTagTapCallback = ZLTagTapCallback

// MARK: - ZLTagRichLabel 属性

public extension ZLTagRichLabel {

    @available(*, deprecated, renamed: "tagRuleName")
    static var hTagRuleName: String { return tagRuleName }

    @available(*, deprecated, renamed: "tagPriority")
    var hTagPriority: Int {
        get { return tagPriority }
        set { tagPriority = newValue }
    }

    @available(*, deprecated, renamed: "parsesTags")
    var parsesHTags: Bool {
        get { return parsesTags }
        set { parsesTags = newValue }
    }
}
