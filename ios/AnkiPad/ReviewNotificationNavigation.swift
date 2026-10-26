import SwiftUI
import UIKit
import UserNotifications

@MainActor final class ReviewNotificationRoute: ObservableObject {
    static let shared = ReviewNotificationRoute()
    @Published private(set) var profileID: String?
    func receive(_ id: String) { profileID = id }
    func take() -> String? {
        let id = profileID
        profileID = nil
        return id
    }
}

@MainActor final class ReviewNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let id = response.notification.request.content.userInfo["profileID"] as? String,
              response.notification.request.identifier.hasPrefix("ankipad.review." + id + ".") else { return }
        await ReviewNotificationRoute.shared.receive(id)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard notification.request.identifier.hasPrefix("ankipad.review.") else { return [] }
        return [.banner, .list, .sound]
    }
}
