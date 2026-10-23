//
//  ViewController.swift
//  GMTagRichView
//
//  Created by fanpeng on 10/22/2026.
//  Copyright (c) 2026 fanpeng. All rights reserved.
//

import UIKit
import ZLRichLabel

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let label = ZLTagRichLabel(frame: CGRect(x: 20, y: 100, width: view.bounds.width - 40, height: 120))
        label.autoresizingMask = [.flexibleWidth]
        label.numberOfLines = 0
        label.verticalAlignment = .top
        label.update { v in
            v.style = [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.gray]
            v.tagStyle = [.foregroundColor: UIColor.blue]
            v.tagHighlightStyle = [.foregroundColor: UIColor.lightGray]
            v.tagStyles = [
                "h2": [.foregroundColor: UIColor.red, .underlineStyle: NSUnderlineStyle.single.rawValue],
            ]
            v.tagWidgetBuilder = { info, _ in
                guard info.name == "h3" else { return nil }
                let icon = UIView()
                icon.backgroundColor = .orange
                icon.layer.cornerRadius = 8
                return HTagWidget(view: icon, size: CGSize(width: 16, height: 16), position: .before)
            }
            v.tagTapHandlers = ["h1": { info in print("open agreement: \(info)") }]
            v.onTagTap = { info in print("tap: \(info)") }
            v.onParsed = { tags in print("parsed: \(tags)") }
            v.text = "I have read and agree to the <h1>User Agreement</h1>, <h2>Privacy Policy</h2> and <h3>Help Center</h3>."
        }
        view.addSubview(label)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

