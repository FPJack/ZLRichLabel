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
- **轻量标记**：简易 Markdown（加粗、删除线、行内代码）等自定义语法

Swift 与 Objective-C 均可使用，基于 [TTTAttributedLabel](https://github.com/TTTAttributedLabel/TTTAttributedLabel)，分为两层：

| 类 | 作用 |
| --- | --- |
| `ZLRichLabel` | 基类。用**正则规则**解析文本，命中内容交给外部渲染（样式 / 替换文字 / 图片 / 自定义 View / 点击 / 按下高亮），重叠时按优先级取舍 |
| `ZLTagRichLabel` | 继承 `ZLRichLabel`。内置 `<h>`、`<h1>`、`<h2>` … 标签规则，按标签名区分样式、按下高亮与点击，常用于「用户协议 / 隐私政策」之类的高亮文案 |

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
- 容错：开闭不匹配、未闭合的标签原样显示，不影响后面的标签
- 多行截断（自定义省略符）、Auto Layout 自适应高度
- RTL：阿拉伯语 / 希伯来语等从右到左文本自动右对齐，支持双向混排
- Objective-C 可用

## 环境要求

- iOS 10.0+（见 podspec；Example 工程使用 iOS 15.0）
- Swift 5.0
- 依赖 `TTTAttributedLabel`

## 安装

```ruby
pod 'ZLRichLabel'
```

源码结构：

```text
ZLRichLabel/Classes/
├── ZLRichDefines.swift    样式类型 HTagTextStyle、内嵌 View 配置 HTagWidget
├── ZLRichRule.swift       TagRichRule / TagRichMatch / TagRichRuleContext / TagRichParser
├── ZLRichLabel.swift      基类：规则解析、渲染、内嵌 View、布局、截断、RTL
└── ZLTagRichLabel.swift   <h> 标签子类、HTagInfo、HTagParser
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
        let user = ctx.matchedText
        ctx.onTap = { print("open", user) }
    }

    // 链接：NSDataDetector 也可以作为规则，替换展示文字
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        v.addRule(TagRichRule(name: "link", regex: detector, priority: 10) { ctx in
            let url = ctx.match.result.url
            ctx.setText("🔗网页链接", attributes: [.foregroundColor: UIColor.systemBlue])
            ctx.onTap = { if let url = url { UIApplication.shared.open(url) } }
        })
    }

    v.text = "Hi @alice, see https://www.apple.com"
}
```

## 自定义规则

### 创建规则

```swift
// 正则字符串（非法时抛错）
let rule = try TagRichRule(name: "topic", pattern: "#[^#\\s]+#", options: [], priority: 5) { ctx in ... }

// 已有的 NSRegularExpression / NSDataDetector
let rule = TagRichRule(name: "link", regex: detector, priority: 10) { ctx in ... }

label.addRule(rule)                // 同名规则会被替换
label.removeRule(named: "topic")
label.removeAllRules()             // 只移除外部规则，不影响子类内置规则
```

规则 handler 在**每次渲染时**都会调用（修改样式、文字、`rebuild()` 等），不要在里面做耗时操作。

### TagRichRuleContext

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
| `onTap` | 设置后整段可点击（含其中的图片和 `tappable` 的 View） |
| `highlightStyle` | 按下高亮，`nil` 使用 label 的 `highlightStyle`，`[:]` 不高亮 |

插入图片：直接放 `NSTextAttachment` 即可，组件会自动转换成 `UIImageView` 显示（TTTAttributedLabel 本身不绘制 attachment）：

```swift
try? label.addRule(name: "emoji", pattern: "\\[(smile|heart)\\]") { ctx in
    guard let key = ctx.group(1),
          let image = UIImage(systemName: key == "smile" ? "face.smiling" : "heart.fill") else { return }
    let attachment = NSTextAttachment()
    attachment.image = image.withRenderingMode(.alwaysTemplate)
    attachment.bounds = CGRect(x: 0, y: 0, width: 17, height: 17)
    ctx.attributedString.setAttributedString(NSAttributedString(attachment: attachment))
    ctx.onTap = { print("emoji", key) }
}
```

插入任意 View：

```swift
try? label.addRule(name: "vip", pattern: "\\[vip\\]") { ctx in
    let badge = UILabel()
    badge.text = "VIP"
    let widget = HTagWidget(view: badge, size: CGSize(width: 30, height: 16), alignment: .middle)
    ctx.attributedString.setAttributedString(ctx.attachmentString(for: widget))
}
```

### 自定义 View 尺寸变化

内嵌的自定义 View（`HTagWidget` / `attachmentString(for:)` / `tagWidgetBuilder`）尺寸或内容变化后，label 会重新排版：后面的文字跟着移动、换行，label 高度同步更新（Auto Layout 下会触发外部重新布局）。只替换占位尺寸，**不会**重新执行规则 handler / builder，已有的点击和链接保持不变。

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
- 之后如果 label `rebuild()`（修改样式、文字等），builder / handler 会重新执行，View 尺寸以新返回的 `HTagWidget` 为准。需要保留变化后的状态时，请把状态存在外部，builder 按状态创建 View（见 Example 用例 21）

> ⚠️ 不要在 `onTap` 中强引用 `ctx`（`ctx` 持有 `onTap` 会形成循环引用），先把需要的值取出来再捕获。

### 优先级

多条规则的命中范围重叠时：

1. `priority` 大的优先
2. 同优先级：位置靠前的优先 → 匹配更长的优先 → 先添加的优先（子类内置规则排在外部规则之前）
3. 被淘汰的命中**整体作废**，其中的文字按普通文本或其他规则处理，不做嵌套解析

```swift
// "Call <h1>13800138000</h1>"
label.hTagPriority = 0     // phone(20) 优先 → <h1> 标签作废，原样显示
label.hTagPriority = 100   // <h1> 优先 → 里面的手机号不再被 phone 规则处理
```

解析结果：

```swift
label.segments   // [ZLRichSegment]：普通文本 + 命中，按位置排序
label.matches    // [TagRichMatch]：最终生效的命中（含内置规则）
TagRichParser.resolve(text, rules: rules)   // 不创建 label，单独执行解析
```

## `<h>` 标签（ZLTagRichLabel）

### 写法

| 写法 | 结果 |
| --- | --- |
| `<h>文字</h>`、`<h1>文字</h1>`、`<h12>文字</h12>` | 标签，`name` 为小写标签名 |
| `<h1>文字<h1/>` | 同上（另一种闭合写法） |
| `<H4>文字</H4>` | 不区分大小写，`name == "h4"` |
| `<h1>文字</h2>`、`<h2>未闭合` | 原样显示，不影响后面的标签 |
| `<h1>a<h2>b</h2>c</h1>` | 不支持嵌套，只识别最内层 `<h2>b</h2>` |
| `<hx>文字</hx>` | 不是 h 标签，原样显示 |

### HTagInfo

| 属性 | 说明 |
| --- | --- |
| `index` | 第几个标签（从 0 开始，所有标签名统一计数） |
| `name` | 小写标签名：`h`、`h1`、`h2` … |
| `level` | `h` 后的数字，`<h>` 为 `nil` |
| `text` | 标签内文字 |
| `raw` | 完整原始标签字符串 |

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
    return HTagWidget(view: dot, size: CGSize(width: 6, height: 6), position: .after)
}
```

View 的尺寸或内容变化后会自动 / 手动刷新排版，见 [自定义 View 尺寸变化](#自定义-view-尺寸变化)。

`HTagWidget` 参数：

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

### 其他

```swift
label.parsesHTags = false            // 关闭 <h> 解析，只用自定义规则
label.onParsed = { tags in ... }     // 解析完成后异步回调所有标签
label.tags                           // 当前所有标签 [HTagInfo]
label.ruleMatches                    // 当前所有自定义规则命中（不含 <h> 标签）
HTagParser.tags("<h1>a</h1>")        // 独立解析，不创建 label
```

## 通用配置

| API | 说明 |
| --- | --- |
| `text` | 设置 `String` 按规则解析；设置 `NSAttributedString` 不解析，按 TTTAttributedLabel 原逻辑显示；`nil` 清空。读取得到渲染后的文字 |
| `rawText` / `tagText` | 原始字符串 |
| `style` | 普通文本样式（未设置 font / foregroundColor 时使用 label 的 `font` / `textColor`） |
| `highlightStyle` | 默认按下高亮样式（`ZLTagRichLabel.tagHighlightStyle` 即此属性） |
| `truncationToken` | 截断省略符，默认带普通文本样式的 `…` |
| `numberOfLines` / `lineBreakMode` | 多行与截断 |
| `update { }` / `beginUpdates()` / `endUpdates()` | 批量修改，只渲染一次 |
| `rebuild()` | 强制重新渲染（如外部状态变化后需要重新调用 builder / handler） |
| `invalidateAttachmentLayout()` / `invalidateLayout(forAttachmentView:)` | 自定义 View 尺寸 / 内容变化后刷新排版（不重新执行 builder / handler） |
| `isRightToLeft` | 当前内容是否为 RTL |

布局：

- Auto Layout：设置宽度约束即可，高度由 `intrinsicContentSize` 计算
- Frame 布局：`label.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))`
- RTL：`textAlignment` 为 `.natural`（默认）时，按内容的第一个强方向字符自动左 / 右对齐

xib / storyboard 中设置的文字同样会被解析。

## 继承 ZLRichLabel 实现自己的规则组件

`ZLTagRichLabel` 就是这样实现的：重写 `builtInRules` 提供内置规则，配置变化时调用 `setNeedsReparse()` / `setNeedsRebuild()`。

```swift
final class MentionLabel: ZLRichLabel {

    var mentionColor: UIColor = .systemBlue { didSet { setNeedsRebuild() } }   // 只影响渲染
    var onMentionTap: ((String) -> Void)?

    private lazy var mentionRule = TagRichRule(name: "mention",
                                               regex: try! NSRegularExpression(pattern: "@\\w+")) { [weak self] ctx in
        guard let self = self else { return }
        ctx.addAttributes([.foregroundColor: self.mentionColor])
        let user = ctx.matchedText
        ctx.onTap = { [weak self] in self?.onMentionTap?(user) }
    }

    override var builtInRules: [TagRichRule] {
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

## Objective-C

所有公开类型都是 `NSObject` 子类或 `@objc` 枚举，`@import ZLRichLabel;` 即可使用。

```objc
@import ZLRichLabel;

ZLTagRichLabel *label = [[ZLTagRichLabel alloc] initWithFrame:CGRectZero];
label.numberOfLines = 0;

// update: 的回调参数是基类 ZLRichLabel，需要转成实际类型
[label update:^(ZLRichLabel *base) {
    ZLTagRichLabel *v = (ZLTagRichLabel *)base;
    v.style = @{NSFontAttributeName: [UIFont systemFontOfSize:15]};
    v.tagStyles = @{@"h1": @{NSForegroundColorAttributeName: UIColor.systemBlueColor}};
    v.tagHighlightStyles = @{@"h1": @{NSBackgroundColorAttributeName: UIColor.yellowColor}};

    // tagTapHandlers 在 OC 中不可用，使用 setTapHandler:forTag:
    [v setTapHandler:^(HTagInfo *info) { NSLog(@"h1 %@", info.text); } forTag:@"h1"];
    v.onTagTap = ^(HTagInfo *info) { NSLog(@"%@ level=%@", info.name, info.level); };

    [v addRuleWithName:@"mention" pattern:@"@\\w+" options:0 priority:10 error:nil
               handler:^(TagRichRuleContext *ctx) {
        [ctx addAttributes:@{NSForegroundColorAttributeName: UIColor.systemPurpleColor}];
        NSString *user = ctx.matchedText;              // 不要在 onTap 里强引用 ctx
        ctx.onTap = ^{ NSLog(@"mention %@", user); };
    }];

    v.text = @"Agree to <h1>User Agreement</h1>, cc @bob";
}];
```

| Swift | Objective-C |
| --- | --- |
| `label.update { v in }` | `[label update:^(ZLRichLabel *v) {}]`（或 `beginUpdates` / `endUpdates`） |
| `tagTapHandlers = [...]` | `setTapHandler:forTag:` / `removeTapHandlerForTag:` |
| `addRule(name:pattern:options:priority:handler:)` | `addRuleWithName:pattern:options:priority:error:handler:` |
| `removeRule(named:)` | `removeRuleNamed:` |
| `ctx.group(1)` / `ctx.group(named:)` | `[ctx groupAtIndex:1]` / `[ctx groupNamed:]` |
| `info.level`（`Int?`） | `info.level`（`NSNumber *`，`<h>` 时为 `nil`） |
| `TagRichParser.resolve(_:rules:)` | `[TagRichParser matchesInString:rules:]` |
| `view.zl_setNeedsRichLabelLayout()` | `[view zl_setNeedsRichLabelLayout]` |
| `invalidateLayout(forAttachmentView:)` | `invalidateLayoutForAttachmentView:` |

## Example

```bash
cd Example
pod install
open ZLRichLabel.xcworkspace
```

示例 App 包含 Swift（`HTagDemoPage.swift`）和 Objective-C（`OCDemoViewController.m`，导航栏左上角「OC」进入）两个版本，内容一致：

| 用例 | 内容 |
| --- | --- |
| 1 – 10 | `ZLTagRichLabel`：按标签名样式、按 index 样式、闭合写法与大小写、按标签名点击、按下高亮、容错、图标、无点击、多行截断、自定义 View |
| 11 | 自定义 View 自己处理交互（勾选框，`tappable: false`） |
| 12 – 16 | 阿拉伯语 RTL：样式与点击、双向混排、截断、自定义 View / 图标、勾选框 |
| 17、18、20 | `ZLRichLabel` 自定义规则：@提及 / #话题# / 链接、表情图片 / 模板变量、简易 Markdown |
| 19 | `ZLTagRichLabel`：`<h>` 标签与自定义规则的优先级 |
| 21 | 自定义 View 尺寸变化自动刷新排版：点击色块改 frame 变宽、点赞计数文字变化 |

页面顶部会显示最近一次点击得到的完整信息，底部有点击历史。

## Author

fanpeng, 25514129393@qq.com

## License

ZLRichLabel is available under the MIT license. See the LICENSE file for more info.
