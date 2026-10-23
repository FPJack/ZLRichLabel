//
//  SwiftUIDemoPage.swift
//  ZLRichLabel_Example
//
//  SwiftUI 封装 ZLRichText 演示：高度自适应、点击回调、动态文字、展开 / 收起、lineLimit、List
//

import SwiftUI
import UIKit
import ZLRichLabel

/// 从 UIKit 页面打开 SwiftUI 示例
enum SwiftUIDemo {
    static func makeViewController() -> UIViewController {
        let controller = UIHostingController(rootView: SwiftUIDemoPage())
        controller.title = "SwiftUI Demo"
        return controller
    }
}

struct SwiftUIDemoPage: View {
    @State private var lastEvent = "点击标签 / 话题，或展开文字，这里显示回调"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(lastEvent)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)

                DemoSection("1. 基础用法：标签样式 + 点击") {
                    BasicDemo(onEvent: report)
                }
                DemoSection("2. 动态文字：输入时高度实时变化") {
                    DynamicTextDemo()
                }
                DemoSection("3. 展开 / 收起：与 @State 双向同步") {
                    ExpandDemo(onEvent: report)
                }
                DemoSection("4. .lineLimit(_:)") {
                    LineLimitDemo()
                }
                DemoSection("5. 规则 + 胶囊背景 + 渐变文字") {
                    DecorationDemo(onEvent: report)
                }
                DemoSection("6. List 中自适应行高") {
                    ListDemo()
                }
            }
            .padding(16)
        }
        .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
    }

    private func report(_ text: String) {
        lastEvent = text
    }
}

// MARK: - 卡片

private struct DemoSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
    }
}

private let demoStyle: HTagTextStyle = [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.label]

// MARK: - 1. 基础用法

private struct BasicDemo: View {
    let onEvent: (String) -> Void

    var body: some View {
        ZLRichText("我已阅读并同意<h1>《用户协议》</h1>和<h2>《隐私政策》</h2>，点击标签试试。", configure: { label in
            label.style = demoStyle
            label.tagStyles = ["h1": [.foregroundColor: UIColor.systemBlue],
                               "h2": [.foregroundColor: UIColor.systemRed]]
            label.tagHighlightStyle = [.backgroundColor: UIColor.systemGray4]
            label.onTagTap = { info in onEvent("onTagTap  <\(info.name)> \(info.text)") }
        })
    }
}

// MARK: - 2. 动态文字

private struct DynamicTextDemo: View {
    @State private var text = "输入文字，<h1>标签</h1>会实时高亮，高度跟着内容变化。"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZLRichText(text, configure: { label in
                label.style = demoStyle
                label.tagStyle = [.foregroundColor: UIColor.systemPurple,
                                  .underlineStyle: NSUnderlineStyle.single.rawValue]
            })
            .padding(8)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(6)

            TextField("输入带 <h1>…</h1> 的文字", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            HStack {
                Button("追加一句") { text += "再加一句很长的文字，看看换行后的高度。" }
                Spacer()
                Button("重置") { text = "输入文字，<h1>标签</h1>会实时高亮。" }
            }
            .font(.footnote)
        }
    }
}

// MARK: - 3. 展开 / 收起

private struct ExpandDemo: View {
    let onEvent: (String) -> Void
    @State private var isExpanded = false

    private let text = "SwiftUI 中使用 ZLRichText：label 内部点击「全文」展开后，"
        + "通过 onExpandChanged 回调同步到 @State；外部按钮修改 @State 后，通过 update 闭包同步回 label。"
        + "无论哪一边改变，高度都会自动重新计算。<h1>标签</h1>照常可以点击。"
        + "这里再多写一些文字，保证收起时一定会被截断。"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZLRichText(text, configure: { label in
                label.style = demoStyle
                label.numberOfLines = 2
                label.expandToken = NSAttributedString(string: "… 全文", attributes: [.foregroundColor: UIColor.systemOrange])
                label.collapseToken = NSAttributedString(string: " 收起", attributes: [.foregroundColor: UIColor.systemOrange])
                label.tagStyle = [.foregroundColor: UIColor.systemBlue]
                label.onTagTap = { info in onEvent("onTagTap  \(info.text)") }
                label.onExpandChanged = { expanded in
                    isExpanded = expanded
                    onEvent("onExpandChanged(\(expanded))")
                }
            }, update: { label in
                // 设置 isExpanded 不会触发 onExpandChanged，不会循环
                if label.isExpanded != isExpanded { label.isExpanded = isExpanded }
            })
            .animation(.easeInOut(duration: 0.25), value: isExpanded)

            Toggle("isExpanded（@State）", isOn: $isExpanded)
                .font(.footnote)
        }
    }
}

// MARK: - 4. lineLimit

private struct LineLimitDemo: View {
    @State private var limit = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZLRichText("SwiftUI 的 .lineLimit(_:) 会同步到 numberOfLines。"
                       + "<h1>这段文字比较长</h1>，用下面的步进器调整显示的行数，0 表示不限制。"
                       + "超出的部分显示省略号，高度跟着行数变化。", configure: { label in
                label.style = demoStyle
                label.tagStyle = [.foregroundColor: UIColor.systemTeal]
            })
            .lineLimit(limit == 0 ? nil : limit)

            Stepper("lineLimit = \(limit == 0 ? "nil" : "\(limit)")", value: $limit, in: 0...5)
                .font(.footnote)
        }
    }
}

// MARK: - 5. 规则 + 胶囊 + 渐变

private struct DecorationDemo: View {
    let onEvent: (String) -> Void

    var body: some View {
        ZLRichText("<grad>ZLRichText for SwiftUI</grad>\n"
                   + "话题 #SwiftUI# #UIKit# 可以点击，@alice 是提及，`label.text` 是行内代码。", configure: { label in
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 6
            label.style = demoStyle.merging([.paragraphStyle: paragraph]) { $1 }
            label.tagNamePattern = "grad"
            label.tagStyles = ["grad": [.font: UIFont.boldSystemFont(ofSize: 20),
                                        .zlGradient: ZLTextGradient(colors: [.systemPink, .systemOrange, .systemPurple])]]
            try? label.addRule(name: "topic", pattern: "#[^#\\s]+#") { ctx in
                let topic = ctx.matchedText
                ctx.addAttributes([.foregroundColor: UIColor.systemPurple,
                                   .zlBackground: ZLTextBackground.capsule(.systemPurple)])
                ctx.highlightStyle = [.zlBackground: ZLTextBackground(fillColor: UIColor.systemPurple.withAlphaComponent(0.3))]
                ctx.onTap = { onEvent("话题 \(topic)") }
            }
            try? label.addRule(name: "mention", pattern: "@\\w+") { ctx in
                let user = ctx.matchedText
                ctx.setText("👤" + user.dropFirst(), attributes: [.foregroundColor: UIColor.systemIndigo])
                ctx.onTap = { onEvent("提及 \(user)") }
            }
            try? label.addRule(name: "code", pattern: "`([^`]+)`") { ctx in
                ctx.setText(ctx.group(1) ?? "", attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .zlBackground: ZLTextBackground.code,
                ])
            }
        })
    }
}

// MARK: - 6. List

private struct ListDemo: View {
    private let rows: [String] = (1...8).map { i in
        let body = String(repeating: "列表行内容，", count: i * 2)
        return "<h1>第 \(i) 行</h1> \(body)每行高度不同。"
    }

    var body: some View {
        List(rows.indices, id: \.self) { index in
            ZLRichText(rows[index], configure: { label in
                label.style = demoStyle
                label.tagStyle = [.foregroundColor: UIColor.systemGreen, .font: UIFont.boldSystemFont(ofSize: 15)]
            })
            .padding(.vertical, 4)
        }
        .listStyle(PlainListStyle())
        .frame(height: 360)
    }
}
