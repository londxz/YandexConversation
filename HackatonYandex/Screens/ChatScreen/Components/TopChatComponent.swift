//
//  TopChatComponent.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

class TopChatComponent: UIView {
    lazy var microNavButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isUserInteractionEnabled = false
        btn.isAccessibilityElement = true
        btn.layer.cornerRadius = 24
        btn.imageView?.contentMode = .center

        return btn
    }()
    
    lazy var leftNavButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: "leftNavBarIcon")?.withRenderingMode(.alwaysOriginal), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false

        return btn
    }()
    
    lazy var rightNavButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: "rightNavBarIcon")?.withRenderingMode(.alwaysOriginal), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false

        return btn
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .clear
        
        addSubview(microNavButton)
        addSubview(leftNavButton)
        addSubview(rightNavButton)
        
        NSLayoutConstraint.activate([
            microNavButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            microNavButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            microNavButton.widthAnchor.constraint(equalToConstant: 48),
            microNavButton.heightAnchor.constraint(equalTo: microNavButton.widthAnchor),
            
            leftNavButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftNavButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            leftNavButton.widthAnchor.constraint(equalToConstant: 24),
            leftNavButton.heightAnchor.constraint(equalTo: leftNavButton.widthAnchor),
            
            rightNavButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightNavButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            rightNavButton.widthAnchor.constraint(equalToConstant: 24),
            rightNavButton.heightAnchor.constraint(equalTo: leftNavButton.widthAnchor)
        ])

        applyMicrophoneActivity(isActive: false)
    }

    func applyMicrophoneActivity(isActive: Bool) {
        if isActive {
            microNavButton.backgroundColor = .clear
            microNavButton.setImage(Self.microphoneImage, for: .normal)
            microNavButton.tintColor = nil
            microNavButton.accessibilityLabel = "Микрофон включён"
        } else {
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            microNavButton.backgroundColor = UIColor(red: 1, green: 0.88, blue: 0.88, alpha: 1)
            microNavButton.setImage(
                UIImage(systemName: "mic.slash.fill", withConfiguration: symbolConfiguration),
                for: .normal
            )
            microNavButton.tintColor = UIColor(red: 0.80, green: 0.12, blue: 0.12, alpha: 1)
            microNavButton.accessibilityLabel = "Микрофон выключен"
        }
        microNavButton.accessibilityTraits = [.image, .updatesFrequently]
    }

    private static var microphoneImage: UIImage? {
        UIImage(named: "microNavBarIcon")?.withRenderingMode(.alwaysOriginal)
    }
}
