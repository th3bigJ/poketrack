import Foundation

/// Runs catalog/pricing network work with a bounded number of in-flight tasks.
/// Matches `AppURLSession.catalog` connection pool so work queues efficiently.
enum CatalogParallelDownloadPool {
    static var maxConcurrent: Int { AppURLSession.catalogParallelDownloads }

    static func map<Element, Result: Sendable>(
        _ elements: [Element],
        body: @escaping @Sendable (Element) async throws -> Result
    ) async rethrows -> [Result] {
        guard !elements.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: Result.self) { group in
            var iterator = elements.makeIterator()
            for _ in 0..<min(maxConcurrent, elements.count) {
                if let element = iterator.next() {
                    group.addTask { try await body(element) }
                }
            }
            var results: [Result] = []
            while let result = try await group.next() {
                results.append(result)
                if let element = iterator.next() {
                    group.addTask { try await body(element) }
                }
            }
            return results
        }
    }
}
