import CloudKit
import Foundation

/// Thin wrapper around `CKContainer.accept` for share invitations.
final class CloudKitSharingService {
    let container: CKContainer

    init(containerIdentifier: String = AppConfiguration.cloudKitContainerIdentifier) {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    func accept(metadata: CKShare.Metadata, completion: @escaping (Error?) -> Void) {
        container.accept(metadata) { _, error in
            completion(error)
        }
    }
}
