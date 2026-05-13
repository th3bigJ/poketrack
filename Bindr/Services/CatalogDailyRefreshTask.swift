import BackgroundTasks
import Foundation

/// BGAppRefreshTask that runs `syncAllIfNeeded` after 03:15 local time so the
/// next foreground launch finds pricing already up to date.
enum CatalogDailyRefreshTask {
    static let identifier = "com.bindr.catalog.dailyrefresh"

    /// Schedule the next refresh for 03:15 local time (12 min after the daily
    /// market data boundary at 03:00). iOS may fire later depending on usage
    /// patterns and power; the task itself re-checks freshness before fetching.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 3
        components.minute = 15
        components.second = 0
        if let today315 = Calendar.current.date(from: components) {
            request.earliestBeginDate = today315 > Date() ? today315 : Calendar.current.date(byAdding: .day, value: 1, to: today315)
        }
        try? BGTaskScheduler.shared.submit(request)
    }

    static func handle(_ task: BGAppRefreshTask) {
        schedule()

        let rawBrands = UserDefaults.standard.array(forKey: "tcg_brand_enabled_raw_values") as? [String] ?? []
        var enabledBrands = Set(rawBrands.compactMap(TCGBrand.init(rawValue:)))
        if enabledBrands.isEmpty { enabledBrands = [.pokemon] }
        let syncTask = Task(priority: .utility) {
            await CatalogSyncCoordinator.shared.syncAllIfNeeded(enabledBrands: enabledBrands)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
