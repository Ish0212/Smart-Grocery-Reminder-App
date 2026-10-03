import Foundation
import FirebaseCore

/// The privacy policy and support pages, which Firebase Hosting serves from `site/` (see
/// docs/app-store/release.md). App Review requires the privacy policy to be reachable in the app.
enum AppLinks {
    /// nil in the demo build, which has no Firebase project.
    static var privacyPolicy: URL? { website(projectID: projectID)?.appendingPathComponent("privacy") }
    static var support: URL? { website(projectID: projectID)?.appendingPathComponent("support") }

    /// The project's default Hosting site. With a custom domain, return that instead.
    static func website(projectID: String?) -> URL? {
        guard let projectID, !projectID.isEmpty else { return nil }
        return URL(string: "https://\(projectID).web.app")
    }

    private static var projectID: String? {
        FirebaseApp.app()?.options.projectID
    }
}
