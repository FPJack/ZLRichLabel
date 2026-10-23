//
//  SceneDelegate.swift
//  ZLRichLabel
//
//  Created by fanpeng on 10/23/2026.
//  Copyright (c) 2026 fanpeng. All rights reserved.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // 默认入口：HTagDemoPage（需要导航栏，包一层 UINavigationController）
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: HTagDemoPage())
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // 场景被系统释放时调用
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // 场景从非活跃状态变为活跃状态时调用
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // 场景即将从活跃状态变为非活跃状态时调用（如来电）
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // 场景从后台进入前台时调用
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // 场景进入后台时调用
    }
}
