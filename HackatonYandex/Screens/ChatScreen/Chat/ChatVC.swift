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
    private let container: AppContainer
    
    private let topChatComponent = TopChatComponent()
    private let containerView = UIView()
    let segmentControlComponent = SegmentControlComponent()
    let chatComponent = ChatComponent()
    lazy var presenter = ConversationPresenter(
        view: self,
        microphonePermissionService: container.microphonePermissionService,
        audioRecordingService: container.audioRecordingService,
        speechRecognitionService: container.speechRecognitionService
    )
    
    var typingHint: StartTypingHint?
    var microphoneHint: MicrophoneOnHint?
    
    private var currentChildVC: UIViewController?
    lazy var talkVC = TalkViewController()
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
        setupContainerView()
        
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
    }
}
