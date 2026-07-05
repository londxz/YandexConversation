//
//  OnboardingPageVC.swift
//  HackatonYandex
//
//  Created by Родион Холодов on 01.06.2025.
//

import UIKit

class OnboardingPageVC: UIPageViewController {
    private var pagesDataSource: [OnboardingPageModel] = []
    private var currentIndex = 0
    var onFinish: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        delegate = self
        view.backgroundColor = .white

        pagesDataSource = [
            OnboardingPageModel(imageName: "onboardingIcon1", title: "Разговаривайте с помощью текста", subtitle: "Приложение покажет на экране, что говорит собеседник. А вы можете написать ответ и озвучить его голосом.", isLast: false),
            OnboardingPageModel(imageName: "onboardingIcon2", title: "Читайте речь вокруг вас", subtitle: "Откройте приложение, и оно начнёт превращать в текст речь одного или более спикеров. Удобно, когда нужно только слушать.", isLast: false),
            OnboardingPageModel(imageName: "onboardingIcon3", title: "Быстрые фразы под рукой", subtitle: "Показывайте или озвучивайте заранее сохранённые фразы.", isLast: true)
        ]
        
        showPage(index: 0)
    }

    func showPage(index: Int, direction: UIPageViewController.NavigationDirection = .forward) {
        currentIndex = index

        let pageVC = OnboardingContentVC(page: pagesDataSource[index], pageIndex: index)
        pageVC.onNext = { [weak self] in
            guard let self = self else { return }
            if index < self.pagesDataSource.count - 1 {
                self.showPage(index: index + 1, direction: .forward)
            } else {
                self.finishOnboarding()
            }
        }
        pageVC.onSkip = { [weak self] in
            self?.finishOnboarding()
        }
        setViewControllers([pageVC], direction: direction, animated: true, completion: nil)
    }

    func finishOnboarding() {
        onFinish?()
    }
}

extension OnboardingPageVC: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let contentVC = viewController as? OnboardingContentVC else { return nil }
        let previousIndex = contentVC.pageIndex - 1
        guard pagesDataSource.indices.contains(previousIndex) else { return nil }
        return makeContentViewController(index: previousIndex)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let contentVC = viewController as? OnboardingContentVC else { return nil }
        let nextIndex = contentVC.pageIndex + 1
        guard pagesDataSource.indices.contains(nextIndex) else { return nil }
        return makeContentViewController(index: nextIndex)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard
            completed,
            let contentVC = viewControllers?.first as? OnboardingContentVC
        else { return }

        currentIndex = contentVC.pageIndex
    }

    private func makeContentViewController(index: Int) -> OnboardingContentVC {
        let pageVC = OnboardingContentVC(page: pagesDataSource[index], pageIndex: index)
        pageVC.onNext = { [weak self] in
            guard let self else { return }
            if index < self.pagesDataSource.count - 1 {
                self.showPage(index: index + 1, direction: .forward)
            } else {
                self.finishOnboarding()
            }
        }
        pageVC.onSkip = { [weak self] in
            self?.finishOnboarding()
        }
        return pageVC
    }
}
