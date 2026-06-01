//
//  BindrApp.swift
//  Bindr
//
//  Created by Jordan Hardcastle on 05/04/2026.
//

import SwiftUI
import SwiftData
import UserNotifications
import UIKit
import BackgroundTasks

final class BindrPushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Buffer for a notification tap that arrived before any observer was
    /// listening — typically a cold launch where the user tapped the
    /// notification to wake the app and `didReceive` fires before SwiftUI
    /// has built `AppServices` (and therefore before
    /// ``SocialPushService.subscribeToPushEvents`` ran).
    /// `NotificationCenter.default.post` requires a live observer at the
    /// moment of posting, so without this buffer the deep link would be lost
    /// on cold launch. ``SocialPushService`` drains this on init.
    static var pendingTapUserInfo: [AnyHashable: Any]?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: CatalogDailyRefreshTask.identifier,
            using: nil
        ) { task in
            CatalogDailyRefreshTask.handle(task as! BGAppRefreshTask)
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .socialPushDeviceTokenDidUpdate, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Safe to ignore in development/simulators where APNs registration may be unavailable.
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Foreground arrival: just present the banner. We deliberately do NOT
        // post the deep-link notification here — `willPresent` fires the
        // moment a push arrives while the app is in front, which is *before*
        // the user has done anything. Posting it would route them to the
        // related post immediately, yanking them out of whatever they were
        // doing. Only the actual tap (`didReceive` below) should route.
        if #available(iOS 14.0, *) {
            return [.banner, .list, .sound, .badge]
        } else {
            return [.alert, .sound, .badge]
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        // Buffer first, then post. Either:
        //   • An observer is already listening — the post delivers it, the
        //     observer drains the buffer (no-op) on the next init.
        //   • No observer yet (cold launch race) — the post is dropped, but
        //     ``SocialPushService.init`` reads `pendingTapUserInfo` and
        //     enqueues the deep link as soon as it subscribes.
        Self.pendingTapUserInfo = userInfo
        NotificationCenter.default.post(name: .socialPushDeepLinkReceived, object: nil, userInfo: userInfo)
    }
}

@main
struct BindrApp: App {
    @UIApplicationDelegateAdaptor(BindrPushAppDelegate.self) private var pushAppDelegate

    static let cloudKitFallbackDefaultsKey = "cloudKitFallbackActive"
    static let cloudKitLastErrorDefaultsKey = "cloudKitLastError"
    /// True if the SQLite store already existed when the app launched.
    /// False means this is a fresh install (or after deletion) — CloudKit restore is needed.
    static let storeExistedAtLaunch: Bool = FileManager.default.fileExists(atPath: Self.storeURL.path)

    init() {
        Self.configureTabBarAppearance()
        Self.installMainThreadWatchdog()
    }

    /// Logs a stack trace every time the main thread is blocked for >100ms.
    /// Remove before shipping.
    ///
    /// Timestamps are printed as seconds since process start (`systemUptime`) so they can be
    /// correlated against other launch events (e.g. the Liquid Glass enable flip in
    /// `ModelContainerHost`, which also logs its `systemUptime`). The previous version only
    /// logged the *duration* of a block and captured the stack *at unblock* — by which point the
    /// main thread is already idle, so the stack was always the runloop and never the real
    /// culprit. Logging the block's START uptime lets us pinpoint exactly what scheduled work
    /// was running when the freeze began.
    private static func installMainThreadWatchdog() {
        #if DEBUG
        // Capture the main thread's mach port HERE (init runs on the main thread) so the
        // background watchdog can read the main thread's stack while it is blocked.
        mainThreadMachPort = mach_thread_self()
        let q = DispatchQueue(label: "main.watchdog", qos: .userInteractive)
        q.async {
            var lastPing = CFAbsoluteTimeGetCurrent()
            // Capture the main thread's stack DURING a long hang (not at unblock). We only sample
            // once per distinct hang so the log isn't flooded.
            var didSampleCurrentHang = false
            while true {
                let sent = CFAbsoluteTimeGetCurrent()
                DispatchQueue.main.async {
                    let delay = CFAbsoluteTimeGetCurrent() - sent
                    if delay > 0.5 {
                        let now = ProcessInfo.processInfo.systemUptime
                        print(String(format: "[Watchdog] main blocked %.2fs (started at uptime %.2fs, ended %.2fs)",
                                     delay, now - delay, now))
                    }
                    lastPing = CFAbsoluteTimeGetCurrent()
                    didSampleCurrentHang = false
                }
                Thread.sleep(forTimeInterval: 0.1)
                let waited = CFAbsoluteTimeGetCurrent() - lastPing
                if waited > 2.0 {
                    let now = ProcessInfo.processInfo.systemUptime
                    print(String(format: "[Watchdog] main STILL blocked %.1fs (block began ~uptime %.2fs)",
                                 waited, now - waited))
                    // Sample the real main-thread stack the first time we notice this hang.
                    if !didSampleCurrentHang {
                        didSampleCurrentHang = true
                        if let stack = Self.captureMainThreadStack() {
                            print("[Watchdog] MAIN THREAD stack DURING hang:\n\(stack)")
                        }
                    }
                }
            }
        }
        #endif
    }

    #if DEBUG
    /// Mach port of the main thread, captured once at launch (in `installMainThreadWatchdog`,
    /// which runs on the main thread) so the watchdog — running on a background queue — can read
    /// the main thread's backtrace while it is blocked.
    nonisolated(unsafe) private static var mainThreadMachPort: thread_t = 0

    /// Walks the main thread's stack frames and symbolicates them with `dladdr`.
    /// Returns a newline-joined, human-readable backtrace, or nil if it could not be read.
    ///
    /// This briefly suspends the main thread, reads its register state + frame-pointer chain,
    /// then resumes it. It is DEBUG-only diagnostic code and must be removed before shipping.
    private static func captureMainThreadStack() -> String? {
        #if arch(arm64)
        let target = mainThreadMachPort
        guard thread_suspend(target) == KERN_SUCCESS else { return nil }
        defer { thread_resume(target) }

        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)
        let kr = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { ptr in
                thread_get_state(target, thread_state_flavor_t(ARM_THREAD_STATE64), ptr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        // The app target is arm64 (not arm64e), so PC/LR/FP and on-stack return addresses are
        // not pointer-authenticated and can be read directly. Mask off any high tag bits just in
        // case so the addresses are valid user-space VAs for dladdr.
        let vaMask: UInt = 0x0000_007F_FFFF_FFFF
        var pcs: [UInt] = []
        pcs.append(UInt(state.__pc) & vaMask)
        let lr = UInt(state.__lr) & vaMask
        if lr != 0 { pcs.append(lr) }

        // Walk the frame-pointer chain: each frame is [saved FP, saved LR].
        var fp = UInt(state.__fp)
        var depth = 0
        while fp != 0, depth < 40 {
            guard let framePtr = UnsafePointer<UInt>(bitPattern: fp) else { break }
            let nextFP = framePtr.pointee
            let returnAddr = framePtr.advanced(by: 1).pointee & vaMask
            if returnAddr != 0 { pcs.append(returnAddr) }
            if nextFP <= fp { break } // stacks grow downward; FP must increase walking up
            fp = nextFP
            depth += 1
        }

        let lines: [String] = pcs.enumerated().map { idx, addr in
            var info = Dl_info()
            if dladdr(UnsafeRawPointer(bitPattern: addr), &info) != 0, let sname = info.dli_sname {
                let symbol = String(cString: sname)
                let image = info.dli_fname.map { (String(cString: $0) as NSString).lastPathComponent } ?? "?"
                return String(format: "%2d  %@  %@", idx, image, Self.demangle(symbol))
            }
            return String(format: "%2d  0x%016lx", idx, addr)
        }
        return lines.joined(separator: "\n")
        #else
        return nil
        #endif
    }

    /// Demangles a Swift symbol name via `swift_demangle` (resolved at runtime). Falls back to the
    /// raw symbol for C/Objective-C names that don't need demangling.
    private static func demangle(_ mangled: String) -> String {
        typealias DemangleFn = @convention(c) (
            _ name: UnsafePointer<CChar>?, _ nameLength: Int,
            _ out: UnsafeMutablePointer<CChar>?, _ outLength: UnsafeMutablePointer<Int>?,
            _ flags: UInt32
        ) -> UnsafeMutablePointer<CChar>?
        guard mangled.hasPrefix("$s") || mangled.hasPrefix("_$s"),
              let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_demangle") else {
            return mangled
        }
        let fn = unsafeBitCast(sym, to: DemangleFn.self)
        return mangled.withCString { cstr -> String in
            guard let out = fn(cstr, strlen(cstr), nil, nil, 0) else { return mangled }
            defer { free(out) }
            return String(cString: out)
        }
    }
    #endif

    /// CloudKit-backed store. SwiftData merges CloudKit records on @MainActor; the
    /// CloudKitIdleMonitor keeps the launch overlay visible until those merges complete,
    /// so the freeze is hidden behind the overlay rather than felt on the dashboard.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            WishlistItem.self,
            TradeListItem.self,
            CollectionItem.self,
            LedgerLine.self,
            CostLot.self,
            SaleAllocation.self,
            Binder.self,
            BinderSlot.self,
            Deck.self,
            DeckCard.self,
            CollectionValueSnapshot.self,
            CollectionWeeklyAverage.self,
            CollectionMonthlyAverage.self,
            CardFolder.self,
            CardFolderItem.self,
        ])

        do {
            let container = try makePersistentContainer(schema: schema, cloudKitDatabase: .automatic)
            UserDefaults.standard.set(false, forKey: cloudKitFallbackDefaultsKey)
            UserDefaults.standard.removeObject(forKey: cloudKitLastErrorDefaultsKey)
            return container
        } catch {
            logModelContainerIssue(stage: "initial CloudKit load", error: error)
            destroyPersistentStoreFiles()
            do {
                let container = try makePersistentContainer(schema: schema, cloudKitDatabase: .automatic)
                UserDefaults.standard.set(false, forKey: cloudKitFallbackDefaultsKey)
                UserDefaults.standard.removeObject(forKey: cloudKitLastErrorDefaultsKey)
                return container
            } catch {
                logModelContainerIssue(stage: "CloudKit reload after store reset", error: error)
                do {
                    let container = try makePersistentContainer(schema: schema, cloudKitDatabase: .none)
                    UserDefaults.standard.set(true, forKey: cloudKitFallbackDefaultsKey)
                    return container
                } catch {
                    fatalError("Could not create fallback SwiftData store: \(error)")
                }
            }
        }
    }

    private static func makePersistentContainer(
        schema: Schema,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: cloudKitDatabase
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static var storeURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let directoryURL = baseURL.appendingPathComponent("Bindr", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("Bindr.store")
    }

    private static func destroyPersistentStoreFiles() {
        let fileManager = FileManager.default
        let urls = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal"),
        ]

        for url in urls where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func logModelContainerIssue(stage: String, error: Error) {
        let nsError = error as NSError
        let iCloudToken = FileManager.default.ubiquityIdentityToken
        let diagnostic = [
            "stage=\(stage)",
            "iCloudAccount=\(iCloudToken != nil ? "signed-in" : "not-signed-in")",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)",
            nsError.userInfo.isEmpty ? nil : "userInfo=\(nsError.userInfo)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        UserDefaults.standard.set(diagnostic, forKey: cloudKitLastErrorDefaultsKey)

        print("[PokeTrack] SwiftData model container failure during \(stage)")
        print("[PokeTrack] iCloud account present: \(iCloudToken != nil)")
        print("[PokeTrack] domain=\(nsError.domain) code=\(nsError.code)")
        print("[PokeTrack] description=\(nsError.localizedDescription)")
        if !nsError.userInfo.isEmpty {
            print("[PokeTrack] userInfo=\(nsError.userInfo)")
        }
    }

    /// Match tab bar glass density to multi-select pill buttons.
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor.black.withAlphaComponent(0.30)
            } else {
                return UIColor.black.withAlphaComponent(0.12)
            }
        }
        appearance.shadowColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.18)
                : UIColor.black.withAlphaComponent(0.10)
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ModelContainerHost()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                CatalogDailyRefreshTask.schedule()
            }
        }
    }

    private struct ModelContainerHost: View {
        @State private var modelContainer: ModelContainer?

        var body: some View {
            Group {
                if let modelContainer {
                    RootView()
                        .modelContainer(modelContainer)
                } else {
                    LaunchWordmarkView(elapsedLabel: "")
                        .task {
                            // Build the ModelContainer off the main thread so opening the
                            // CloudKit-backed SQLite store doesn't freeze the launch animation.
                            let container = await Task.detached(priority: .userInitiated) {
                                BindrApp.makeModelContainer()
                            }.value
                            modelContainer = container
                        }
                }
            }
            .task {
                // iOS 26's Glass.regular.glassEffect() is expensive to initialise: rendering
                // 5 concurrent glass layers for the first time blocks the main thread for 8–9s.
                // Delay enabling glass until well after the launch layout storm has settled.
                try? await Task.sleep(for: .seconds(10))
                print(String(format: "[Glass] enabling Liquid Glass at uptime %.2fs",
                             ProcessInfo.processInfo.systemUptime))
                GlassReadySignal.shared.isReady = true
                print(String(format: "[Glass] isReady flipped (returned to scheduler) at uptime %.2fs",
                             ProcessInfo.processInfo.systemUptime))
            }
        }
    }
}
