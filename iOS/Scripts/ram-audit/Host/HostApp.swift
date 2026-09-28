import UIKit

/// App chủ tối giản cho driver RAM: một UITextView + nút "toggle" (ẩn/hiện bàn phím để đo
/// rò rỉ qua nhiều vòng show/hide). UIKit thuần — không SwiftUI để app chủ nhẹ, ổn định.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting s: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = SceneDelegate.self   // iOS 27 bắt buộc scene lifecycle
        return c
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        w.rootViewController = HostVC()
        w.makeKeyAndVisible()
        window = w
    }
}

final class HostVC: UIViewController {
    let field = UITextView()
    let toggle = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        field.font = .systemFont(ofSize: 20)
        field.accessibilityIdentifier = "field"
        field.autocorrectionType = .default
        toggle.setTitle("toggle", for: .normal)
        toggle.accessibilityIdentifier = "toggle"
        toggle.addAction(UIAction { [weak self] _ in
            guard let f = self?.field else { return }
            if f.isFirstResponder { f.resignFirstResponder() } else { f.becomeFirstResponder() }
        }, for: .touchUpInside)
        view.addSubview(field)
        view.addSubview(toggle)
    }

    /// `-autocycle N`: tự ẩn/hiện bàn phím N vòng (1,5 s mỗi pha) KHÔNG qua XCUITest —
    /// XCUITest bật runtime Accessibility, cache AX (_AXObjectCacheHelper) giữ mạnh view của
    /// extension ⇒ đo rò rỉ phải có đường không-AX để so (ram-audit.sh autocycle).
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-autocycle"), i + 1 < args.count, let n = Int(args[i + 1]) else { return }
        field.becomeFirstResponder()
        var left = n * 2
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
            guard let f = self?.field, left > 0 else { t.invalidate(); return }
            left -= 1
            if f.isFirstResponder { f.resignFirstResponder() } else { f.becomeFirstResponder() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let s = view.safeAreaLayoutGuide.layoutFrame
        toggle.frame = CGRect(x: s.maxX - 100, y: s.minY, width: 90, height: 40)
        field.frame = CGRect(x: s.minX + 8, y: s.minY + 44, width: s.width - 16, height: 160)
    }
}
