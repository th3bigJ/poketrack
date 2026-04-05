import CloudKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let service = CloudKitSharingService(containerIdentifier: cloudKitShareMetadata.containerIdentifier)
        service.accept(metadata: cloudKitShareMetadata) { error in
            if let error {
                NSLog("CloudKit share accept failed: \(error.localizedDescription)")
            }
        }
    }
}
