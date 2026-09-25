import SwiftUI

/// A scene-level window covers presented sheets as well as the root during app-switcher snapshots.
struct PrivacyShield: UIViewRepresentable {
    var active: Bool
    func makeUIView(context: Context) -> ShieldHost { ShieldHost() }
    func updateUIView(_ view: ShieldHost, context: Context) { view.shielded = active }
    static func dismantleUIView(_ view: ShieldHost, coordinator: ()) { view.shielded = false }

    final class ShieldHost: UIView {
        var shielded = false { didSet { updateShield() } }
        private var shieldWindow: UIWindow?
        override func didMoveToWindow() { super.didMoveToWindow(); updateShield() }
        private func updateShield() {
            guard shielded, let scene = window?.windowScene else {
                shieldWindow?.isHidden = true; shieldWindow = nil; return
            }
            guard shieldWindow == nil else { return }
            let cover = UIWindow(windowScene: scene)
            cover.windowLevel = .alert + 1
            let controller = UIViewController()
            controller.view.backgroundColor = .systemGroupedBackground
            let label = UILabel(); label.text = "Local Ledger · Private"; label.font = .preferredFont(forTextStyle: .title2)
            label.textColor = .secondaryLabel; label.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor), label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor)])
            cover.rootViewController = controller; cover.isHidden = false; shieldWindow = cover
        }
    }
}
