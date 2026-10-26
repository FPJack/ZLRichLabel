# ZLRichLabel

[![Version](https://img.shields.io/cocoapods/v/ZLRichLabel.svg?style=flat)](https://cocoapods.org/pods/ZLRichLabel)
[![License](https://img.shields.io/cocoapods/l/ZLRichLabel.svg?style=flat)](https://cocoapods.org/pods/ZLRichLabel)
[![Platform](https://img.shields.io/cocoapods/p/ZLRichLabel.svg?style=flat)](https://cocoapods.org/pods/ZLRichLabel)

**ZLRichLabel 是一个 iOS 富文本 Label：用正则规则（或内置的 `<h1>…</h1>` 标签）从普通字符串里识别出关键内容，再由你决定每段内容怎么显示、点了做什么。**

一行带标记的字符串，就能渲染出带样式、图片、自定义 View、可点击、支持按下高亮的富文本，不需要手动拼 `NSAttributedString`、计算点击区域或摆放子 View。

适用场景：

- **协议 / 隐私政策勾选文案**：`我已阅读并同意<h1>用户协议</h1>和<h2>隐私政策</h2>`，不同标签不同颜色、不同跳转
- **社交内容**：@提及、#话题#、链接识别与点击，链接替换为「🔗网页链接」
- **表情与模板**：`[smile]` 替换为图片，`{{name}}` 替换为变量值
- **行内控件**：文字中嵌入按钮、徽章、勾选框、计数器等任意 `UIView`，尺寸变化后自动重新排版
- **多语言**：阿拉伯语 / 希伯来语等 RTL 文本与双向混排
- **轻量标记**：简易 Markdown（加粗、删除线、行内代码），或 `<b>`、`<color value="#f00">`、`<a href="…">` 这类可嵌套的 HTML 风格标签

Swift 与 Objective-C 均可使用，基于 CoreText 自行实现绘制，无第三方依赖，分为三层：

| 类 | 作用 |
| --- | --- |
| `ZLAttributedLabel` | 底层富文本 Label（继承 `UILabel`）。CoreText 绘制，支持内边距、垂直对齐、行数限制与自定义截断符、`.backgroundColor` / 删除线绘制；链接（手动添加、`.link` 属性、`NSDataDetector` 识别），默认 / 按下 / 失活样式，点击 / 长按回调与 delegate，扩大点击热区；尺寸计算与缓存；VoiceOver 下每个链接可单独聚焦和点击 |
| `ZLRichLabel` | 基类。用**正则规则**解析文本，命中内容交给外部渲染（样式 / 替换文字 / 图片 / 自定义 View / 点击 / 按下高亮），重叠时按优先级取舍 |
| `ZLTagRichLabel` | 继承 `ZLRichLabel`。内置标签规则：默认识别 `<h>`、`<h1>`、`<h2>` …，也可以识别任意标签名、读取标签属性、支持嵌套；按标签名区分样式、按下高亮与点击，常用于「用户协议 / 隐私政策」之类的高亮文案 |

```text
"I agree to the <h1>User Agreement</h1> and <h2>Privacy Policy</h2>. cc @alice"
                 ^^^^^^^^^^^^^^^^^^^^^^^     ^^^^^^^^^^^^^^^^^^^^^^^      ^^^^^^
                 ZLTagRichLabel 内置标签      ZLTagRichLabel 内置标签       自定义规则
```

## 功能

- 正则规则：任意 `NSRegularExpression` / `NSDataDetector`，支持捕获组、命名捕获组
- 规则优先级：命中范围重叠时按 `priority` → 位置 → 长度 → 添加顺序取舍
- 命中内容完全由外部决定：加属性、替换文字、插入 `NSTextAttachment` 图片、插入任意 `UIView`
- 自定义 View 尺寸 / 内容变化后自动重新排版
- 点击与按下高亮：整段可点击（包括其中的图片 / View），可按规则 / 标签名设置不同的高亮样式
- `<h>` 标签：`<h>`、`<h1>`…`<hN>`，`</h1>` 和 `<h1/>` 两种闭合写法，不区分大小写；按标签名区分样式与点击；可替换为自定义 View
- 通用标签：可识别任意标签名（`<b>`、`<a href="…">`、`<color value="#f00">`），解析标签属性，支持嵌套（内层继承外层样式、点击内层优先）和自闭合标签（`<br/>`、`<icon name="star"/>`）
- 容错：开闭不匹配、未闭合的标签原样显示，不影响后面的标签
- 胶囊背景（圆角背景 / 边框 / 内边距，适合 #话题#、`code`、标签徽章）与渐变文字，由 label 自己绘制，跨行时逐行绘制
- 多行截断（自定义省略符）、Auto Layout 自适应高度
- 展开 / 收起：截断时末尾显示可点击的「… 全文」，展开后显示「收起」
- 长按（整体 / 按命中 / 按标签）、双击、扩大点击热区，可按坐标查询字符和命中
- 选中复制：长按选词、拖柄调整范围，可复制展示文字或对应的原文
- 渲染缓存 + 排版缓存：改样式 / 追加文字时只重新处理变化的部分
- RTL：阿拉伯语 / 希伯来语等从右到左文本自动右对齐，支持双向混排
- 深色模式自动重新渲染；可选支持 Dynamic Type（系统文字大小）
- SwiftUI：`ZLRichText` 封装，高度自适应（支持 `.lineLimit`、展开 / 收起等内部变化）
- Objective-C 可用

## 环境要求

- iOS 13.0+（见 podspec / Package.swift；Example 工程使用 iOS 15.0）
- Swift 5.0
- 无第三方依赖（只依赖 UIKit、CoreText）

## 安装

### CocoaPods

```ruby
pod 'ZLRichLabel'
```

### Swift Package Manager

Xcode › File › Add Package Dependencies…，输入仓库地址：

```text
https://github.com/FPJack/ZLRichLabel.git
```

或在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/FPJack/ZLRichLabel.git", from: "3.0.0"),
],
targets: [
    .target(name: "YourTarget", dependencies: ["ZLRichLabel"]),
]
```

使用方式与 CocoaPods 相同：Swift 中 `import ZLRichLabel`，Objective-C 中 `@import ZLRichLabel;`。

源码结构：

```text
ZLRichLabel/Classes/
├── ZLAttributedLabel.swift                底层富文本 Label：属性定义、文字设置、初始化
├── ZLAttributedLabel+Layout.swift         排版：字号自适应、textRect / sizeThatFits、字符定位、截断
├── ZLAttributedLabel+Drawing.swift        绘制：CoreText 绘制文字，补充背景色与删除线
├── ZLAttributedLabel+Link.swift           链接与触摸：添加 / 查找链接、自动识别、按下样式、点击与长按
├── ZLAttributedLabel+Accessibility.swift  无障碍：每个链接单独可聚焦、可激活
├── ZLRichDefines.swift    样式类型 ZLTextStyle、内嵌 View 配置 ZLRichWidget
├── ZLRichRule.swift       ZLRichRule / ZLRichMatch / ZLRichRuleContext / ZLRichParser
├── ZLRichLabel.swift      基类：属性定义、规则解析、渲染与缓存、内嵌 View（附件）
├── ZLRichLabel+Layout.swift     布局：自适应高度、RTL 对齐、内嵌 View 的位置
├── ZLRichLabel+Expand.swift     展开 / 收起：实际行数、按钮样式与位置、按钮点击
├── ZLRichLabel+Gesture.swift    手势与点击：长按、双击、内嵌 View 的触摸、按坐标查找命中
├── ZLRichLabel+Selection.swift  选中复制：选中范围、拖柄、菜单、展示文字与原文的对应
├── ZLRichLabel+Decoration.swift 胶囊背景 / 渐变文字的属性与绘制
├── ZLRichText.swift      SwiftUI 封装（UIViewRepresentable），高度自适应
├── ZLTagParser.swift      标签解析：通用标签（任意标签名、属性、嵌套、自闭合、容错）与 <h> 标签
└── ZLTagRichLabel.swift   标签子类、ZLTagInfo、ZLTagSegment
```

## 快速开始

### 标签高亮：ZLTagRichLabel

```swift
import ZLRichLabel

let label = ZLTagRichLabel(frame: .zero)
label.numberOfLines = 0
label.update { v in   // 批量修改，只渲染一次
    v.style = [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.gray]   // 普通文本
    v.tagStyle = [.foregroundColor: UIColor.systemBlue]                                 // 所有标签
    v.tagStyles = ["h2": [.foregroundColor: UIColor.systemRed]]                         // 按标签名
    v.tagHighlightStyle = [.backgroundColor: UIColor(white: 0.9, alpha: 1)]             // 按下高亮
    v.tagTapHandlers = [
        "h1": { _ in openAgreement() },
        "h2": { _ in openPrivacy() },
    ]
    v.onTagTap = { info in print(info.name, info.text) }   // 没有对应 handler 的标签走这里
    v.text = "I agree to the <h1>User Agreement</h1> and <h2>Privacy Policy</h2>."
}
```

### 自定义规则：ZLRichLabel

不需要 `<h>` 标签时直接用基类：

```swift
let label = ZLRichLabel(frame: .zero)
label.numberOfLines = 0
label.update { v in
    v.style = [.font: UIFont.systemFont(ofSize: 15)]

    // @提及
    try? v.addRule(name: "mention", pattern: "@\\w+", priority: 10) { ctx in
        ctx.addAttributes([.foregroundColor: UIColor.systemPurple])
        ctx.onTap = { match in print("open", match.text) }   // 参数是这次点击的命中
    }

    // 链接：NSDataDetector 也可以作为规则，替换展示文字
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        v.addRule(ZLRichRule(name: "link", regex: detector, priority: 10) { ctx in
            ctx.setText("🔗网页链接", attributes: [.foregroundColor: UIColor.systemBlue])
            ctx.onTap = { match in
                if let url = match.result.url { UIApplication.shared.open(url) }
            }
        })
    }

    v.text = "Hi @alice, see https://www.apple.com"
}
```

### 富文本与链接：ZLAttributedLabel

不需要规则解析、只想显示 `NSAttributedString` 并添加链接时，直接用底层 Label：

```swift
let label = ZLAttributedLabel(frame: .zero)
label.numberOfLines = 0
label.textInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
label.text = "阅读并同意《用户协议》，或访问 https://www.apple.com"
label.enabledTextCheckingTypes = NSTextCheckingResult.CheckingType.link.rawValue   // 自动识别网址
label.addLink(range: (label.text! as NSString).range(of: "《用户协议》")) { _, _ in openAgreement() }
label.delegate = self   // ZLAttributedLabelDelegate：URL 链接 / 识别结果的点击与长按
```

## 自定义规则

### 创建规则

```swift
// 正则字符串（非法时抛错）
let rule = try ZLRichRule(name: "topic", pattern: "#[^#\\s]+#", options: [], priority: 5) { ctx in ... }

// 已有的 NSRegularExpression / NSDataDetector
let rule = ZLRichRule(name: "link", regex: detector, priority: 10) { ctx in ... }

label.addRule(rule)                // 同名规则会被替换
label.removeRule(named: "topic")
label.removeAllRules()             // 只移除外部规则，不影响子类内置规则
```

handler 的结果会按命中缓存（见 [性能与缓存](#性能与缓存)）：修改 `style` / font / textColor、深色模式或字号变化、调用 `rebuild()` 时重新执行；只改按下高亮 / 省略符，或文字变化但该命中的位置和内容没变时直接复用。**handler 依赖的外部数据变化后，请调用 `rebuild()` 或 `setNeedsRebuild(forRuleNamed:)`**。

### ZLRichRuleContext

handler 通过 `ctx` 读取命中信息，并写入要展示的内容：

| 成员 | 说明 |
| --- | --- |
| `match` / `matchedText` / `ruleName` | 命中信息（`match.result` 为原始 `NSTextCheckingResult`，`match.range` 相对原始字符串） |
| `group(_:)` / `group(named:)` | 捕获组 / 命名捕获组 |
| `baseStyle` | 普通文本样式（label 的 font / textColor + `style`） |
| `attributedString` | 要展示的内容，初始为「命中文字 + baseStyle」，可任意修改；为空则不显示 |
| `addAttributes(_:)` | 给整段内容追加属性 |
| `setText(_:attributes:)` | 用新文字替换（默认带 baseStyle） |
| `attachmentString(for:style:)` | 生成自定义 View 的占位富文本，拼进 `attributedString` 即可在该位置显示 View |
| `onTap` | `(ZLRichMatch) -> Void`，设置后整段可点击（含其中的图片和 `tappable` 的 View）。参数是这次点击的命中 |
| `onLongPress` | `(ZLRichMatch) -> Void`，长按这段内容时回调（设置后不再回调 label 的 `onLongPress`） |
| `addLink(range:highlightStyle:onTap:onLongPress:)` | 给内容中的一段单独设置点击 / 长按 / 按下高亮，回调参数同样是命中；可以添加多段、可以互相包含，重叠时后添加的优先（嵌套标签就是先加外层、再加内层） |
| `highlightStyle` | 按下高亮，`nil` 使用 label 的 `highlightStyle`，`[:]` 不高亮 |

插入图片：直接放 `NSTextAttachment` 即可，组件会自动转换成 `UIImageView` 显示（CoreText 本身不绘制 attachment）：

```swift
try? label.addRule(name: "emoji", pattern: "\\[(smile|heart)\\]") { ctx in
    guard let key = ctx.group(1),
          let image = UIImage(systemName: key == "smile" ? "face.smiling" : "heart.fill") else { return }
    let attachment = NSTextAttachment()
    attachment.image = image.withRenderingMode(.alwaysTemplate)
    attachment.bounds = CGRect(x: 0, y: 0, width: 17, height: 17)
    ctx.attributedString.setAttributedString(NSAttributedString(attachment: attachment))
    ctx.onTap = { match in print("emoji", match.group(1) ?? "") }
}
```

插入任意 View：

```swift
try? label.addRule(name: "vip", pattern: "\\[vip\\]") { ctx in
    let badge = UILabel()
    badge.text = "VIP"
    let widget = ZLRichWidget(view: badge, size: CGSize(width: 30, height: 16), alignment: .middle)
    ctx.attributedString.setAttributedString(ctx.attachmentString(for: widget))
}
```

### 自定义 View 尺寸变化

内嵌的自定义 View（`ZLRichWidget` / `attachmentString(for:)` / `tagWidgetBuilder`）尺寸或内容变化后，label 会重新排版：后面的文字跟着移动、换行，label 高度同步更新（Auto Layout 下会触发外部重新布局）。只替换占位尺寸，**不会**重新执行规则 handler / builder，已有的点击和链接保持不变。

| 场景 | 做法 |
| --- | --- |
| 直接修改 View 的 `frame` / `bounds` 尺寸 | 无需额外调用，label 下次布局时自动检测并刷新 |
| 自动尺寸（`size: .zero`）的 View 内容变化，如 UILabel 换了文字 | 调用 `view.zl_setNeedsRichLabelLayout()`，重新测量后刷新 |
| 批量刷新 | `label.invalidateLayout(forAttachmentView:)` / `label.invalidateAttachmentLayout()` |

```swift
// 1. 直接改 frame：自动刷新
box.frame.size.width = 120

// 2. 自动尺寸的 View 内容变了：通知所在 label 重新测量（在任意子 View 上调用都可以）
counter.text = "👍 99"
counter.zl_setNeedsRichLabelLayout()
```

注意：

- 固定尺寸（`size` 不为 `.zero`）且没有改过 frame 的 View，调用刷新不会改变其尺寸
- 之后如果 label `rebuild()`（修改样式、文字等），builder / handler 会重新执行，View 尺寸以新返回的 `ZLRichWidget` 为准。需要保留变化后的状态时，请把状态存在外部，builder 按状态创建 View（见 Example 用例 21）

> 点击 / 长按回调的参数就是这次的命中（`match.text`、`match.group(_:)`、`match.result`、`match.rule`、`match.index`），回调里不需要引用 `ctx`。
> 命中的渲染结果被缓存复用时（位置和内容不变），回调收到的也是本次解析的命中。

### 优先级

多条规则的命中范围重叠时：

1. `priority` 大的优先
2. 同优先级：位置靠前的优先 → 匹配更长的优先 → 先添加的优先（子类内置规则排在外部规则之前）
3. 被淘汰的命中**整体作废**，其中的文字按普通文本或其他规则处理，不做嵌套解析

```swift
// "Call <h1>13800138000</h1>"
label.tagPriority = 0     // phone(20) 优先 → <h1> 标签作废，原样显示
label.tagPriority = 100   // <h1> 优先 → 里面的手机号不再被 phone 规则处理
```

解析结果：

```swift
label.segments   // [ZLRichSegment]：普通文本 + 命中，按位置排序
label.matches    // [ZLRichMatch]：最终生效的命中（含内置规则）
ZLRichParser.resolve(text, rules: rules)   // 不创建 label，单独执行解析
```

## 标签（ZLTagRichLabel）

默认只识别 `<h>` / `<hN>`；需要任意标签名、属性或嵌套时见 [通用标签](#通用标签任意标签名--属性--嵌套)。

### 写法

| 写法 | 结果 |
| --- | --- |
| `<h>文字</h>`、`<h1>文字</h1>`、`<h12>文字</h12>` | 标签，`name` 为小写标签名 |
| `<h1>文字<h1/>` | 同上（另一种闭合写法） |
| `<H4>文字</H4>` | 不区分大小写，`name == "h4"` |
| `<h1>文字</h2>`、`<h2>未闭合` | 原样显示，不影响后面的标签 |
| `<h1>a<h2>b</h2>c</h1>` | 不支持嵌套，只识别最内层 `<h2>b</h2>` |
| `<hx>文字</hx>` | 不是 h 标签，原样显示 |

以上是默认配置下的行为；开启 `allowsNestedTags` 后 `<h1>a<h2>b</h2>c</h1>` 会识别为嵌套的两个标签。

### ZLTagInfo

| 属性 | 说明 |
| --- | --- |
| `index` | 第几个标签（从 0 开始，所有标签名统一计数） |
| `name` | 小写标签名：`h`、`h1`、`h2` … |
| `level` | `h` 后的数字，`<h>` 为 `nil` |
| `text` | 标签内文字 |
| `raw` | 完整原始标签字符串 |
| `attributes` | 标签属性（名称小写），`<a href="x" target=_blank disabled>` → `["href": "x", "target": "_blank", "disabled": ""]` |
| `attribute(_:)` | 读取属性，名称不区分大小写 |
| `colorAttribute(_:)` | 把属性值解析为颜色：`#rgb`、`#rrggbb`、`#rrggbbaa`（`#` 可省略）或 red、blue、gray 等颜色名 |
| `parent` / `depth` | 外层标签 / 嵌套深度（最外层为 `nil` / 0） |

嵌套时 `text` 是去掉内层标签后的纯文字：`<b>粗 <i>斜</i></b>` 的 `<b>` 为 `粗 斜`。

### 样式

样式按顺序 merge，后面的覆盖前面的：

```text
label.font / textColor → style → tagStyle → tagStyles[name] → tagStyleBuilder(info)
```

```swift
label.tagStyle = [.foregroundColor: UIColor.systemBlue]
label.tagStyles = [
    "h1": [.underlineStyle: NSUnderlineStyle.single.rawValue],
    "h2": [.foregroundColor: UIColor.systemRed],
]
label.tagStyleBuilder = { info in                      // 按 index / level / text 单独定制
    info.index == 0 ? [.font: UIFont.boldSystemFont(ofSize: 15)] : nil
}
```

### 自定义内容

优先级：`tagSpanBuilder` > `tagWidgetBuilder` > 默认文字。

```swift
// 完全自定义富文本（可包含 NSTextAttachment 图片），返回 nil 使用默认样式
label.tagSpanBuilder = { info, style in
    guard info.name == "h1" else { return nil }
    return NSAttributedString(string: "《\(info.text)》", attributes: style)
}

// 自定义 View：替换文字 / 放在文字前 / 放在文字后
label.tagWidgetBuilder = { info, _ in
    guard info.name == "h3" else { return nil }
    let dot = UIView()
    dot.backgroundColor = .red
    dot.layer.cornerRadius = 3
    return ZLRichWidget(view: dot, size: CGSize(width: 6, height: 6), position: .after)
}
```

View 的尺寸或内容变化后会自动 / 手动刷新排版，见 [自定义 View 尺寸变化](#自定义-view-尺寸变化)。

`ZLRichWidget` 参数：

| 参数 | 说明 |
| --- | --- |
| `view` | 要显示的 View |
| `size` | 尺寸，`.zero` 时自动计算（`systemLayoutSizeFitting` → `sizeThatFits` → `bounds`） |
| `position` | `.replace`（默认）/ `.before` / `.after`，仅 `tagWidgetBuilder` 生效 |
| `alignment` | 与文字的对齐：`.middle`（默认）/ `.baseline` / `.aboveBaseline` / `.belowBaseline` / `.top` / `.bottom` |
| `tappable` | 是否自动给 View 加点击（触发标签点击）。View 自己处理交互（如勾选框）时设为 `false` |

### 点击与按下高亮

```swift
label.tagTapHandlers = ["h1": { info in ... }]          // 按标签名
label.setTapHandler({ info in ... }, forTag: "h2")      // 等价写法
label.removeTapHandler(forTag: "h2")
label.onTagTap = { info in ... }                        // 兜底：没有对应 handler 的标签

label.tagHighlightStyle = [.backgroundColor: UIColor.lightGray]     // 默认按下高亮
label.tagHighlightStyles = [
    "h1": [.backgroundColor: UIColor.yellow],
    "h3": [:],                                                      // 不高亮
]
```

`tagTapHandlers` 和 `onTagTap` 都没有处理的标签不可点击。

### 通用标签（任意标签名 / 属性 / 嵌套）

```swift
label.tagConfiguration = .anyTags      // 任意标签名 + 嵌套 + 自闭合
// 或分别设置（Objective-C 也可用）：
label.tagNamePattern = ZLTagParserConfiguration.anyTagName   // 标签名正则，整体匹配，不区分大小写；默认 "h\\d*"
label.allowsNestedTags = true          // 默认 false
label.allowsSelfClosingTags = true     // 默认 false
```

只想识别几种标签时，`tagNamePattern` 可以写成 `"b|i|u|color|a"`，其他标签原样显示。

样式、自定义内容、点击都和 `<h>` 一样按标签名配置，属性在 `ZLTagInfo` 里读取：

```swift
label.tagStyles = [
    "b": [.font: UIFont.boldSystemFont(ofSize: 15)],
    "a": [.foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue],
]
label.tagStyleBuilder = { info in                       // <color value="#f00">
    info.colorAttribute("value").map { [.foregroundColor: $0] }
}
label.tagSpanBuilder = { info, style in                 // <br/>
    info.name == "br" ? NSAttributedString(string: "\n", attributes: style) : nil
}
label.tagWidgetBuilder = { info, _ in                   // <icon name="star.fill"/>
    guard info.name == "icon", let name = info.attribute("name") else { return nil }
    return ZLRichWidget(view: UIImageView(image: UIImage(systemName: name)), size: CGSize(width: 16, height: 16))
}
label.setTapHandler({ info in print("open", info.attribute("href") ?? "") }, forTag: "a")
label.text = "<b>粗体里 <color value=\"#2196F3\">蓝色 <a href=\"https://github.com\">链接</a></color></b><br/><icon name=\"star.fill\"/>"
```

嵌套规则：

- **样式**：内层在外层样式的基础上继续 merge（外层样式 → `tagStyle` → `tagStyles[name]` → `tagStyleBuilder(info)`），所以蓝色的链接同时是粗体。
- **点击 / 长按 / 按下高亮**：每个标签单独响应，点在内层范围内只触发内层，其余位置触发外层。
- **`tagSpanBuilder` 返回非 nil 时**，它返回的内容会替换整个标签（包括内层标签），内层不再单独渲染。
- `tags` / `onParsed` 按先序排列（外层在前），内层的 `parent` 指向外层。

容错：

| 写法 | 结果 |
| --- | --- |
| `<b>a <i>b</b>` | `<i>` 未闭合，原样显示 `<i>`；`<b>` 正常 |
| `</u>`、`<b>x</i>` | 多余或不匹配的闭合标签原样显示 |
| `<br/>`（`allowsSelfClosingTags == false`） | 原样显示 |
| `<h1>文字<h1/>` | 前面有未闭合的同名标签时，`<h1/>` 始终作为闭合标签 |
| 属性值 | 支持双引号、单引号、无引号、无值；会解码 `&quot;` `&#39;` `&lt;` `&gt;` `&amp;` |

不创建 label、单独解析：

```swift
ZLTagParser.tags(in: source, configuration: .anyTags)   // [ZLTagInfo]，外层在前
```

### 其他

```swift
label.parsesTags = false            // 关闭 <h> 解析，只用自定义规则
label.onParsed = { tags in ... }     // 解析完成后异步回调所有标签
label.tags                           // 当前所有标签 [ZLTagInfo]
label.ruleMatches                    // 当前所有自定义规则命中（不含 <h> 标签）
ZLTagParser.tags("<h1>a</h1>")        // 独立解析 <h> 标签，不创建 label
```

## ZLAttributedLabel（底层富文本 Label）

`ZLAttributedLabel` 继承 `UILabel`，用 CoreText 自行绘制，是 `ZLRichLabel` 的父类，也可以单独使用（替代 TTTAttributedLabel）。
`ZLRichLabel` / `ZLTagRichLabel` 自动拥有下面所有能力。

### 文字

| API | 说明 |
| --- | --- |
| `text` | 纯文本，使用 label 的 `font` / `textColor` / `textAlignment` / `lineBreakMode`；之后修改这些属性会自动重新生成 |
| `attributedText` | 富文本，原样显示；`.link` 属性的范围自动成为链接 |
| `.backgroundColor` / `.strikethroughStyle` / `.strikethroughColor` | CoreText 不绘制，由 label 补充绘制 |
| `shadowColor` / `shadowOffset` / `shadowRadius` | 整段文字阴影，`shadowRadius` 为新增的模糊半径 |
| `isHighlighted` / `highlightedTextColor` | 高亮时全部文字使用 `highlightedTextColor`（与 `UILabel` 一致） |
| `labelAttributes()` | 由 `font` / `textColor` / 对齐等生成的默认属性，子类可重写 |

### 布局

| API | 说明 |
| --- | --- |
| `textInsets` | 内边距，默认 `.zero`；尺寸计算、点击、截断、字符定位都按内边距偏移 |
| `verticalAlignment` | label 比内容高时的垂直对齐：`.center`（默认）/ `.top` / `.bottom`（OC：`ZLLabelVerticalAlignmentTop` 等） |
| `numberOfLines` / `lineBreakMode` | 行数限制与截断；多行时只截断最后一行（尾部），单行时支持头 / 中 / 尾 |
| `attributedTruncationToken` | 自定义截断符，例如「…更多」，nil 时为 `…` |
| `sizeThatFits(_:)` / `intrinsicContentSize` | 包含内边距，按「宽度 + 行数」缓存；多行时 Auto Layout 宽度变化后自动重新计算高度 |
| `preferredMaxLayoutWidth` | 大于 0 时 `intrinsicContentSize` 按这个宽度计算 |
| `adjustsFontSizeToFitWidth` / `minimumScaleFactor` | 字号自适应：放不下时按同一比例缩小所有字体（含截断符），最小到 `minimumScaleFactor`（为 0 时不缩小，与 `UILabel` 相同）。单行按宽度，多行按 `numberOfLines` 与 label 高度判断；不缩放字间距、行距与内嵌 View；`sizeThatFits` 仍按原字号计算 |
| `currentFontScaleFactor` | 当前实际使用的缩放比例，1 表示未缩小 |

### 链接

| API | 说明 |
| --- | --- |
| `addLink(to:range:)` | 添加 URL 链接，点击回调 delegate 的 `didSelectLinkWith url` |
| `addLink(range:attributes:onTap:)` | 添加带回调的链接，返回 `ZLLabelLink`（可再设置 `onLongPress`） |
| `addLink(_:)` | 添加自定义的 `ZLLabelLink`：可单独设置 `attributes` / `activeAttributes` / `inactiveAttributes`、`onTap` / `onLongPress`、`accessibilityHintText` |
| `removeAllLinks()` / `links` | 移除 / 读取所有链接，后添加的优先响应 |
| `enabledTextCheckingTypes` | 用 `NSDataDetector` 自动识别网址、电话、日期、地址等，识别结果在 `link.result` |
| `linkAttributes` / `activeLinkAttributes` / `inactiveLinkAttributes` | 链接默认 / 按下 / 失活（弹出 alert 等 `tintAdjustmentMode == .dimmed` 时）样式 |
| `extendsLinkTouchArea` | 手指没有按在文字上时向四周最多 15pt 查找链接；按在普通文字上时不会命中旁边的链接 |
| `longPressGestureRecognizer` | 只在按在链接上时开始，可调整 `minimumPressDuration` |
| `delegate` | `ZLAttributedLabelDelegate`，见下 |
| `link(at:)` / `containsLink(at:)` / `link(atCharacter:)` / `activeLink` | 按坐标 / 字符查询链接，当前按下的链接 |
| `performTap(on:)` | 以代码触发一次链接点击（与用户点击走同样的回调） |

点击的回调顺序：链接设置了 `onTap` 时只调用 `onTap`；否则带 URL 的链接调用 `didSelectLinkWith url`（未实现时退回 `didSelect link`），其他链接调用 `didSelect link`。
长按同理：`onLongPress` 优先，否则调用 `didLongPress link at point`。

```swift
extension ViewController: ZLAttributedLabelDelegate {
    func attributedLabel(_ label: ZLAttributedLabel, didSelectLinkWith url: URL) { UIApplication.shared.open(url) }
    func attributedLabel(_ label: ZLAttributedLabel, didSelect link: ZLLabelLink) {
        if let phone = link.result?.phoneNumber { print("call", phone) }
    }
    func attributedLabel(_ label: ZLAttributedLabel, didLongPress link: ZLLabelLink, at point: CGPoint) { }
}

// 自定义样式的链接：橙底白字，按下变深
let link = ZLLabelLink(range: range,
                       attributes: [.foregroundColor: UIColor.white, .backgroundColor: UIColor.systemOrange],
                       activeAttributes: [.backgroundColor: UIColor.brown])
link.onTap = { label, link in print(link.range) }
link.onLongPress = { label, link in showMenu() }
label.addLink(link)
```

### 定位与无障碍

| API | 说明 |
| --- | --- |
| `characterIndex(at:)` | 坐标处的字符下标，没有按在文字上时为 `NSNotFound` |
| `boundingRect(forCharacterRange:)` | 一段文字在 label 坐标系中的矩形（不含行尾空格） |
| VoiceOver | 有链接时 label 作为容器：整段文字 + 每个链接，链接可单独聚焦、双击触发点击；`ZLLabelLink.accessibilityHintText` 为附加说明 |

### Objective-C

```objc
ZLAttributedLabel *label = [[ZLAttributedLabel alloc] initWithFrame:CGRectZero];
label.numberOfLines = 0;
label.textInsets = UIEdgeInsetsMake(8, 12, 8, 12);
label.verticalAlignment = ZLLabelVerticalAlignmentTop;
label.text = @"阅读并同意《用户协议》";
[label addLinkWithRange:[label.text rangeOfString:@"《用户协议》"] attributes:nil
                  onTap:^(ZLAttributedLabel *l, ZLLabelLink *link) { NSLog(@"agreement"); }];
[label addLinkToURL:[NSURL URLWithString:@"https://www.apple.com"] withRange:range];
label.delegate = self;   // attributedLabel:didSelectLinkWithURL: / attributedLabel:didSelectLink: / attributedLabel:didLongPressLink:atPoint:
```

暂不支持：`ZLAttributedLabel` 本身不绘制 `NSTextAttachment` 图片（`ZLRichLabel` 会把附件转换成 View 显示）。

## 通用配置

| API | 说明 |
| --- | --- |
| `text` | 设置 `String` 按规则解析；`nil` 清空。读取得到渲染后的文字 |
| `attributedText` | 设置 `NSAttributedString` 不解析，按 `ZLAttributedLabel` 原逻辑直接显示 |
| `rawText` / `tagText` | 原始字符串 |
| `style` | 普通文本样式（未设置 font / foregroundColor 时使用 label 的 `font` / `textColor`） |
| `highlightStyle` | 默认按下高亮样式（`ZLTagRichLabel.tagHighlightStyle` 即此属性） |
| `truncationToken` | 截断省略符，默认带普通文本样式的 `…` |
| `numberOfLines` / `lineBreakMode` | 多行与截断 |
| `textInsets` | 内边距，默认 `.zero`。文字、点击热区、自定义 View、截断与「展开」都在内边距以内；`sizeThatFits` / `intrinsicContentSize` 包含内边距 |
| `verticalAlignment` | label 比内容高时的垂直对齐：`.center`（默认）/ `.top` / `.bottom` |
| `update { }` / `beginUpdates()` / `endUpdates()` | 批量修改，只渲染一次 |
| `rebuild()` | 强制重新渲染：清空渲染缓存，所有 builder / handler 重新执行（外部状态变化后调用） |
| `setNeedsRebuild(forRuleNamed:)` | 只让某条规则重新执行 handler，其他命中直接复用 |
| `statistics` | 渲染 / 排版统计（handler 执行次数、复用次数、framesetter 创建次数等），调试缓存用 |
| `invalidateAttachmentLayout()` / `invalidateLayout(forAttachmentView:)` | 自定义 View 尺寸 / 内容变化后刷新排版（不重新执行 builder / handler） |
| `isRightToLeft` | 当前内容是否为 RTL |
| `adjustsFontForContentSizeCategory` | 默认 `false`。开启后按系统「文字大小」缩放所有字体（正文、规则 / 标签内容、自定义 View 的对齐），系统字号变化时自动重新渲染；`UIFont.preferredFont(forTextStyle:)` 创建的字体不会重复缩放 |
| `scaledFont(_:)` | 按当前系统字号缩放一个字体（未开启上面的开关时原样返回），可在 handler / builder 中给自定义 View 用 |

深色模式：浅色 / 深色切换时 label 会自动重新渲染，规则 handler 和 builder 会重新执行。使用动态颜色（如 `.label`、`UIColor { trait in ... }`）即可自动适配；需要按外观返回不同内容时，在 handler 中读取 `label.traitCollection.userInterfaceStyle`。

布局：

- Auto Layout：设置宽度约束即可，高度由 `intrinsicContentSize` 计算
- Frame 布局：`label.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))`
- RTL：`textAlignment` 为 `.natural`（默认）时，按内容的第一个强方向字符自动左 / 右对齐

内边距：背景色铺满整个 label，文字在内边距以内排版，适合「气泡 / 卡片」样式，不需要再套一层容器 View：

```swift
label.textInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
label.backgroundColor = .secondarySystemBackground
label.layer.cornerRadius = 12
label.layer.masksToBounds = true
// Frame 布局：传入 label 的总宽度，返回的高度已包含上下内边距
let height = label.sizeThatFits(CGSize(width: 300, height: .greatestFiniteMagnitude)).height
```

```objc
label.textInsets = UIEdgeInsetsMake(12, 16, 12, 16);
```

SwiftUI 中在 `configure` 里设置：`ZLRichText(text, configure: { $0.textInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12) })`。

xib / storyboard 中设置的文字同样会被解析。

## 胶囊背景 / 渐变文字

给一段文字加上属性即可，规则 handler、`style`、`tagStyles`、按下高亮里都能用：

```swift
// #话题#：浅色胶囊
try? label.addRule(name: "topic", pattern: "#[^#\\s]+#") { ctx in
    ctx.addAttributes([.foregroundColor: UIColor.systemPurple,
                       .zlBackground: ZLTextBackground.capsule(.systemPurple)])
    // 按下时换成更深的背景
    ctx.highlightStyle = [.zlBackground: ZLTextBackground(fillColor: UIColor.systemPurple.withAlphaComponent(0.3))]
}
// `代码`：去掉反引号，灰色背景 + 细边框
try? label.addRule(name: "code", pattern: "`([^`]+)`") { ctx in
    ctx.setText(ctx.group(1) ?? "", attributes: [.font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                                                  .zlBackground: ZLTextBackground.code])
}
// 渐变文字
label.tagStyles = ["grad": [.font: UIFont.boldSystemFont(ofSize: 22),
                            .zlGradient: ZLTextGradient(colors: [.systemPink, .systemOrange, .systemPurple])]]
```

`ZLTextBackground`：

| 属性 | 说明 |
| --- | --- |
| `fillColor` | 填充色，nil 不填充 |
| `strokeColor` / `lineWidth` | 边框颜色 / 宽度，`strokeColor` 为 nil 时没有边框 |
| `cornerRadius` | 圆角，小于 0（默认 -1）时为高度的一半，两端是半圆 |
| `padding` | 文字到背景边缘的距离，默认上下 1、左右 6 |
| `margin` | 背景外侧与相邻文字的水平间距，默认 2 |
| `capsule(_:)` / `code` | 预设：浅色胶囊 / 行内代码 |

`ZLTextGradient`：`colors`、`locations`（nil 时均匀分布）、`startPoint` / `endPoint`（单位坐标，默认从左到右；竖向渐变用 `(0.5, 0)` → `(0.5, 1)`）。

说明：

- **水平内边距占用排版空间**：组件用 kern 在胶囊两侧预留 `padding + margin`（位于段落开头时用首行缩进），不插入任何字符，所以展示文字、原文、点击范围、选中都不受影响。
- **垂直内边距不占行高**，只影响绘制；多行文本请适当设置 `lineSpacing`，避免背景和上下行重叠。
- **跨行**：胶囊和渐变都按行分段绘制；位于折行开头 / 结尾的一段不会超出 label。
- 相邻的两个命中即使用的是同一个 `ZLTextBackground` 实例，也是两个独立的胶囊。
- 渐变文字的原颜色会被设为透明，下划线 / 删除线因此也不显示。
- 从右到左（RTL）文本中，胶囊左右内边距的位置可能不够精确。

## 长按 / 双击 / 点击热区

```swift
// 长按：其他位置弹出「复制 / 举报」菜单
label.onLongPress = { info in
    // info.location / characterIndex / match / matchDisplayText / rawText / displayText
    UIPasteboard.general.string = info.rawText
}

// 某条规则的命中单独处理长按（设置后长按它不再回调 label.onLongPress）
try? label.addRule(name: "mention", pattern: "@\\w+") { ctx in
    ctx.onTap = { match in openProfile(match.text) }
    ctx.onLongPress = { match in showMenu(for: match.text) }
}

// ZLTagRichLabel：长按标签
tagLabel.onTagLongPress = { info in UIPasteboard.general.string = info.text }

// 双击
label.onDoubleTap = { info in like() }

// 点击热区向四周扩大最多 15pt（ZLAttributedLabel 的属性，对 match(at:) 同样生效；按在普通文字上时不会命中旁边的链接）
label.extendsLinkTouchArea = true
```

| API | 说明 |
| --- | --- |
| `onLongPress` | 长按回调，参数为 `ZLRichGestureInfo`。长按会取消按下高亮和点击 |
| `ctx.onLongPress` / `onTagLongPress` | 命中 / 标签自己的长按，优先于 `onLongPress` |
| `onDoubleTap` | 双击回调。**设置后单击链接要等双击判定失败才触发（约 0.3 秒）**，不需要时保持 nil |
| `richLongPressGesture` / `richDoubleTapGesture` | 对应的手势，可调整 `minimumPressDuration` 等，也可用来定位菜单 |
| `extendsLinkTouchArea` | 可点击内容的热区向四周扩大最多 15pt |
| `characterIndex(at:)` | 某个位置在展示文字中的字符下标，不在文字上时为 `NSNotFound` |
| `match(at:)` | 某个位置所在的规则命中 |
| `gestureInfo(at:)` | 某个位置的完整信息（同 `ZLRichGestureInfo`） |

`ZLRichGestureInfo`：

| 属性 | 说明 |
| --- | --- |
| `location` | 手势位置（label 坐标系） |
| `characterIndex` | 展示文字中的字符下标，不在文字上时为 `NSNotFound` |
| `match` / `matchDisplayText` | 所在的规则命中，以及它在 label 上展示的文字（规则可能替换过） |
| `rawText` / `displayText` | 原始字符串 / 渲染后的文字（图片和 View 为占位符 U+FFFC） |

基类 `ZLAttributedLabel` 的 `longPressGestureRecognizer` 只作用于链接，在 `ZLRichLabel` 中已被禁用，统一使用 `richLongPressGesture`。

## 选中复制

```swift
label.isSelectable = true
label.onCopy = { text, isRawText in print(isRawText ? "原文" : "展示文字", text) }
label.onSelectionChanged = { range in print(label.selectedText ?? "", label.selectedRawText ?? "") }
```

- 长按文字选中一个词（中文按系统分词），长按在规则命中上则选中整个命中
- 不松手拖动扩展范围；松手后可拖动两端的拖柄调整
- 松手弹出菜单：**复制**（展示文字）、**复制原文**、**全选**（iOS 16+ 使用 `UIEditMenuInteraction`，更低版本使用 `UIMenuController`）
- 点击 label 或菜单消失（复制后、点击别处）时取消选中；内容变化后自动取消选中
- 开启后长按普通文字用于选中，不再回调 `onLongPress`；命中自己的 `ctx.onLongPress` / `onTagLongPress` 仍然优先

展示文字与原文的对应：普通文字逐字对应；规则命中（可能替换了文字、换成了图片）只要选中一部分，就对应整个命中的原文。

```text
原文      Hi [smile] @alice, hello world
展示文字  Hi  😊   👤alice, hello world
选中 "ali"          → selectedText "ali"，selectedRawText "@alice"
全选               → selectedText 去掉图片占位符，selectedRawText 与 rawText 相同
```

| API | 说明 |
| --- | --- |
| `isSelectable` | 是否可以选中，默认 false |
| `selectedRange` / `hasSelection` | 选中范围（展示文字中），没有选中时 `location == NSNotFound` |
| `selectedText` | 选中的展示文字（去掉图片 / View 的占位符） |
| `selectedRawText` | 选中范围对应的原文 |
| `rawText(forDisplayRange:)` | 任意展示范围对应的原文 |
| `select(range:)` / `selectAllText()` / `clearSelection()` | 代码控制选中（全选不包含「收起」） |
| `copySelection(raw:)` | 复制选中内容（与菜单相同，会回调 `onCopy`） |
| `selectionColor` | 选中背景色，默认 `tintColor` 的 25% 透明度；拖柄使用不透明的同色 |
| `copyMenuTitle` / `copyRawMenuTitle` / `selectAllMenuTitle` | 菜单标题，默认「复制 / 复制原文 / 全选」 |
| `onSelectionChanged` / `onCopy` | 选中范围变化 / 复制后回调 |

## 展开 / 收起

内容超过 `numberOfLines` 行时，最后一行末尾显示 `expandToken`（代替省略符），点击后展开全部内容；展开后在末尾显示 `collapseToken`，点击恢复。

```swift
label.numberOfLines = 3                      // 收起时的行数
label.expandToken = NSAttributedString(string: "… 全文", attributes: [.foregroundColor: UIColor.systemBlue])
label.collapseToken = NSAttributedString(string: " 收起", attributes: [.foregroundColor: UIColor.systemBlue])
label.onExpandChanged = { [weak self] expanded in
    self?.model.isExpanded = expanded        // 保存状态
    self?.tableView.performBatchUpdates(nil) // 列表中刷新行高
}

// cell 复用时按数据设置，不会触发 onExpandChanged
label.isExpanded = model.isExpanded
```

默认点击「全文 / 收起」由内部自动切换。需要由外部决定时（例如跳转详情页、先请求完整内容、弹窗确认），设置 `onExpandTokenTap`：
设置后点击按钮只回调它，**不会自动切换**，也不回调 `onExpandChanged`；外部需要切换时设置 `isExpanded` 或调用 `toggleExpanded()`。

```swift
label.onExpandTokenTap = { [weak self] label, wantsExpand in   // 点「全文」为 true，点「收起」为 false
    if wantsExpand, self?.model.isLongArticle == true {
        self?.openDetail()                                     // 不展开，跳转详情页
    } else {
        label.toggleExpanded()                                 // 按默认方式切换，并回调 onExpandChanged
    }
}
label.onExpandTokenTap = nil                                   // 恢复内部自动切换
```

| API | 说明 |
| --- | --- |
| `expandToken` | 「展开」按钮，没设置的属性使用普通文本样式；为 nil（默认）时只显示省略符 |
| `collapseToken` | 「收起」按钮，展开后拼接在末尾，可点击、有按下高亮；为 nil 时展开后不能收起 |
| `isExpanded` | 展开状态。直接设置不回调 `onExpandChanged` |
| `onExpandChanged` | 点击「全文 / 收起」后回调新的状态（设置了 `onExpandTokenTap` 时由外部切换后才回调） |
| `onExpandTokenTap` | 可选，点击「全文 / 收起」按钮的外部处理，参数为 label 和想要的状态；设置后不自动切换，为 nil（默认）时内部自动切换 |
| `toggleExpanded()` | 切换状态并回调，与点击效果相同 |
| `numberOfLines` / `collapsedNumberOfLines` | 展开时 `numberOfLines` 读取为 0；设置的行数保存在 `collapsedNumberOfLines` |
| `isTruncated` | 当前内容是否被截断（最近一次布局的结果） |
| `expandTokenRect` | 「展开」按钮的点击区域（label 坐标系） |

注意：

- 设置 `expandToken` 后 `lineBreakMode` 会改为 `.byTruncatingTail`
- 展开 / 收起只重新拼装内容，不会重新执行规则 handler / builder
- 内容不足 `numberOfLines` 行时不显示「展开」；直接设置 `isExpanded = true` 时，即使内容很短也会显示「收起」

## 性能与缓存

**渲染缓存**：每个命中的渲染结果（handler / builder 的输出、创建的自定义 View、点击）都会缓存，下次渲染时直接复用，不执行 handler、不重建 View。

| 操作 | 重新执行 handler 的范围 |
| --- | --- |
| `highlightStyle`、`truncationToken` | 不执行，全部复用 |
| 修改文字（`text` / `rawText`） | 只有位置、序号或内容变化的命中（例如在末尾追加时，前面的全部复用） |
| 增删规则 | 只有受影响的命中 |
| `ZLTagRichLabel` 的标签配置（`tagStyle`、`tagStyles`、`tagWidgetBuilder`、`onTagTap` 等） | 只有 `<h>` 标签，自定义规则复用 |
| `setNeedsRebuild(forRuleNamed:)` | 只有这条规则 |
| `style`、`font`、`textColor`、深色模式 / 字号变化、`rebuild()` | 全部 |

**排版缓存**：同一份内容只创建一次 `CTFramesetter`；`sizeThatFits` / `intrinsicContentSize` 按「宽度 + 行数」缓存结果，自定义 View 的定位按文本区域缓存行信息。内容或尺寸变化时自动失效。

**解析**：多条规则重叠时的取舍为 O(n log n)，上万个命中也能很快完成。

```swift
label.statistics.reset()
label.highlightStyle = [.backgroundColor: UIColor.yellow]
print(label.statistics)   // renders: 1, handlerCalls: 0, reusedMatches: 600, ...
```

自己写子类时：只影响内置规则渲染的配置用 `setNeedsRebuild(forRuleNamed:)`，影响所有内容的用 `setNeedsRebuild()`。

## 继承 ZLRichLabel 实现自己的规则组件

`ZLTagRichLabel` 就是这样实现的：重写 `builtInRules` 提供内置规则，配置变化时调用 `setNeedsReparse()` / `setNeedsRebuild()`。

```swift
final class MentionLabel: ZLRichLabel {

    var mentionColor: UIColor = .systemBlue { didSet { setNeedsRebuild() } }   // 只影响渲染
    var onMentionTap: ((String) -> Void)?

    private lazy var mentionRule = ZLRichRule(name: "mention",
                                               regex: try! NSRegularExpression(pattern: "@\\w+")) { [weak self] ctx in
        guard let self = self else { return }
        ctx.addAttributes([.foregroundColor: self.mentionColor])
        ctx.onTap = { [weak self] match in self?.onMentionTap?(match.text) }
    }

    override var builtInRules: [ZLRichRule] {
        return super.builtInRules + [mentionRule]
    }

    override func didParse() {
        super.didParse()
        // 可在这里整理 matches，例如统计 @ 了哪些用户
    }
}
```

- 影响**解析**的配置（规则的正则、优先级、是否启用）变化 → `setNeedsReparse()`
- 只影响**渲染**的配置变化 → `setNeedsRebuild()`
- 内置规则的 handler 中用 `[weak self]`，避免 label ↔ rule 循环引用

## SwiftUI

`ZLRichText` 用 `UIViewRepresentable` 包了一层 `ZLTagRichLabel`，高度随内容自适应：

```swift
import SwiftUI
import ZLRichLabel

struct AgreementView: View {
    @State private var isExpanded = false

    var body: some View {
        ZLRichText("我已阅读并同意<h1>《用户协议》</h1>和 #话题#", configure: { label in
            // 只在创建时执行一次：加规则、设样式和回调
            label.style = [.font: UIFont.systemFont(ofSize: 15)]
            label.tagStyles = ["h1": [.foregroundColor: UIColor.systemBlue]]
            label.onTagTap = { info in print(info.text) }
            try? label.addRule(name: "topic", pattern: "#[^#\\s]+#") { ctx in
                ctx.addAttributes([.zlBackground: ZLTextBackground.capsule(.systemPurple)])
            }
            label.numberOfLines = 2
            label.expandToken = NSAttributedString(string: "… 全文")
            label.onExpandChanged = { isExpanded = $0 }     // label → @State
        }, update: { label in
            // 每次 SwiftUI 刷新都会执行：同步会变化的状态
            if label.isExpanded != isExpanded { label.isExpanded = isExpanded }   // @State → label
        })
    }
}
```

| 参数 / 修饰符 | 说明 |
| --- | --- |
| `text` | 原始文本，变化时重新解析 |
| `configure` | 创建 label 时执行**一次**：添加规则、设置样式与回调。规则请在这里添加，避免每次刷新重复添加 |
| `update` | 每次 SwiftUI 刷新时执行（在一次批量更新中，最后才设置 `text`），用于同步 `@State` 等会变化的配置 |
| `.lineLimit(_:)` | 同步到 `numberOfLines`；只在变化时应用，不会覆盖 `configure` 里设置的行数 |

高度自适应：

- iOS 16+：通过 `sizeThatFits(_:uiView:context:)` 按 SwiftUI 提供的宽度计算，宽度不超过可用宽度（短文字不会撑满）。
- iOS 13 ~ 15：用 `GeometryReader` 读取宽度后测量高度，占满可用宽度。
- label 内部的变化（点击「全文」展开、自定义 View 尺寸变化、Dynamic Type）也会重新计算高度，可以直接放在 `ScrollView` / `List` 中。

说明：

- `configure` 里的回调是在创建时捕获的。修改外部状态请通过 `@State` / `@Binding` / `ObservableObject` 等引用语义的方式，不要依赖创建后才变化的普通值。
- 需要直接操作 label 时（如 `toggleExpanded()`），在 `configure` 里把它保存到引用类型中，或者通过 `update` 同步状态。

## Objective-C

所有公开类型都是 `NSObject` 子类或 `@objc` 枚举，`@import ZLRichLabel;` 即可使用。

```objc
@import ZLRichLabel;

ZLTagRichLabel *label = [[ZLTagRichLabel alloc] initWithFrame:CGRectZero];
label.numberOfLines = 0;

// updateTag: 的回调参数直接是 ZLTagRichLabel（基类 ZLRichLabel 用 update:）
[label updateTag:^(ZLTagRichLabel *v) {
    v.style = @{NSFontAttributeName: [UIFont systemFontOfSize:15]};
    v.tagStyles = @{@"h1": @{NSForegroundColorAttributeName: UIColor.systemBlueColor}};
    v.tagHighlightStyles = @{@"h1": @{NSBackgroundColorAttributeName: UIColor.yellowColor}};

    // tagTapHandlers 在 OC 中不可用，使用 setTapHandler:forTag:
    [v setTapHandler:^(ZLTagInfo *info) { NSLog(@"h1 %@", info.text); } forTag:@"h1"];
    v.onTagTap = ^(ZLTagInfo *info) { NSLog(@"%@ level=%@", info.name, info.level); };

    [v addRuleWithName:@"mention" pattern:@"@\\w+" options:0 priority:10 error:nil
               handler:^(ZLRichRuleContext *ctx) {
        [ctx addAttributes:@{NSForegroundColorAttributeName: UIColor.systemPurpleColor}];
        ctx.onTap = ^(ZLRichMatch *match) { NSLog(@"mention %@", match.text); };   // 参数是这次点击的命中
    }];

    v.text = @"Agree to <h1>User Agreement</h1>, cc @bob";
}];
```

| Swift | Objective-C |
| --- | --- |
| `label.update { v in }` | `ZLTagRichLabel`：`[label updateTag:^(ZLTagRichLabel *v) {}]`；`ZLRichLabel`：`[label update:^(ZLRichLabel *v) {}]`（或 `beginUpdates` / `endUpdates`） |
| `tagTapHandlers = [...]` | `setTapHandler:forTag:` / `removeTapHandlerForTag:` |
| `addRule(name:pattern:options:priority:handler:)` | `addRuleWithName:pattern:options:priority:error:handler:` |
| `removeRule(named:)` | `removeRuleNamed:` |
| `ctx.group(1)` / `ctx.group(named:)` | `[ctx groupAtIndex:1]` / `[ctx groupNamed:]` |
| `ctx.onTap = { match in }` | `ctx.onTap = ^(ZLRichMatch *match) {}` |
| `info.level`（`Int?`） | `info.level`（`NSNumber *`，`<h>` 时为 `nil`） |
| `ZLRichParser.resolve(_:rules:)` | `[ZLRichParser matchesInString:rules:]` |
| `view.zl_setNeedsRichLabelLayout()` | `[view zl_setNeedsRichLabelLayout]` |
| `invalidateLayout(forAttachmentView:)` | `invalidateLayoutForAttachmentView:` |
| `setNeedsRebuild(forRuleNamed:)` | `setNeedsRebuildForRuleNamed:` |
| `onExpandChanged = { expanded in }` | `onExpandChanged = ^(BOOL expanded) {}` |
| `onExpandTokenTap = { label, wantsExpand in }` | `onExpandTokenTap = ^(ZLRichLabel *label, BOOL wantsExpand) {}` |
| `onLongPress = { info in }` / `onDoubleTap` | `onLongPress = ^(ZLRichGestureInfo *info) {}` |
| `characterIndex(at:)` / `match(at:)` / `gestureInfo(at:)` | `characterIndexAtPoint:` / `matchAtPoint:` / `gestureInfoAtPoint:` |
| `select(range:)` / `rawText(forDisplayRange:)` / `copySelection(raw:)` | `selectRange:` / `rawTextForDisplayRange:` / `copySelectionRaw:` |
| `onCopy = { text, isRaw in }` | `onCopy = ^(NSString *text, BOOL isRaw) {}` |
| `tagConfiguration = .anyTags` | `tagNamePattern = ZLTagParser.anyTagNamePattern; allowsNestedTags = YES; allowsSelfClosingTags = YES;` |
| `info.attribute("href")` / `info.colorAttribute("value")` | `[info attributeNamed:@"href"]` / `[info colorAttributeNamed:@"value"]` |
| `ZLTagParser.tags(in:configuration:)` | `[ZLTagParser tagsInString:namePattern:allowsNesting:allowsSelfClosing:]` |
| `.zlBackground` / `.zlGradient` | `ZLRichLabel.textBackgroundAttributeName` / `ZLRichLabel.textGradientAttributeName` |
| `ZLTextBackground(fillColor:strokeColor:cornerRadius:)` | `[ZLTextBackground backgroundWithFillColor:strokeColor:cornerRadius:]` |
| `ZLTextGradient(colors:)` | `[ZLTextGradient gradientWithColors:]` |

## 命名变更（迁移）

所有公开类型统一使用 `ZL` 前缀。

- **2.x**：Swift 中旧名字仍可使用（过时别名，编译时提示改为新名字，Xcode 可一键修复）；Objective-C 只能使用新类名。
- **3.0 起**：旧名字已全部删除，使用旧名字的代码会编译失败。从 2.x 升级时，建议先在 2.x 下按编译警告改为新名字，再升级到 3.0；也可以直接按下表替换。

| 旧名字 | 新名字 |
| --- | --- |
| `HTagTextStyle` | `ZLTextStyle` |
| `HTagWidget` / `HTagWidgetPosition` / `HTagWidgetAlignment` | `ZLRichWidget` / `ZLRichWidgetPosition` / `ZLRichWidgetAlignment` |
| `TagRichRule` / `TagRichMatch` / `TagRichRuleContext` / `TagRichParser` | `ZLRichRule` / `ZLRichMatch` / `ZLRichRuleContext` / `ZLRichParser` |
| `HTagInfo` / `HTagSegment` | `ZLTagInfo` / `ZLTagSegment` |
| `HTagParser` | `ZLTagParser`（与通用标签解析器合并，`parse(_:)` / `tags(_:)` 不变） |
| `HTagStyleBuilder` / `HTagSpanBuilder` / `HTagWidgetBuilder` / `HTagTapCallback` | `ZLTagStyleBuilder` / `ZLTagSpanBuilder` / `ZLTagWidgetBuilder` / `ZLTagTapCallback` |
| `ZLTagRichLabel.hTagPriority` / `parsesHTags` / `hTagRuleName` | `tagPriority` / `parsesTags` / `tagRuleName`（规则名的值仍为 `"h-tag"`） |
| OC 枚举 `HTagWidgetPositionReplace` 等 | `ZLRichWidgetPositionReplace` 等 |

另外，`ctx.onTap` / `ctx.onLongPress` / `addLink` 的回调改为接收命中信息：`ctx.onTap = { match in ... }`（OC：`^(ZLRichMatch *match) {}`），
原来不带参数的写法需要加上参数（不用时写 `_ in`）。

## Example

```bash
cd Example
pod install          # 只安装测试用的 FBSnapshotTestCase
open ZLRichLabel.xcworkspace
```

Example 工程通过 Swift Package Manager 引用仓库根目录的本地包（`..`），修改库源码后直接生效。

示例 App 包含 4 个页面：

| 页面 | 入口 | 内容 |
| --- | --- | --- |
| `HTagDemoPage.swift` | 首页 | `ZLTagRichLabel` / `ZLRichLabel` 全部功能，用例 1 – 29（见下表） |
| `OCDemoViewController.m` | 导航栏左上角「OC」 | 与首页内容一致的 Objective-C 版本 |
| `SwiftUIDemoPage.swift` | 导航栏右上角「SwiftUI」 | `ZLRichText`：基础用法与点击、输入时高度实时变化、展开 / 收起与 `@State` 同步、`.lineLimit`、规则 + 胶囊 + 渐变、`List` 中自适应行高 |
| `AttributedLabelDemoPage.swift` | 导航栏右上角「Base」 | 底层 `ZLAttributedLabel`，用例 1 – 13（见下表） |

首页用例：

| 用例 | 内容 |
| --- | --- |
| 1 – 10 | `ZLTagRichLabel`：按标签名样式、按 index 样式、闭合写法与大小写、按标签名点击、按下高亮、容错、图标、无点击、多行截断、自定义 View |
| 11 | 自定义 View 自己处理交互（勾选框，`tappable: false`） |
| 12 – 16 | 阿拉伯语 RTL：样式与点击、双向混排、截断、自定义 View / 图标、勾选框 |
| 17、18、20 | `ZLRichLabel` 自定义规则：@提及 / #话题# / 链接、表情图片 / 模板变量、简易 Markdown |
| 19 | `ZLTagRichLabel`：`<h>` 标签与自定义规则的优先级 |
| 21 | 自定义 View 尺寸变化自动刷新排版：点击色块改 frame 变宽、点赞计数文字变化 |
| 22 | 深色模式 / Dynamic Type：切换预览区域的外观与文字大小，文字、标签、规则内容和自定义 View 一起变化 |
| 23 | 性能：600 个命中（含 200 张图片）的 label，对比改高亮 / 追加文字 / 只刷新一条规则 / `rebuild()` 的耗时与 handler 执行次数，`sizeThatFits` 缓存，1.5 万命中的解析耗时 |
| 24 | 展开 / 收起：3 行截断显示「… 全文」，展开后显示「收起」；内容不足 3 行时不显示按钮；24c / 24d 为 `collapseThreshold`；24e 为 `onExpandTokenTap`（点击按钮弹出选项，由外部决定展开、跳转详情或取消） |
| 25 | 长按菜单（复制原文 / 展示文字、举报）、@提及与标签各自的长按、双击点赞、扩大点击热区 |
| 26 | 选中复制：长按选词、拖柄调整，「复制」展示文字 /「复制原文」，下方实时显示 selectedText / selectedRawText |
| 27 | 通用标签：`<b>` `<i>` `<u>` `<color value>` `<size value>` `<a href>`、自闭合 `<br/>` `<icon/>`、嵌套（内层继承外层样式、点击内层优先）、容错；卡片下方按嵌套缩进显示属性 |
| 28 | 胶囊背景 / 渐变文字：#话题# 胶囊（按下变深）、行内代码、实心徽章、只有边框的标签、横向 / 竖向渐变、跨行的胶囊 |
| 29 | 内边距 `textInsets`：圆角背景的 label 切换 0 / 8 / 12·16 / 24 内边距，文字重新折行；链接、内嵌标签、展开 / 收起都在内边距以内 |

页面顶部会显示最近一次点击得到的完整信息，底部有点击历史。

`ZLAttributedLabel` 页面用例（顶部显示最近一次回调）：

| 用例 | 内容 |
| --- | --- |
| 1 | 纯文本 `text`：切换 `font` / `textColor` / `textAlignment` 后自动更新 |
| 2 | 富文本 `attributedText`：颜色、粗体、字号、下划线、背景色、删除线 / 双删除线 / 删除线颜色、字间距、段落行距与首行缩进、`shadowRadius` 阴影 |
| 3 | 内边距 `textInsets` + 垂直对齐 `verticalAlignment`：固定高度的 label 切换内边距与 top / center / bottom |
| 4 | 行数与截断：1 行 / 2 行 / 不限，尾部 / 头部 / 中间截断，`attributedTruncationToken` 自定义「…更多」 |
| 5 | 链接：`.link` 属性、`addLink(to:range:)`、`addLink(range:onTap:)` 计数、自定义样式的 `ZLLabelLink`（橙色胶囊，按下变深） |
| 6 | 自动识别 `enabledTextCheckingTypes`：网址、电话、日期、地址 |
| 7 | 长按链接：`onLongPress` 与 delegate 的 `didLongPress`，调整 `minimumPressDuration` |
| 8 | 扩大点击热区 `extendsLinkTouchArea`：开关对比，行距较大时点击链接上下的空白 |
| 9 | 失活样式 `inactiveLinkAttributes`：弹出 alert 时链接变灰 |
| 10 | 高亮 `isHighlighted` / `highlightedTextColor` |
| 11 | 尺寸与定位：点击文字用 `characterIndex(at:)` + `boundingRect(forCharacterRange:)` 框出所在的词；Frame 布局下用 `sizeThatFits` 计算高度 |
| 12 | VoiceOver：打印 `accessibilityElements`，链接单独聚焦，`accessibilityHintText` |
| 13 | 字号自适应 `adjustsFontSizeToFitWidth`：单行标题（带链接）、2 行、固定高度三个 label；切换宽度、开关、`minimumScaleFactor`，实时显示 `currentFontScaleFactor` |

## Author

fanpeng, 25514129393@qq.com

## License

ZLRichLabel is available under the MIT license. See the LICENSE file for more info.
