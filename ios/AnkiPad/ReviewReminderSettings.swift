import SwiftUI
import UserNotifications

@MainActor enum ReviewReminderStore {
    private static var saving = false
    private static var generations: [String: UUID] = [:]
    private static func key(_ profileID: String) -> String { "reviewReminder." + profileID }
    private static func prefix(_ profileID: String) -> String {
        var value = "ankipad.review." + profileID + "."
        #if DEBUG
        if let namespace = UITestIsolation.namespace() { value += "uitest." + namespace + "." }
        #endif
        return value
    }
    #if DEBUG
    // Read the OS schedule, not reconstructed settings. No mutation/injection.
    static func testSchedule(profileID: String) async throws -> String {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let records: [[String: Any]] = requests.filter { $0.identifier.hasPrefix(prefix(profileID)) }.map { request in
            let trigger = request.trigger as? UNCalendarNotificationTrigger
            return ["id": request.identifier, "profileID": request.content.userInfo["profileID"] as? String ?? "",
                    "weekday": trigger?.dateComponents.weekday ?? -1, "hour": trigger?.dateComponents.hour ?? -1,
                    "minute": trigger?.dateComponents.minute ?? -1, "year": trigger?.dateComponents.year ?? -1, "month": trigger?.dateComponents.month ?? -1, "day": trigger?.dateComponents.day ?? -1, "repeats": trigger?.repeats ?? false,
                    "sound": request.content.sound != nil]
        }
        let config = try load(profileID: profileID)
        let data = try JSONSerialization.data(withJSONObject: ["pending": records, "savedIDs": config.requestIDs], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
    #endif
    static func load(profileID: String) throws -> ReviewReminderConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key(profileID)) else { return ReviewReminderConfiguration() }
        let config = try JSONDecoder().decode(ReviewReminderConfiguration.self, from: data)
        try config.validate()
        return config
    }
    static func save(_ desired: ReviewReminderConfiguration, profile: StudyProfile, engine: Engine? = nil, requestPermission: Bool = true) async throws {
        try desired.validate()
        guard !saving else { throw EngineError(message: "ほかの通知設定を保存中です。少し待ってから、もう一度保存してください。") }
        saving = true
        let generation = UUID()
        generations[profile.id] = generation
        defer { saving = false }
        let old = try load(profileID: profile.id)
        let center = UNUserNotificationCenter.current()
        var next = desired
        next.requestIDs = []
        if desired.enabled {
            let granted: Bool
            if requestPermission { granted = try await center.requestAuthorization(options: [.alert, .sound]) }
            else {
                let status = await center.notificationSettings().authorizationStatus
                granted = status == .authorized || status == .provisional || status == .ephemeral
            }
            guard granted else { throw EngineError(message: "通知が許可されていません。iPadの設定からAnkiPadの通知を許可してください。") }
            var conditionalDates: [Date] = []
            if desired.conditional {
                guard let engine else { throw EngineError(message: "通知条件を確認するコレクションがありません。") }
                conditionalDates = try await engine.reminderForecast(desired, now: Date()).filter { $0.matches(desired) }.map(\.date)
            }
            try Task.checkCancellation()
            guard generations[profile.id] == generation else { throw CancellationError() }
            let pending = await center.pendingNotificationRequests()
            try ReviewReminderRequestBudget.validateStaging(pendingCount: Set(pending.map(\.identifier)).count, additions: desired.conditional ? conditionalDates.count : desired.weekdays.count)
            let batch = UUID().uuidString
            do {
                let dates: [DateComponents] = desired.conditional
                    ? conditionalDates.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
                    : desired.weekdays.sorted().map { DateComponents(hour: desired.hour, minute: desired.minute, weekday: $0) }
                for (index, components) in dates.enumerated() {
                    try Task.checkCancellation()
                    let identifier = prefix(profile.id) + batch + "." + String(index)
                    let content = UNMutableNotificationContent()
                    content.title = "学習の時間です"
                    content.body = profile.name + "のカードを復習しましょう。"
                    if desired.sound { content.sound = .default }
                    content.userInfo = ["profileID": profile.id]
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: !desired.conditional)
                    try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                    next.requestIDs.append(identifier)
                }
            } catch {
                center.removePendingNotificationRequests(withIdentifiers: next.requestIDs)
                throw error
            }
        }
        do {
            try Task.checkCancellation()
            guard generations[profile.id] == generation else { throw CancellationError() }
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
        generations[profileID] = UUID()
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
    let engine: Engine
    let decks: [Deck]
    @Environment(\.dismiss) private var dismiss
    @State private var config = ReviewReminderConfiguration()
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var permission = ""
    #if DEBUG
    @State private var nativeSchedule = ""
    #endif
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
                Toggle("通知音", isOn: $config.sound).accessibilityIdentifier("reminder-sound")
            }
            Section("通知する曜日") {
                ForEach(1...7, id: \.self) { day in
                    Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: {
                        config.weekdays.contains(day)
                    }, set: { enabled in
                        config.weekdays.removeAll { $0 == day }
                        if enabled { config.weekdays.append(day) }
                    })).accessibilityIdentifier("reminder-weekday-\(day)")
                }
            }
            Section("通知の条件") {
                Stepper("必要なカード: \(config.minimumDue)枚以上（0で制限なし）", value: $config.minimumDue, in: 0...100000)
                    .accessibilityIdentifier("reminder-minimum-due")
                Picker("対象デッキ", selection: Binding(get: { config.deckID ?? "" }, set: { config.deckID = $0.isEmpty ? nil : $0 })) {
                    Text("すべてのデッキ").tag("")
                    ForEach(decks) { Text($0.name).tag($0.id) }
                    if let id = config.deckID, !decks.contains(where: { $0.id == id }) { Text("削除されたデッキ").tag(id) }
                }.accessibilityIdentifier("reminder-deck")
                Toggle("その日にまだ学習していない場合だけ", isOn: $config.onlyIfNoReviews).accessibilityIdentifier("reminder-no-reviews")
            }
            Section {
                Text(config.conditional ? "今後14日分の予測で予約し、アプリの起動・学習・同期後に更新します。アプリを開かない間の変更は、通知時に再判定できません。" : "指定した曜日と時刻に通知します。復習枚数や、その日に学習したかどうかにかかわらず通知します。")
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--uitest-reminders"), !nativeSchedule.isEmpty {
                    Text("予約状態").accessibilityIdentifier("reminder-native-schedule").accessibilityValue(nativeSchedule)
                }
                #endif
                if !permission.isEmpty { Text(permission).foregroundStyle(.secondary) }
                if busy { ProgressView() }
                Button("リマインダーを保存") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await ReviewReminderStore.save(config, profile: profile, engine: engine); dismiss() }
                        catch {
                            #if DEBUG
                            if ProcessInfo.processInfo.arguments.contains("--uitest-reminders") {
                                nativeSchedule = (try? await ReviewReminderStore.testSchedule(profileID: profile.id)) ?? ""
                            }
                            #endif
                            self.error = error.localizedDescription
                        }
                    }
                }.accessibilityIdentifier("reminder-save")
            }
        }
        .accessibilityIdentifier("reminder-form")
        .disabled(!loaded || busy)
        .studyThemeSurface().navigationTitle("学習リマインダー")
        .task {
            loaded = false
            #if DEBUG
            nativeSchedule = ""
            #endif
            do { config = try ReviewReminderStore.load(profileID: profile.id); loaded = true }
            catch { self.error = error.localizedDescription }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitest-reminders") {
                do { nativeSchedule = try await ReviewReminderStore.testSchedule(profileID: profile.id) }
                catch { self.error = error.localizedDescription }
            }
            #endif
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .denied { permission = "通知はiPadの設定で無効になっています。" }
        }
        .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("閉じる", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}
