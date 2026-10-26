//
//  ZLTextStyle+Chain.swift
//  ZLRichLabel
//
//  ZLTextStyle 的链式配置。
//
//  Swift：ZLTextStyle 就是 `[NSAttributedString.Key: Any]`，所有接收 ZLTextStyle 的地方
//  （style / highlightStyle / tagStyle / tagStyles / ctx.addAttributes / ctx.highlightStyle /
//  ctx.setText(attributes:) / NSAttributedString(string:attributes:) …）都可以直接链式书写：
//
//      label.style = .font(.systemFont(ofSize: 15)).color(.label).lineSpacing(4)
//      label.tagStyles = ["h1": .boldFont(16).color(.systemBlue).underline()]
//      ctx.addAttributes(.color(.systemPurple).capsule(.systemPurple))
//      let merged = base.adding(.color(.red))       // 在已有样式上继续配置
//
//  每一步都返回新的样式（值类型），不会修改原来的样式。
//
//  Objective-C：使用 ZLTextStyleMaker
//
//      label.style = ZLTextStyleMaker.make.font([UIFont systemFontOfSize:15]).color(UIColor.labelColor).style;
//

import UIKit

// MARK: - Swift：ZLTextStyle 链式配置

public extension Dictionary where Key == NSAttributedString.Key, Value == Any {

    // MARK: 通用

    /// 设置任意属性；value 为 nil 时移除该属性
    func set(_ key: NSAttributedString.Key, _ value: Any?) -> ZLTextStyle {
        var style = self
        style[key] = value
        return style
    }

    /// 合并另一个样式（另一个样式中的同名属性覆盖当前的）
    func adding(_ other: ZLTextStyle?) -> ZLTextStyle {
        guard let other = other else { return self }
        return merging(other) { _, new in new }
    }

    /// 移除属性
    func removing(_ keys: NSAttributedString.Key...) -> ZLTextStyle {
        var style = self
        keys.forEach { style[$0] = nil }
        return style
    }

    // MARK: 字体

    func font(_ font: UIFont) -> ZLTextStyle { set(.font, font) }

    /// 系统字体
    func systemFont(_ size: CGFloat, weight: UIFont.Weight = .regular) -> ZLTextStyle {
        font(.systemFont(ofSize: size, weight: weight))
    }

    /// 系统粗体
    func boldFont(_ size: CGFloat) -> ZLTextStyle { font(.boldSystemFont(ofSize: size)) }

    /// 等宽字体
    func monospacedFont(_ size: CGFloat, weight: UIFont.Weight = .regular) -> ZLTextStyle {
        font(.monospacedSystemFont(ofSize: size, weight: weight))
    }

    /// 只改字号，保留当前字体（没有字体时用 17pt 系统字体）
    func fontSize(_ size: CGFloat) -> ZLTextStyle { font(currentFont.withSize(size)) }

    /// 当前字体加粗（保留字号和字体族）
    func bold() -> ZLTextStyle { addingTraits(.traitBold) }

    /// 当前字体斜体（保留字号和字体族）
    func italic() -> ZLTextStyle { addingTraits(.traitItalic) }

    // MARK: 颜色与装饰

    /// 文字颜色
    func color(_ color: UIColor) -> ZLTextStyle { set(.foregroundColor, color) }

    /// 文字背景色（矩形，按行绘制）。圆角胶囊请用 `background(_:)` / `capsule(_:)`
    func backgroundColor(_ color: UIColor) -> ZLTextStyle { set(.backgroundColor, color) }

    /// 下划线；color 为 nil 时与文字同色
    func underline(_ style: NSUnderlineStyle = .single, color: UIColor? = nil) -> ZLTextStyle {
        set(.underlineStyle, style.rawValue).set(.underlineColor, color ?? self[.underlineColor])
    }

    /// 删除线；color 为 nil 时与文字同色
    func strikethrough(_ style: NSUnderlineStyle = .single, color: UIColor? = nil) -> ZLTextStyle {
        set(.strikethroughStyle, style.rawValue).set(.strikethroughColor, color ?? self[.strikethroughColor])
    }

    /// 字间距
    func kern(_ value: CGFloat) -> ZLTextStyle { set(.kern, value) }

    /// 基线偏移（正数上移）
    func baselineOffset(_ value: CGFloat) -> ZLTextStyle { set(.baselineOffset, value) }

    /// 倾斜（0 为不倾斜，正数向右）
    func obliqueness(_ value: CGFloat) -> ZLTextStyle { set(.obliqueness, value) }

    /// 横向拉伸（0 为不拉伸）
    func expansion(_ value: CGFloat) -> ZLTextStyle { set(.expansion, value) }

    /// 描边；width 为正数时只描边（空心），负数时描边并填充
    func stroke(_ color: UIColor, width: CGFloat) -> ZLTextStyle {
        set(.strokeColor, color).set(.strokeWidth, width)
    }

    /// 文字阴影
    func shadow(_ color: UIColor, offset: CGSize = CGSize(width: 0, height: 1), blur: CGFloat = 2) -> ZLTextStyle {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowOffset = offset
        shadow.shadowBlurRadius = blur
        return set(.shadow, shadow)
    }

    /// 链接（ZLAttributedLabel 会识别 `.link` 属性生成可点击链接）
    func link(_ url: Any) -> ZLTextStyle { set(.link, url) }

    // MARK: ZLRichLabel 装饰

    /// 圆角背景 / 边框 / 内边距（ZLRichLabel 绘制）
    func background(_ background: ZLTextBackground) -> ZLTextStyle { set(.zlBackground, background) }

    /// 浅色胶囊背景（`ZLTextBackground.capsule`）
    func capsule(_ color: UIColor) -> ZLTextStyle { background(.capsule(color)) }

    /// 行内代码背景（`ZLTextBackground.code`）
    func codeBackground() -> ZLTextStyle { background(.code) }

    /// 渐变文字
    func gradient(_ gradient: ZLTextGradient) -> ZLTextStyle { set(.zlGradient, gradient) }

    /// 渐变文字：默认从左到右，vertical 为 true 时从上到下
    func gradient(colors: [UIColor], vertical: Bool = false) -> ZLTextStyle {
        gradient(vertical
                 ? ZLTextGradient(colors: colors, startPoint: CGPoint(x: 0.5, y: 0), endPoint: CGPoint(x: 0.5, y: 1))
                 : ZLTextGradient(colors: colors))
    }

    // MARK: 段落（在已有段落样式的基础上修改，不会覆盖其他段落属性）

    /// 自定义段落样式
    func paragraph(_ configure: (NSMutableParagraphStyle) -> Void) -> ZLTextStyle {
        let paragraph = ((self[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        configure(paragraph)
        return set(.paragraphStyle, paragraph.copy())
    }

    func lineSpacing(_ value: CGFloat) -> ZLTextStyle { paragraph { $0.lineSpacing = value } }
    func paragraphSpacing(_ value: CGFloat) -> ZLTextStyle { paragraph { $0.paragraphSpacing = value } }
    func paragraphSpacingBefore(_ value: CGFloat) -> ZLTextStyle { paragraph { $0.paragraphSpacingBefore = value } }
    func alignment(_ value: NSTextAlignment) -> ZLTextStyle { paragraph { $0.alignment = value } }
    func lineBreakMode(_ value: NSLineBreakMode) -> ZLTextStyle { paragraph { $0.lineBreakMode = value } }
    func firstLineHeadIndent(_ value: CGFloat) -> ZLTextStyle { paragraph { $0.firstLineHeadIndent = value } }
    func headIndent(_ value: CGFloat) -> ZLTextStyle { paragraph { $0.headIndent = value } }
    func tailIndent(_ value: CGFloat) -> ZLTextStyle { paragraph { $0.tailIndent = value } }
    func lineHeightMultiple(_ value: CGFloat) -> ZLTextStyle { paragraph { $0.lineHeightMultiple = value } }
    func writingDirection(_ value: NSWritingDirection) -> ZLTextStyle { paragraph { $0.baseWritingDirection = value } }

    /// 固定行高（最小 = 最大）
    func lineHeight(_ value: CGFloat) -> ZLTextStyle {
        paragraph { $0.minimumLineHeight = value; $0.maximumLineHeight = value }
    }

    // MARK: 内部

    private var currentFont: UIFont { (self[.font] as? UIFont) ?? .systemFont(ofSize: 17) }

    private func addingTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> ZLTextStyle {
        let font = currentFont
        let combined = font.fontDescriptor.symbolicTraits.union(traits)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(combined) else { return self }
        return self.font(UIFont(descriptor: descriptor, size: font.pointSize))
    }
}

// MARK: - Swift：链式起点（可以直接写 `.font(...)`、`.color(...)` 开始）

public extension Dictionary where Key == NSAttributedString.Key, Value == Any {

    static func set(_ key: NSAttributedString.Key, _ value: Any?) -> ZLTextStyle { ZLTextStyle().set(key, value) }

    static func font(_ font: UIFont) -> ZLTextStyle { ZLTextStyle().font(font) }
    static func systemFont(_ size: CGFloat, weight: UIFont.Weight = .regular) -> ZLTextStyle {
        ZLTextStyle().systemFont(size, weight: weight)
    }
    static func boldFont(_ size: CGFloat) -> ZLTextStyle { ZLTextStyle().boldFont(size) }
    static func monospacedFont(_ size: CGFloat, weight: UIFont.Weight = .regular) -> ZLTextStyle {
        ZLTextStyle().monospacedFont(size, weight: weight)
    }
    static func fontSize(_ size: CGFloat) -> ZLTextStyle { ZLTextStyle().fontSize(size) }
    static func bold() -> ZLTextStyle { ZLTextStyle().bold() }
    static func italic() -> ZLTextStyle { ZLTextStyle().italic() }

    static func color(_ color: UIColor) -> ZLTextStyle { ZLTextStyle().color(color) }
    static func backgroundColor(_ color: UIColor) -> ZLTextStyle { ZLTextStyle().backgroundColor(color) }
    static func underline(_ style: NSUnderlineStyle = .single, color: UIColor? = nil) -> ZLTextStyle {
        ZLTextStyle().underline(style, color: color)
    }
    static func strikethrough(_ style: NSUnderlineStyle = .single, color: UIColor? = nil) -> ZLTextStyle {
        ZLTextStyle().strikethrough(style, color: color)
    }
    static func kern(_ value: CGFloat) -> ZLTextStyle { ZLTextStyle().kern(value) }
    static func baselineOffset(_ value: CGFloat) -> ZLTextStyle { ZLTextStyle().baselineOffset(value) }
    static func obliqueness(_ value: CGFloat) -> ZLTextStyle { ZLTextStyle().obliqueness(value) }
    static func expansion(_ value: CGFloat) -> ZLTextStyle { ZLTextStyle().expansion(value) }
    static func stroke(_ color: UIColor, width: CGFloat) -> ZLTextStyle { ZLTextStyle().stroke(color, width: width) }
    static func shadow(_ color: UIColor, offset: CGSize = CGSize(width: 0, height: 1), blur: CGFloat = 2) -> ZLTextStyle {
        ZLTextStyle().shadow(color, offset: offset, blur: blur)
    }
    static func link(_ url: Any) -> ZLTextStyle { ZLTextStyle().link(url) }

    static func background(_ background: ZLTextBackground) -> ZLTextStyle { ZLTextStyle().background(background) }
    static func capsule(_ color: UIColor) -> ZLTextStyle { ZLTextStyle().capsule(color) }
    static func codeBackground() -> ZLTextStyle { ZLTextStyle().codeBackground() }
    static func gradient(_ gradient: ZLTextGradient) -> ZLTextStyle { ZLTextStyle().gradient(gradient) }
    static func gradient(colors: [UIColor], vertical: Bool = false) -> ZLTextStyle {
        ZLTextStyle().gradient(colors: colors, vertical: vertical)
    }

    static func paragraph(_ configure: (NSMutableParagraphStyle) -> Void) -> ZLTextStyle {
        ZLTextStyle().paragraph(configure)
    }
    static func lineSpacing(_ value: CGFloat) -> ZLTextStyle { ZLTextStyle().lineSpacing(value) }
    static func paragraphSpacing(_ value: CGFloat) -> ZLTextStyle { ZLTextStyle().paragraphSpacing(value) }
    static func paragraphSpacingBefore(_ value: CGFloat) -> ZLTextStyle { ZLTextStyle().paragraphSpacingBefore(value) }
    static func alignment(_ value: NSTextAlignment) -> ZLTextStyle { ZLTextStyle().alignment(value) }
    static func lineBreakMode(_ value: NSLineBreakMode) -> ZLTextStyle { ZLTextStyle().lineBreakMode(value) }
    static func firstLineHeadIndent(_ value: CGFloat) -> ZLTextStyle { ZLTextStyle().firstLineHeadIndent(value) }
    static func headIndent(_ value: CGFloat) -> ZLTextStyle { ZLTextStyle().headIndent(value) }
    static func tailIndent(_ value: CGFloat) -> ZLTextStyle { ZLTextStyle().tailIndent(value) }
    static func lineHeightMultiple(_ value: CGFloat) -> ZLTextStyle { ZLTextStyle().lineHeightMultiple(value) }
    static func writingDirection(_ value: NSWritingDirection) -> ZLTextStyle { ZLTextStyle().writingDirection(value) }
    static func lineHeight(_ value: CGFloat) -> ZLTextStyle { ZLTextStyle().lineHeight(value) }
}

// MARK: - Objective-C：ZLTextStyleMaker

/// Objective-C 的链式样式配置（Swift 直接用 ZLTextStyle 的链式方法即可）
///
///     label.style = ZLTextStyleMaker.make
///         .font([UIFont systemFontOfSize:15])
///         .color(UIColor.labelColor)
///         .lineSpacing(4)
///         .style;
///     label.tagStyles = @{@"h1": ZLTextStyleMaker.make.boldFont(16).color(UIColor.systemBlueColor).underline().style};
///     [ctx addAttributes:ZLTextStyleMaker.make.color(kPurple).capsule(kPurple).style];
///
/// 每一步修改的是同一个 maker，最后通过 `.style` 取出不可变字典
@objcMembers
public final class ZLTextStyleMaker: NSObject {

    /// 配置结果
    public private(set) var style: ZLTextStyle

    public init(style: ZLTextStyle) {
        self.style = style
        super.init()
    }

    public override convenience init() { self.init(style: [:]) }

    /// 空样式开始：`ZLTextStyleMaker.make.font(...).style`
    public static var make: ZLTextStyleMaker { ZLTextStyleMaker() }

    /// 在已有样式的基础上继续配置：`[ZLTextStyleMaker makeWithStyle:label.style].color(...).style`
    @objc(makeWithStyle:)
    public static func make(with style: ZLTextStyle?) -> ZLTextStyleMaker { ZLTextStyleMaker(style: style ?? [:]) }

    private func apply(_ change: (ZLTextStyle) -> ZLTextStyle) -> ZLTextStyleMaker {
        style = change(style)
        return self
    }

    // 通用
    public var set: (NSAttributedString.Key, Any?) -> ZLTextStyleMaker { { k, v in self.apply { $0.set(k, v) } } }
    public var adding: (ZLTextStyle?) -> ZLTextStyleMaker { { s in self.apply { $0.adding(s) } } }
    public var remove: (NSAttributedString.Key) -> ZLTextStyleMaker { { k in self.apply { $0.removing(k) } } }

    // 字体
    public var font: (UIFont) -> ZLTextStyleMaker { { f in self.apply { $0.font(f) } } }
    public var systemFont: (CGFloat) -> ZLTextStyleMaker { { s in self.apply { $0.systemFont(s) } } }
    public var systemFontWeight: (CGFloat, UIFont.Weight) -> ZLTextStyleMaker {
        { s, w in self.apply { $0.systemFont(s, weight: w) } }
    }
    public var boldFont: (CGFloat) -> ZLTextStyleMaker { { s in self.apply { $0.boldFont(s) } } }
    public var monospacedFont: (CGFloat) -> ZLTextStyleMaker { { s in self.apply { $0.monospacedFont(s) } } }
    public var fontSize: (CGFloat) -> ZLTextStyleMaker { { s in self.apply { $0.fontSize(s) } } }
    public var bold: () -> ZLTextStyleMaker { { self.apply { $0.bold() } } }
    public var italic: () -> ZLTextStyleMaker { { self.apply { $0.italic() } } }

    // 颜色与装饰
    public var color: (UIColor) -> ZLTextStyleMaker { { c in self.apply { $0.color(c) } } }
    public var backgroundColor: (UIColor) -> ZLTextStyleMaker { { c in self.apply { $0.backgroundColor(c) } } }
    /// 单线下划线，与文字同色
    public var underline: () -> ZLTextStyleMaker { { self.apply { $0.underline() } } }
    /// 下划线样式 + 颜色（颜色可为 nil）
    public var underlineStyle: (NSUnderlineStyle, UIColor?) -> ZLTextStyleMaker {
        { s, c in self.apply { $0.underline(s, color: c) } }
    }
    /// 单线删除线，与文字同色
    public var strikethrough: () -> ZLTextStyleMaker { { self.apply { $0.strikethrough() } } }
    public var strikethroughStyle: (NSUnderlineStyle, UIColor?) -> ZLTextStyleMaker {
        { s, c in self.apply { $0.strikethrough(s, color: c) } }
    }
    public var kern: (CGFloat) -> ZLTextStyleMaker { { v in self.apply { $0.kern(v) } } }
    public var baselineOffset: (CGFloat) -> ZLTextStyleMaker { { v in self.apply { $0.baselineOffset(v) } } }
    public var obliqueness: (CGFloat) -> ZLTextStyleMaker { { v in self.apply { $0.obliqueness(v) } } }
    public var expansion: (CGFloat) -> ZLTextStyleMaker { { v in self.apply { $0.expansion(v) } } }
    public var stroke: (UIColor, CGFloat) -> ZLTextStyleMaker { { c, w in self.apply { $0.stroke(c, width: w) } } }
    public var shadow: (UIColor, CGSize, CGFloat) -> ZLTextStyleMaker {
        { c, o, b in self.apply { $0.shadow(c, offset: o, blur: b) } }
    }
    public var link: (Any) -> ZLTextStyleMaker { { u in self.apply { $0.link(u) } } }

    // ZLRichLabel 装饰
    public var background: (ZLTextBackground) -> ZLTextStyleMaker { { b in self.apply { $0.background(b) } } }
    public var capsule: (UIColor) -> ZLTextStyleMaker { { c in self.apply { $0.capsule(c) } } }
    public var codeBackground: () -> ZLTextStyleMaker { { self.apply { $0.codeBackground() } } }
    public var gradient: (ZLTextGradient) -> ZLTextStyleMaker { { g in self.apply { $0.gradient(g) } } }
    /// 从左到右的渐变
    public var gradientColors: ([UIColor]) -> ZLTextStyleMaker { { c in self.apply { $0.gradient(colors: c) } } }
    /// 从上到下的渐变
    public var verticalGradientColors: ([UIColor]) -> ZLTextStyleMaker {
        { c in self.apply { $0.gradient(colors: c, vertical: true) } }
    }

    // 段落
    public var paragraph: ((NSMutableParagraphStyle) -> Void) -> ZLTextStyleMaker {
        { block in self.apply { $0.paragraph(block) } }
    }
    public var lineSpacing: (CGFloat) -> ZLTextStyleMaker { { v in self.apply { $0.lineSpacing(v) } } }
    public var paragraphSpacing: (CGFloat) -> ZLTextStyleMaker { { v in self.apply { $0.paragraphSpacing(v) } } }
    public var paragraphSpacingBefore: (CGFloat) -> ZLTextStyleMaker {
        { v in self.apply { $0.paragraphSpacingBefore(v) } }
    }
    public var alignment: (NSTextAlignment) -> ZLTextStyleMaker { { v in self.apply { $0.alignment(v) } } }
    public var lineBreakMode: (NSLineBreakMode) -> ZLTextStyleMaker { { v in self.apply { $0.lineBreakMode(v) } } }
    public var firstLineHeadIndent: (CGFloat) -> ZLTextStyleMaker { { v in self.apply { $0.firstLineHeadIndent(v) } } }
    public var headIndent: (CGFloat) -> ZLTextStyleMaker { { v in self.apply { $0.headIndent(v) } } }
    public var tailIndent: (CGFloat) -> ZLTextStyleMaker { { v in self.apply { $0.tailIndent(v) } } }
    public var lineHeightMultiple: (CGFloat) -> ZLTextStyleMaker { { v in self.apply { $0.lineHeightMultiple(v) } } }
    public var lineHeight: (CGFloat) -> ZLTextStyleMaker { { v in self.apply { $0.lineHeight(v) } } }
    public var writingDirection: (NSWritingDirection) -> ZLTextStyleMaker {
        { v in self.apply { $0.writingDirection(v) } }
    }
}
