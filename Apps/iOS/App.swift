import SwiftUI
import ThisJellyFixFeature
import ThisJellyFixCast

@main
struct ThisFrameIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup { ThisFrameRootView() }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        application.tjf_orientationLock
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Cast: inicialización única y temprana (debe ser ANTES de cualquier
        // uso de GCKDiscoveryManager/GCKSessionManager). Idempotente por
        // diseño — una segunda llamada sería no-op, imposible duplicarla.
        // El descubrimiento NO arranca aquí: solo cuando el usuario abre el
        // selector (ahorro de red y de permisos).
        CastSDK.initialize()
        return true
    }
}
