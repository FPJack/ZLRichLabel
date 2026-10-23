import XCTest
import ZLRichLabel

/// 自定义 View 尺寸变化后刷新排版
class AttachmentResizeTests: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    /// 创建 label：`[box]` 替换为传入的 View；`@x` 为可点击规则（用于验证链接不丢失）
    private func makeLabel(widget: @escaping () -> HTagWidget) -> ZLRichLabel {
        let label = ZLRichLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 0))
        label.numberOfLines = 0
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 15)]
            try? v.addRule(name: "box", pattern: "\\[box\\]") { ctx in
                ctx.attributedString.setAttributedString(ctx.attachmentString(for: widget()))
            }
            try? v.addRule(name: "mention", pattern: "@x") { ctx in
                ctx.onTap = {}
            }
            v.text = "Hello [box] world, some words @x"
        }
        window.addSubview(label)
        fit(label)
        return label
    }

    private func fit(_ label: ZLRichLabel) {
        label.frame.size.height = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height
        window.layoutIfNeeded()
        label.layoutIfNeeded()
    }

    /// 外部直接修改 View 的 frame 尺寸：label 下次布局自动刷新
    func testExternalFrameChangeReflows() {
        let box = UIView()
        let label = makeLabel { HTagWidget(view: box, size: CGSize(width: 20, height: 14)) }
        XCTAssertEqual(box.frame.size, CGSize(width: 20, height: 14))
        let heightBefore = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height
        let linksBefore = label.links.count

        box.frame.size = CGSize(width: 150, height: 30)
        label.layoutIfNeeded()

        XCTAssertEqual(box.bounds.size, CGSize(width: 150, height: 30))
        let heightAfter = label.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(heightAfter, heightBefore, "View 变宽后文字应换行，高度增加")
        XCTAssertEqual(label.links.count, linksBefore, "刷新排版不应丢失链接")

        // 布局稳定：再次布局尺寸不变
        fit(label)
        XCTAssertEqual(box.bounds.size, CGSize(width: 150, height: 30))
        XCTAssertFalse(box.isHidden)
    }

    /// 自动尺寸的 View 内容变化：调用 zl_setNeedsRichLabelLayout 重新测量
    func testAutoSizeContentChange() {
        let badge = UILabel()
        badge.font = .systemFont(ofSize: 12)
        badge.text = "1"
        let label = makeLabel { HTagWidget(view: badge) }   // size == .zero 自动计算
        let widthBefore = badge.bounds.width
        XCTAssertGreaterThan(widthBefore, 0)

        badge.text = "123456789"
        badge.zl_setNeedsRichLabelLayout()
        label.layoutIfNeeded()

        XCTAssertGreaterThan(badge.bounds.width, widthBefore)
        XCTAssertEqual(badge.bounds.size, badge.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                                    height: CGFloat.greatestFiniteMagnitude)))
    }

    /// 从内部子 View 调用也能找到所在的 label
    func testInvalidateFromNestedSubview() {
        let container = UIView()
        let inner = UIView()
        container.addSubview(inner)
        let label = makeLabel { HTagWidget(view: container, size: CGSize(width: 20, height: 14)) }

        container.bounds.size = CGSize(width: 60, height: 14)
        inner.zl_setNeedsRichLabelLayout()
        label.layoutIfNeeded()

        XCTAssertEqual(container.frame.size, CGSize(width: 60, height: 14))
    }

    /// 固定尺寸且未被外部修改：invalidate 不改变尺寸
    func testFixedSizeUnchangedWithoutExternalChange() {
        let box = UIView()
        let label = makeLabel { HTagWidget(view: box, size: CGSize(width: 20, height: 14)) }
        label.invalidateAttachmentLayout()
        label.layoutIfNeeded()
        XCTAssertEqual(box.frame.size, CGSize(width: 20, height: 14))
    }
}
