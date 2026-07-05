//
//  ChatVC.swift
//  HackatonYandex
//
//  Created by Родион Холодов on 01.06.2025.
//

import UIKit

class ChatVC: UIViewController {
    
    var chatComponentBottomConstraint: NSLayoutConstraint!
    var chatComponentHeightConstraint: NSLayoutConstraint!
    let quickPhrasePanelHeight: CGFloat = 306
    var isQuickPhrasePanelVisible = false
    private let container: AppContainer
    
    private let topChatComponent = TopChatComponent()
    private let containerView = UIView()
    let segmentControlComponent = SegmentControlComponent()
    let chatComponent = ChatComponent()
    lazy var quickPhrasePanel = QuickPhrasePanelView(
        fetchPhrasesUseCase: container.fetchPhrasesUseCase,
        recordPhraseUsageUseCase: container.recordPhraseUsageUseCase
    )
    lazy var presenter = ConversationPresenter(
        view: self,
        microphonePermissionService: container.microphonePermissionService,
        audioRecordingService: container.audioRecordingService,
        speechRecognitionService: container.speechRecognitionService,
        saveConversationUseCase: container.saveConversationUseCase,
        addConversationMessageUseCase: container.addConversationMessageUseCase
    )
    
    var typingHint: StartTypingHint?
    var microphoneHint: MicrophoneOnHint?
    
    private var currentChildVC: UIViewController?
    lazy var talkVC = TalkViewController(textToSpeechService: container.textToSpeechService)
    lazy var listenVC = ListenViewController()
    
    var microEnabledView: MicroEnabledView?
    var isViewRotated = false
    var currentConversationMode: ConversationMode = .talk

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
        view.backgroundColor = .backgroundYandex
        setupKeyboardObservers()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
        
        setupTopChatComponent()
        setupSegmentControlComponent()
        setupChatComponent()
        setupQuickPhrasePanel()
        setupContainerView()
        setupTopActions()
        
        segmentControlComponent.delegate = self
        talkVC.delegate = self
        chatComponent.delegate = self
        presenter.viewDidLoad()
    }
    
    deinit {
        removeKeyboardObservers()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        presenter.viewDidDisappear()
    }
    
    private func setupTopChatComponent() {
        view.addSubview(topChatComponent)
        topChatComponent.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topChatComponent.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topChatComponent.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topChatComponent.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topChatComponent.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func setupQuickPhrasePanel() {
        view.addSubview(quickPhrasePanel)
        quickPhrasePanel.translatesAutoresizingMaskIntoConstraints = false
        quickPhrasePanel.alpha = 0
        quickPhrasePanel.isHidden = true
        quickPhrasePanel.onSelectPhrase = { [weak self] text in
            self?.hideQuickPhrasePanel(animated: true)
            self?.presenter.didSubmitQuickPhrase(text)
        }

        NSLayoutConstraint.activate([
            quickPhrasePanel.topAnchor.constraint(equalTo: chatComponent.bottomAnchor),
            quickPhrasePanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            quickPhrasePanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            quickPhrasePanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func setupTopActions() {
        topChatComponent.leftNavButton.addTarget(self, action: #selector(historyTapped), for: .touchUpInside)
        topChatComponent.leftNavButton.accessibilityLabel = "Открыть историю разговоров"
        topChatComponent.rightNavButton.addTarget(self, action: #selector(newConversationTapped), for: .touchUpInside)
        topChatComponent.rightNavButton.accessibilityLabel = "Начать новый разговор"
    }
    
    private func setupSegmentControlComponent() {
        view.addSubview(segmentControlComponent)
        segmentControlComponent.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            segmentControlComponent.topAnchor.constraint(equalTo: topChatComponent.bottomAnchor, constant: 4),
            segmentControlComponent.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 11),
            segmentControlComponent.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -11),
            segmentControlComponent.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func setupContainerView() {
        view.addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: segmentControlComponent.bottomAnchor, constant: 12),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: chatComponent.topAnchor, constant: -6)
        ])
    }
    
    private func setupChatComponent() {
        view.addSubview(chatComponent)
        chatComponent.translatesAutoresizingMaskIntoConstraints = false
        
        chatComponentBottomConstraint = chatComponent.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        chatComponentHeightConstraint = chatComponent.heightAnchor.constraint(equalToConstant: 56)
        
        
        NSLayoutConstraint.activate([
            chatComponent.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatComponent.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatComponentHeightConstraint,
            chatComponentBottomConstraint
        ])
    }
    
    func switchToChild(_ newVC: UIViewController) {
        guard currentChildVC !== newVC else { return }

        if let current = currentChildVC {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        
        addChild(newVC)
        containerView.addSubview(newVC.view)
        newVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            newVC.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            newVC.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            newVC.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            newVC.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        newVC.didMove(toParent: self)
        
        currentChildVC = newVC
    }
    
    func dismissMicrophoneOverlayIfNeeded() {
        guard let overlay = microEnabledView else { return }
        
        UIView.animate(withDuration: 0.3, animations: {
            overlay.alpha = 0
            overlay.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }, completion: { _ in
            overlay.removeFromSuperview()
        })
        
        microEnabledView = nil
    }
    
    func resetRotationIfNeeded() {
        guard isViewRotated else { return }
        
        UIView.animate(withDuration: 0.3) {
            self.view.transform = .identity
        }
        isViewRotated = false
    }
    
    func toggleRotation() {
        isViewRotated.toggle()
        
        UIView.animate(withDuration: 0.3) {
            self.view.transform = self.isViewRotated ? CGAffineTransform(rotationAngle: .pi) : .identity
        }
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
        hideQuickPhrasePanel(animated: true)
    }

    @objc private func historyTapped() {
        view.endEditing(true)
        hideQuickPhrasePanel(animated: true)

        let historyVC = HistoryViewController(container: container)
        let navigationController = UINavigationController(rootViewController: historyVC)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    @objc private func newConversationTapped() {
        view.endEditing(true)
        presenter.didRequestNewConversation()
    }

    func toggleQuickPhrasePanel() {
        view.endEditing(true)

        if isQuickPhrasePanelVisible {
            hideQuickPhrasePanel(animated: true)
        } else {
            showQuickPhrasePanel()
        }
    }

    func showQuickPhrasePanel() {
        guard currentConversationMode == .talk else { return }

        isQuickPhrasePanelVisible = true
        quickPhrasePanel.isHidden = false
        quickPhrasePanel.reloadPhrases()
        chatComponentBottomConstraint.constant = -quickPhrasePanelHeight

        UIView.animate(withDuration: 0.22) {
            self.quickPhrasePanel.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    func hideQuickPhrasePanel(animated: Bool) {
        guard isQuickPhrasePanelVisible || !quickPhrasePanel.isHidden else { return }

        isQuickPhrasePanelVisible = false
        chatComponentBottomConstraint.constant = 0

        let changes = {
            self.quickPhrasePanel.alpha = 0
            self.view.layoutIfNeeded()
        }

        let completion: (Bool) -> Void = { _ in
            self.quickPhrasePanel.isHidden = true
        }

        if animated {
            UIView.animate(withDuration: 0.18, animations: changes, completion: completion)
        } else {
            changes()
            completion(true)
        }
    }
}
