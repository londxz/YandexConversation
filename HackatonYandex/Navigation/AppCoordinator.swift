//
//  AppCoordinator.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

final class AppCoordinator: Coordinator {
    private let window: UIWindow
    private let container: AppContainer

    init(window: UIWindow, container: AppContainer) {
        self.window = window
        self.container = container
    }

    func start() {
        if container.appStateStore.hasSeenOnboarding {
            showMain(animated: false)
        } else {
            showOnboarding(animated: false)
        }

        window.makeKeyAndVisible()
    }

    private func showOnboarding(animated: Bool) {
        let onboardingVC = OnboardingPageVC(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )

        onboardingVC.onFinish = { [weak self] in
            guard let self else { return }
            self.container.appStateStore.hasSeenOnboarding = true
            self.showMain(animated: true)
        }

        setRoot(onboardingVC, animated: animated)
    }

    private func showMain(animated: Bool) {
        let tabBarController = TabBarController(container: container)
        setRoot(tabBarController, animated: animated)
    }

    private func setRoot(_ viewController: UIViewController, animated: Bool) {
        guard animated else {
            window.rootViewController = viewController
            return
        }

        UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve) {
            self.window.rootViewController = viewController
        }
    }
}
