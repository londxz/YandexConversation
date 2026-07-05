//
//  TabBarController.swift
//  HackatonYandex
//
//  Created by Родион Холодов on 01.06.2025.
//

import UIKit

class TabBarController: UITabBarController {
    private let container: AppContainer

    init(container: AppContainer = AppContainer()) {
        self.container = container
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.container = AppContainer()
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        
        let firstVC = ChatVC(container: container)
        let secondVC = PhrasesViewController(container: container)
        let thirdVC = SettingsViewController(container: container)

        firstVC.tabBarItem = makeTabBarItem(
            imageName: "tabBarIcon1Disabled",
            selectedImageName: "tabBarIcon1Enabled",
            accessibilityLabel: "Разговор и слушание"
        )

        secondVC.tabBarItem = makeTabBarItem(
            imageName: "tabBarIcon2Disabled",
            selectedImageName: "tabBarIcon2Enabled",
            accessibilityLabel: "Фразы"
        )

        thirdVC.tabBarItem = makeTabBarItem(
            imageName: "tabBarIcon3Disabled",
            selectedImageName: "tabBarIcon3Enabled",
            accessibilityLabel: "Настройки"
        )

        viewControllers = [firstVC, secondVC, thirdVC]
    }

    private func makeTabBarItem(
        imageName: String,
        selectedImageName: String,
        accessibilityLabel: String
    ) -> UITabBarItem {
        let item = UITabBarItem(
            title: nil,
            image: UIImage(named: imageName)?.withRenderingMode(.alwaysOriginal),
            selectedImage: UIImage(named: selectedImageName)?.withRenderingMode(.alwaysOriginal)
        )

        item.accessibilityLabel = accessibilityLabel
        item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
        item.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 100)
        return item
    }
}
