//
//  SPPrivacyPolicyViewController.swift
//  ConsentViewController-tvOS
//
//  Created by Vilas on 03/05/21.
//

import UIKit

class SPPrivacyPolicyViewController: UIViewController {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionTextView: UITextView!
    @IBOutlet weak var logoImageView: UIImageView!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var backButton: UIButton!

    var privacyPolicyView: SPPrivacyManager

    public init(privacyPolicyContent: SPPrivacyManager) {
        privacyPolicyView = privacyPolicyContent
        super.init(nibName: "SPPrivacyPolicyViewController", bundle: Bundle.framework)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func loadLabelText(forComponentId id: String, label: UILabel) {
        if let textDetails = privacyPolicyView.components.first(where: {component in component.id == id }) {
            label.text = textDetails.text
            label.textColor = SDKUtils.hexStringToUIColor(hex: textDetails.style?.font?.color ?? "")
            if let fontFamily = textDetails.style?.font?.fontFamily, let fontsize = textDetails.style?.font?.fontSize {
                label.font = UIFont(name: fontFamily, size: fontsize)
            }
        }
    }

    func loadBody(forComponentId id: String, textView: UITextView) {
        if let categoriesDescription = privacyPolicyView.components.first(where: {component in component.id == id }) {
            textView.text = categoriesDescription.text
            textView.textColor = SDKUtils.hexStringToUIColor(hex: categoriesDescription.style?.font?.color ?? "")
            if let fontFamily = categoriesDescription.style?.font?.fontFamily, let fontsize = categoriesDescription.style?.font?.fontSize {
                textView.font = UIFont(name: fontFamily, size: fontsize)
            }
        }
    }

    func loadActionButton(forComponentId id: String, button: UIButton) {
        if let action =  privacyPolicyView.components.first(where: { component in component.id == id }) {
            button.titleLabel?.text = action.text
            button.setTitleColor(SDKUtils.hexStringToUIColor(hex: action.style?.onUnfocusTextColor ?? ""), for: .normal)
            button.setTitleColor(SDKUtils.hexStringToUIColor(hex: action.style?.onFocusTextColor ?? ""), for: .focused)
            button.backgroundColor = SDKUtils.hexStringToUIColor(hex: action.style?.onUnfocusBackgroundColor ?? "")
            if let fontFamily = action.style?.font?.fontFamily, let fontsize = action.style?.font?.fontSize {
                button.titleLabel?.font = UIFont(name: fontFamily, size: fontsize)
            }
        }
    }

    func loadBackButton(forComponentId id: String, button: UIButton) {
        if let action =  privacyPolicyView.components.first(where: { component in component.id == id }) {
            button.titleLabel?.text = action.text
            button.setTitleColor(SDKUtils.hexStringToUIColor(hex: action.style?.font?.color ?? ""), for: .normal)
            button.backgroundColor = SDKUtils.hexStringToUIColor(hex: action.style?.backgroundColor ?? "")
            if let fontFamily = action.style?.font?.fontFamily, let fontsize = action.style?.font?.fontSize {
                button.titleLabel?.font = UIFont(name: fontFamily, size: fontsize)
            }
        }
    }

    func addBackgroundColor() -> UIColor? {
        return SDKUtils.hexStringToUIColor(hex: privacyPolicyView.style.backgroundColor ?? "")
    }

    func setupHomeView() {
        self.view.backgroundColor = addBackgroundColor()
        self.view.tintColor = addBackgroundColor()
        loadLabelText(forComponentId: "HeaderText", label: titleLabel)
        loadBody(forComponentId: "Body", textView: descriptionTextView)
        loadActionButton(forComponentId: "CloseButton", button: closeButton)
        loadBackButton(forComponentId: "BackButton", button: backButton)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHomeView()
    }

    @IBAction func onBackTap(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }

    @IBAction func onCloseTap(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
}
