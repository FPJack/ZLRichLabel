//
//  ZLRichText.swift
//  ZLRichLabel
//
//  SwiftUI 封装：ZLRichText，高度自适应
//
//  ```swift
//  ZLRichText("同意 <h1>用户协议</h1> 和 #话题#", configure: { label in
//      // 只在创建时执行一次：加规则、设样式和回调
//      label.tagStyles = ["h1": [.foregroundColor: UIColor.systemBlue]]
//      label.onTagTap = { info in print(info.text) }
//      try? label.addRule(name: "topic", pattern: "#[^#\\s]+#") { ctx in
//          ctx.addAttributes([.zlBackground: ZLTextBackground.capsule(.systemPurple)])
//      }
//  }, update: { label in
//      // 每次 SwiftUI 刷新都会执行：同步会变化的状态
//      label.isExpanded = isExpanded
//  })
//  .lineLimit(3)
//  ```
//
//  - iOS 16+：通过 `sizeThatFits(_:uiView:context:)` 按 SwiftUI 提供的宽度计算高度
//  - iOS 13 ~ 15：用 GeometryReader 读取宽度后测量高度，占满可用宽度
//  - label 内部内容变化（展开 / 收起、自定义 View 尺寸变化、Dynamic Type 等）后自动重新计算高度
//

#if canImport(SwiftUI)
import SwiftUI
import UIKit

@available(iOS 13.0, *)
public struct ZLRichText: View {

    /// 配置 label 的闭包
    public typealias Configure = (ZLTagRichLabel) -> Void

    /// 仅用于测试：强制使用 iOS 13 ~ 15 的高度计算方式
    public static var _usesLegacySizing = false

    private let text: String
    private let configure: Configure?
    private let update: Configure?

    @State private var layoutVersion = 0
    @State private var legacyWidth: CGFloat = 0
    @State private var legacyHeight: CGFloat = 0

    /// - Parameters:
    ///   - text: 原始文本（可包含标签，规则在 `configure` 中添加）
    ///   - configure: 创建 label 时执行一次：添加规则、设置样式与回调。
    ///     回调里请通过 `Binding` / 引用类型修改外部状态
    ///   - update: 每次 SwiftUI 刷新时执行（在一次批量更新中，最后才设置 `text`），用于同步会变化的配置
    public init(_ text: String, configure: Configure? = nil, update: Configure? = nil) {
        self.text = text
        self.configure = configure
        self.update = update
    }

    public var body: some View {
        if #available(iOS 16.0, *), !ZLRichText._usesLegacySizing {
            representable(legacyWidth: 0)
        } else {
            representable(legacyWidth: legacyWidth)
                .frame(height: legacyHeight > 0 ? legacyHeight : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ZLRichTextWidthKey.self, value: proxy.size.width)
                })
                .onPreferenceChange(ZLRichTextWidthKey.self) { width in
                    if width != legacyWidth { legacyWidth = width }
                }
        }
    }

    private func representable(legacyWidth: CGFloat) -> ZLRichTextRepresentable {
        let height = $legacyHeight
        let version = $layoutVersion
        return ZLRichTextRepresentable(text: text,
                                       configure: configure,
                                       update: update,
                                       layoutVersion: layoutVersion,
                                       legacyWidth: legacyWidth,
                                       onLegacyHeight: { value in
                                           if height.wrappedValue != value { height.wrappedValue = value }
                                       },
                                       onLayoutChange: { version.wrappedValue += 1 })
    }
}

@available(iOS 13.0, *)
private struct ZLRichTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@available(iOS 13.0, *)
struct ZLRichTextRepresentable: UIViewRepresentable {
    let text: String
    let configure: ZLRichText.Configure?
    let update: ZLRichText.Configure?
    /// 内容变化后递增，让 SwiftUI 重新计算尺寸
    let layoutVersion: Int
    /// iOS 13 ~ 15：外部测得的宽度，> 0 时在更新后测量高度并通过 `onLegacyHeight` 回调
    let legacyWidth: CGFloat
    let onLegacyHeight: (CGFloat) -> Void
    let onLayoutChange: () -> Void

    final class Coordinator {
        /// 上一次计算尺寸时的宽度与结果（用于判断内容变化后尺寸是否真的变了）
        var lastWidth: CGFloat = 0
        var lastSize: CGSize = .zero
        /// 上一次应用的 SwiftUI lineLimit（nil 表示没有应用过）
        var appliedLineLimit: Int??
        var onLayoutChange: (() -> Void)?
        private var scheduled = false

        func size(of label: ZLRichLabel, width: CGFloat) -> CGSize {
            let fit = label.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            return CGSize(width: min(ceil(fit.width), width), height: ceil(fit.height))
        }

        /// label 尺寸失效：下一轮 RunLoop 按上次的宽度重新测量，尺寸变化时通知 SwiftUI
        func labelDidInvalidate(_ label: ZLRichLabel?) {
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self, weak label] in
                guard let self = self else { return }
                self.scheduled = false
                guard let label = label, self.lastWidth > 0 else { return }
                let size = self.size(of: label, width: self.lastWidth)
                guard size != self.lastSize else { return }
                self.lastSize = size
                self.onLayoutChange?()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    func makeUIView(context: Context) -> ZLTagRichLabel {
        let label = ZLTagRichLabel(frame: .zero)
        label.numberOfLines = 0
        label.backgroundColor = .clear
        // 宽度由 SwiftUI 决定
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        if let configure = configure {
            label.update { configure($0) }
        }
        let coordinator = context.coordinator
        label.intrinsicSizeObserver = { [weak label, weak coordinator] in
            coordinator?.labelDidInvalidate(label)
        }
        return label
    }

    func updateUIView(_ label: ZLTagRichLabel, context: Context) {
        let coordinator = context.coordinator
        coordinator.onLayoutChange = onLayoutChange
        let lineLimit = context.environment.lineLimit

        label.update { v in
            // SwiftUI 的 .lineLimit(_:)：只在变化时应用，不覆盖 configure 中设置的行数
            if coordinator.appliedLineLimit == nil || coordinator.appliedLineLimit! != lineLimit {
                if let limit = lineLimit {
                    v.numberOfLines = limit
                } else if coordinator.appliedLineLimit != nil {
                    v.numberOfLines = 0
                }
                coordinator.appliedLineLimit = .some(lineLimit)
            }
            update?(v)
            if v.rawText != text { v.text = text }
        }

        if legacyWidth > 0 {
            let size = coordinator.size(of: label, width: legacyWidth)
            coordinator.lastWidth = legacyWidth
            coordinator.lastSize = size
            let callback = onLegacyHeight
            // 不能在 SwiftUI 更新视图的过程中修改 State
            DispatchQueue.main.async { callback(size.height) }
        }
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ZLTagRichLabel, context: Context) -> CGSize? {
        let maxWidth: CGFloat = 100000
        let width = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? maxWidth
        let size = context.coordinator.size(of: uiView, width: width)
        context.coordinator.lastWidth = width
        context.coordinator.lastSize = size
        return size
    }
}
#endif
