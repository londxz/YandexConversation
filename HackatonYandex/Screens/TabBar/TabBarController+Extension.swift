//
//  TabBarController+Extension.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

extension TabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if let chatVC = viewController as? ChatVC {
            chatVC.dismissLargeTextDisplayIfNeeded()
        }
    }
}
