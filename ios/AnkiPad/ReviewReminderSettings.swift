import SwiftUI
import UserNotifications

@MainActor enum ReviewReminderStore {
    private static func key(_ profileID: String) -> String { "reviewReminder." + profileID }
    private static func prefix(_ profileID: String) -> String { "ankipad.review." + profileID + "." }
    static func load(profileID: String) throws -> ReviewReminderConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key(profileID)) else { return ReviewReminderConfiguration() }
        let config = try JSONDecoder().decode(ReviewReminderConfiguration.self, from: data)
        try config.validate()
        return config
    }
    static func save(_ desired: ReviewReminderConfiguration, profile: StudyProfile) async throws {
        try desired.validate()
        let old = try load(profileID: profile.id)
        let center = UNUserNotificationCenter.current()
        var next = desired
        next.requestIDs = []
        if desired.enabled {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { throw EngineError(message: "通知が許可されていません。iPadの設定からAnkiPadの通知を許可してください。") }
            let batch = UUID().uuidString
            do {
                for weekday in desired.weekdays.sorted() {
                    let identifier = prefix(profile.id) + batch + "." + String(weekday)
                    let content = UNMutableNotificationContent()
                    content.title = "学習の時間です"
                    content.body = profile.name + "のカードを復習しましょう。"
                    if desired.sound { content.sound = .default }
                    content.userInfo = ["profileID": profile.id]
                    let components = DateComponents(hour: desired.hour, minute: desired.minute, weekday: weekday)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                    next.requestIDs.append(identifier)
                }
            } catch {
                center.removePendingNotificationRequests(withIdentifiers: next.requestIDs)
                throw error
            }
        }
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(next), forKey: key(profile.id))
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: next.requestIDs)
            throw error
        }
        let previous = old.requestIDs.filter { $0.hasPrefix(prefix(profile.id)) }
        center.removePendingNotificationRequests(withIdentifiers: previous)
        center.removeDeliveredNotifications(withIdentifiers: previous)
    }
    static func delete(profileID: String) {
        if let config = try? load(profileID: profileID) {
            let ids = config.requestIDs.filter { $0.hasPrefix(prefix(profileID)) }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
        UserDefaults.standard.removeObject(forKey: key(profileID))
    }
}

struct ReviewReminderSettingsView: View {
    let profile: StudyProfile
    @Environment(\.dismiss) private var dismiss
    @State private var config = ReviewReminderConfiguration()
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var permission = ""
    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: config.hour, minute: config.minute)) ?? Date()
        }, set: {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
            config.hour = parts.hour ?? 19
            config.minute = parts.minute ?? 0
        })
    }
    var body: some View {
        Form {
            Section(profile.name) {
                Toggle("学習リマインダー", isOn: $config.enabled).accessibilityIdentifier("reminder-enabled")
                DatePicker("通知時刻", selection: time, displayedComponents: .hourAndMinute)
                Toggle("通知音", isOn: $config.sound)
            }
            Section("通知する曜日") {
                ForEach(1...7, id: \.self) { day in
                    Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: {
                        config.weekdays.contains(day)
                    }, set: { enabled in
                        config.weekdays.removeAll { $0 == day }
                        if enabled { config.weekdays.append(day) }
                    }))
                }
            }
            Section {
                Text("指定した曜日と時刻に通知します。復習枚数や、その日に学習したかどうかにかかわらず通知します。")
                if !permission.isEmpty { Text(permission).foregroundStyle(.secondary) }
                if busy { ProgressView() }
                Button("リマインダーを保存") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await ReviewReminderStore.save(config, profile: profile); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.accessibilityIdentifier("reminder-save")
            }
        }
        .disabled(!loaded || busy)
        .navigationTitle("学習リマインダー")
        .task {
            do { config = try ReviewReminderStore.load(profileID: profile.id); loaded = true }
            catch { self.error = error.localizedDescription }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .denied { permission = "通知はiPadの設定で無効になっています。" }
        }
        .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("閉じる", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}
