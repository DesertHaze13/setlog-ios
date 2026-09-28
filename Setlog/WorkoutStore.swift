import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

@MainActor
final class WorkoutStore: ObservableObject {
    #if os(macOS)
    private let deviceName = "Mac"
    #elseif os(iOS)
    private var deviceName: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
    #else
    private let deviceName = "device"
    #endif
    @Published private(set) var state: WorkoutState
    @Published private(set) var syncLabel = "Saved locally"
    @Published private(set) var accountEmail: String?
    @Published private(set) var cloudConflict = false
    @Published private(set) var accountBusy = false
    @Published var message: String?
    @Published private(set) var selectedWeekStart: String?

    private let localURL: URL
    private var cloudTask: Task<Void, Never>?
    private var cloudRecord: CloudRecord?
    private var pendingCloudSave = false
    private var recordDate = Date()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        localURL = directory.appendingPathComponent("setlog-state.json")
        let isFirstLaunch: Bool
        if let saved = try? Self.readState(at: localURL), saved.isValid {
            state = saved
            isFirstLaunch = false
        } else if let seedURL = Bundle.main.url(forResource: "workout-seed", withExtension: "json"),
                  let seed = try? Self.readState(at: seedURL) {
            state = seed
            isFirstLaunch = true
        } else {
            fatalError("The workout schedule is missing from the app bundle.")
        }
        state.activeDay = min(max(state.activeDay, 0), 6)
        if !isFirstLaunch && state.weekStart != Self.currentWeekKey() {
            backupLocal(named: "setlog-before-week-rollover")
        }
        Self.rollOver(&state)
        selectedWeekStart = state.weekStart
        recordDate = Self.dateForWeekday(state.activeDay)
        if isFirstLaunch { normalizeUnrecordedSets() }
        accountEmail = SharedCloud.storedSession()?.email
        persistLocal()
        Task { await refreshFromCloud() }
    }

    var visibleDays: [WorkoutDay] {
        guard let selectedWeekStart, selectedWeekStart != state.weekStart else { return state.days }
        return state.weekRecords[selectedWeekStart] ?? state.days.map(Self.freshDay)
    }

    var isViewingPastWeek: Bool { selectedWeekStart != nil && selectedWeekStart != state.weekStart }
    var currentDay: WorkoutDay { visibleDays[state.activeDay] }
    var selectedWeekDate: Date { Self.date(from: selectedWeekStart ?? state.weekStart ?? Self.currentWeekKey()) ?? Date() }

    func selectWeek(containing date: Date) {
        selectedWeekStart = Self.weekKey(for: date)
        recordDate = Self.dateForWeekday(state.activeDay, in: selectedWeekDate)
    }

    func selectCurrentWeek() { selectWeek(containing: Date()) }

    func selectDay(_ index: Int) {
        guard state.days.indices.contains(index) else { return }
        state.activeDay = index
        recordDate = Self.dateForWeekday(index, in: selectedWeekDate)
        persistLocal()
    }

    func selectRecordDate(_ date: Date) { recordDate = date }

    func setPlan(_ plan: String) {
        guard !isViewingPastWeek else { return }
        state.days[state.activeDay].selectedPlan = plan
        changed(recordProgress: true)
    }

    func setFinished(_ finished: Bool) {
        guard !isViewingPastWeek else { return }
        state.days[state.activeDay].finished = finished
        changed(recordProgress: true)
    }

    func setNotes(_ notes: String) {
        guard !isViewingPastWeek else { return }
        state.days[state.activeDay].notes = notes
        changed()
    }

    func setLast(_ value: String, exercise index: Int) {
        guard !isViewingPastWeek else { return }
        guard validExercise(index) else { return }
        state.days[state.activeDay].exercises[index].last = value
        changed()
    }

    func setWeight(_ value: String, exercise index: Int, set setIndex: Int) {
        guard !isViewingPastWeek else { return }
        guard validSet(index, setIndex) else { return }
        state.days[state.activeDay].exercises[index].sets[setIndex].weight = value
        changed()
    }

    func setReps(_ value: String, exercise index: Int, set setIndex: Int) {
        guard !isViewingPastWeek else { return }
        guard validSet(index, setIndex) else { return }
        state.days[state.activeDay].exercises[index].sets[setIndex].reps = value
        changed()
    }

    func toggleSet(exercise index: Int, set setIndex: Int) {
        guard !isViewingPastWeek else { return }
        guard validSet(index, setIndex) else { return }
        state.days[state.activeDay].exercises[index].sets[setIndex].done.toggle()
        changed(recordProgress: true)
    }

    func addSet(exercise index: Int) {
        guard !isViewingPastWeek else { return }
        guard validExercise(index) else { return }
        let item = state.days[state.activeDay].exercises[index]
        state.days[state.activeDay].exercises[index].sets.append(
            SetEntry(weight: item.last == "—" ? "" : item.last, reps: item.targetReps, done: false)
        )
        changed(recordProgress: true)
    }

    func removeSet(exercise index: Int, set setIndex: Int) {
        guard !isViewingPastWeek else { return }
        guard validSet(index, setIndex) else { return }
        state.days[state.activeDay].exercises[index].sets.remove(at: setIndex)
        changed(recordProgress: true)
    }

    func addExercise(name: String, targetSets: Int, targetReps: String, last: String, note: String) {
        guard !isViewingPastWeek else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let count = min(max(targetSets, 1), 30)
        let chosenPlan = state.days[state.activeDay].day == "Friday"
            ? (state.days[state.activeDay].selectedPlan ?? "Glutes & Isolation") : nil
        let exercise = Exercise(id: UUID().uuidString, name: trimmed, targetSets: String(count),
                                targetReps: targetReps.isEmpty ? "10" : targetReps,
                                last: last, note: note.isEmpty ? nil : note, group: chosenPlan,
                                sets: (0..<count).map { _ in SetEntry(weight: last, reps: targetReps.isEmpty ? "10" : targetReps, done: false) })
        state.days[state.activeDay].exercises.append(exercise)
        changed(recordProgress: true)
    }

    func removeExercise(_ index: Int) {
        guard !isViewingPastWeek else { return }
        guard validExercise(index) else { return }
        state.days[state.activeDay].exercises.remove(at: index)
        changed(recordProgress: true)
    }

    func importWorkout(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let imported: WorkoutState
            if let direct = try? decoder.decode(WorkoutState.self, from: data) {
                imported = direct
            } else {
                imported = try decoder.decode(ExportEnvelope.self, from: data).state
            }
            guard imported.isValid else { throw ImportError.invalidSchedule }
            let backup = localURL.deletingLastPathComponent().appendingPathComponent("setlog-before-import-\(Int(Date().timeIntervalSince1970)).json")
            if FileManager.default.fileExists(atPath: localURL.path) { try FileManager.default.copyItem(at: localURL, to: backup) }
            state = imported
            state.activeDay = min(max(state.activeDay, 0), 6)
            Self.rollOver(&state)
            selectedWeekStart = state.weekStart
            changed()
            message = "Imported all seven days, recorded sets, and notes. A backup of your previous local data was kept."
        } catch {
            message = "Could not import this file. Choose the JSON exported from Setlog."
        }
    }

    func exportURL() -> URL? {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Setlog-backup.json")
        guard let data = try? encoder.encode(state) else { return nil }
        try? data.write(to: destination, options: .atomic)
        return destination
    }

    func signIn(email: String, password: String, create: Bool) async {
        accountBusy = true
        defer { accountBusy = false }
        do {
            let session = try await SharedCloud.authenticate(email: email, password: password, create: create)
            try await connect(session)
        } catch { message = error.localizedDescription }
    }

    func signOut() {
        cloudTask?.cancel()
        SharedCloud.signOut()
        cloudRecord = nil
        accountEmail = nil
        cloudConflict = false
        pendingCloudSave = false
        syncLabel = "Saved on \(deviceName) · sign in to sync"
    }

    func useSharedCopy() async {
        guard let session = SharedCloud.storedSession() else { return }
        do {
            guard let remote = try await SharedCloud.read(session) else { throw CloudFailure.missingRecord }
            backupLocal(named: "setlog-before-shared-choice")
            let selectedDay = state.activeDay
            state = remote.state
            state.activeDay = selectedDay
            Self.rollOver(&state)
            selectedWeekStart = state.weekStart
            persistLocal()
            cloudRecord = remote
            cloudConflict = false
            pendingCloudSave = false
            rememberSharedTimestamp(remote.state.updatedAt, uid: session.uid)
            syncLabel = "Shared record up to date"
        } catch { message = error.localizedDescription }
    }

    func keepIPhoneCopy() async {
        guard let session = SharedCloud.storedSession() else { return }
        do {
            guard let remote = try await SharedCloud.read(session) else { throw CloudFailure.missingRecord }
            cloudRecord = try await SharedCloud.write(session, state: state, after: remote)
            cloudConflict = false
            pendingCloudSave = false
            rememberSharedTimestamp(state.updatedAt, uid: session.uid)
            syncLabel = "Saved on \(deviceName) and shared"
        } catch { message = error.localizedDescription }
    }

    func refreshFromCloud() async {
        let rolledLocally = rollOverCurrentWeek()
        guard let session = SharedCloud.storedSession() else {
            syncLabel = "Saved on \(deviceName) · sign in to sync"
            return
        }
        do {
            if cloudRecord == nil { try await connect(session); return }
            guard !pendingCloudSave && cloudTask == nil && !cloudConflict else { return }
            guard let remote = try await SharedCloud.read(session) else { throw CloudFailure.missingRecord }
            if remote.updateTime != cloudRecord?.updateTime {
                backupLocal(named: "setlog-before-remote-update")
                let selectedDay = state.activeDay
                var merged = remote.state
                merged.history.merge(state.history) { remote, _ in remote }
                merged.weekRecords.merge(state.weekRecords, uniquingKeysWith: Self.moreCompleteArchive)
                let archiveNeedsRepair = merged.weekRecords != remote.state.weekRecords
                state = merged
                state.activeDay = selectedDay
                let rolledRemote = rollOverCurrentWeek()
                persistLocal()
                cloudRecord = remote
                rememberSharedTimestamp(remote.state.updatedAt, uid: session.uid)
                if rolledRemote || archiveNeedsRepair { scheduleCloudSave() }
            }
            if rolledLocally { scheduleCloudSave() }
            syncLabel = "Saved on \(deviceName) and shared"
        } catch { syncLabel = "Saved on \(deviceName) · sync unavailable"; message = error.localizedDescription }
    }

    private func connect(_ session: CloudSession) async throws {
        guard let remote = try await SharedCloud.read(session) else { throw CloudFailure.missingRecord }
        accountEmail = session.email
        if state.updatedAt > sharedTimestamp(uid: session.uid) && sharedTimestamp(uid: session.uid) > 0 && state != remote.state {
            cloudRecord = remote
            cloudConflict = true
            syncLabel = "Saved on \(deviceName) · choose which copy to keep"
            return
        }
        backupLocal(named: "setlog-before-shared-sync")
        let selectedDay = state.activeDay
        var merged = remote.state
        merged.history.merge(state.history) { remote, _ in remote }
        merged.weekRecords.merge(state.weekRecords, uniquingKeysWith: Self.moreCompleteArchive)
        let archiveNeedsRepair = merged.weekRecords != remote.state.weekRecords
        state = merged
        state.activeDay = selectedDay
        let rolledRemote = rollOverCurrentWeek()
        persistLocal()
        cloudRecord = remote
        cloudConflict = false
        pendingCloudSave = false
        rememberSharedTimestamp(remote.state.updatedAt, uid: session.uid)
        syncLabel = "Saved on \(deviceName) and shared"
        if rolledRemote || archiveNeedsRepair { scheduleCloudSave() }
    }

    private func sharedTimestamp(uid: String) -> Double {
        UserDefaults.standard.double(forKey: "setlog-last-shared-\(uid)")
    }

    private func rememberSharedTimestamp(_ timestamp: Double, uid: String) {
        UserDefaults.standard.set(timestamp, forKey: "setlog-last-shared-\(uid)")
    }

    private func backupLocal(named name: String) {
        guard FileManager.default.fileExists(atPath: localURL.path) else { return }
        let backup = localURL.deletingLastPathComponent().appendingPathComponent("\(name)-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: localURL, to: backup)
    }

    private func normalizeUnrecordedSets() {
        for dayIndex in state.days.indices {
            for exerciseIndex in state.days[dayIndex].exercises.indices {
                let item = state.days[dayIndex].exercises[exerciseIndex]
                let parts = item.note?.range(of: #"Last time:\s*(\d+)\s*×\s*(\d+)"#, options: .regularExpression)
                let numbers = parts.map { String(item.note![$0]).filter { $0.isNumber || $0 == " " || $0 == "×" }.split(separator: "×").map { $0.trimmingCharacters(in: .whitespaces) } }
                let previousCount = numbers?.first.flatMap(Int.init)
                let previousReps = numbers?.last
                let pristine = item.sets.allSatisfy { !$0.done && ($0.weight.isEmpty || $0.weight == item.last) && ($0.reps.isEmpty || $0.reps == item.targetReps) }
                guard pristine else { continue }
                let count = min(max(previousCount ?? item.sets.count, 1), 30)
                state.days[dayIndex].exercises[exerciseIndex].sets = (0..<count).map { _ in
                    SetEntry(weight: item.last == "—" ? "" : item.last, reps: previousReps ?? item.targetReps, done: false)
                }
            }
        }
    }

    private func changed(recordProgress: Bool = false) {
        if recordProgress {
            let day = state.days[state.activeDay]
            let key = Self.dateKey(recordDate)
            state.history[key] = WorkoutSnapshot(progress: day.progress, finished: day.isFinished,
                                                  completedSets: day.visibleSets.filter(\.done).count,
                                                  totalSets: day.visibleSets.count)
        }
        state.updatedAt = Date().timeIntervalSince1970 * 1000
        persistLocal()
        if accountEmail != nil && !cloudConflict { scheduleCloudSave() }
    }

    private static func dateKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func dateForWeekday(_ index: Int, in week: Date = Date()) -> Date {
        let calendar = Calendar.current
        let monday = monday(for: week)
        return calendar.date(byAdding: .day, value: (index + 6) % 7, to: monday) ?? week
    }

    private static func monday(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private static func weekKey(for date: Date) -> String { dateKey(monday(for: date)) }
    private static func currentWeekKey() -> String { weekKey(for: Date()) }

    private static func date(from key: String) -> Date? {
        let pieces = key.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2], hour: 12))
    }

    private static func freshDay(_ old: WorkoutDay) -> WorkoutDay {
        var day = old
        day.finished = false
        day.notes = ""
        for index in day.exercises.indices {
            let prior = day.exercises[index]
            if let latest = prior.sets.last(where: { $0.done && !$0.weight.isEmpty }) {
                day.exercises[index].last = latest.weight
            }
            for setIndex in day.exercises[index].sets.indices {
                day.exercises[index].sets[setIndex].done = false
                day.exercises[index].sets[setIndex].weight = day.exercises[index].last == "—" ? "" : day.exercises[index].last
            }
        }
        return day
    }

    private static func moreCompleteArchive(_ shared: [WorkoutDay], _ local: [WorkoutDay]) -> [WorkoutDay] {
        let sharedCount = shared.flatMap { $0.exercises.flatMap(\.sets) }.filter(\.done).count
        let localCount = local.flatMap { $0.exercises.flatMap(\.sets) }.filter(\.done).count
        return sharedCount >= localCount ? shared : local
    }

    @discardableResult
    private static func rollOver(_ state: inout WorkoutState) -> Bool {
        let current = currentWeekKey()
        if state.weekStart == nil {
            // Legacy records have no week identity. Prefer their most recent dated workout;
            // otherwise use the last edit date, so completed sets are archived before reset.
            let recorded = state.history.keys.sorted().last.flatMap(date(from:))
            let edited = Date(timeIntervalSince1970: state.updatedAt / 1000)
            state.weekStart = weekKey(for: recorded ?? edited)
        }
        guard let old = state.weekStart, old < current else { return false }
        state.weekRecords[old] = state.days
        state.days = state.days.map(freshDay)
        state.weekStart = current
        state.updatedAt = Date().timeIntervalSince1970 * 1000
        return true
    }

    @discardableResult
    private func rollOverCurrentWeek() -> Bool {
        let before = state
        guard Self.rollOver(&state) else { return false }
        backupLocal(named: "setlog-before-week-rollover")
        if selectedWeekStart == nil || selectedWeekStart == before.weekStart { selectedWeekStart = state.weekStart }
        recordDate = Self.dateForWeekday(state.activeDay)
        persistLocal()
        return true
    }

    private func persistLocal() {
        guard let data = try? encoder.encode(state) else { return }
        do { try data.write(to: localURL, options: .atomic) }
        catch { syncLabel = "Could not save on \(deviceName)" }
    }

    private func scheduleCloudSave() {
        pendingCloudSave = true
        guard cloudRecord != nil else {
            syncLabel = "Saved on \(deviceName) · waiting for shared record"
            return
        }
        guard cloudTask == nil else { return }
        cloudTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            while pendingCloudSave && !Task.isCancelled {
                pendingCloudSave = false
                guard let session = SharedCloud.storedSession(), let previous = cloudRecord else { break }
                let snapshot = state
                syncLabel = "Saving shared record…"
                do {
                    cloudRecord = try await SharedCloud.write(session, state: snapshot, after: previous)
                    rememberSharedTimestamp(snapshot.updatedAt, uid: session.uid)
                    syncLabel = "Saved on \(deviceName) and shared"
                } catch {
                    cloudConflict = true
                    syncLabel = "Saved on \(deviceName) · shared sync paused"
                    message = error.localizedDescription
                    break
                }
            }
            cloudTask = nil
        }
    }

    private func validExercise(_ index: Int) -> Bool { state.days[state.activeDay].exercises.indices.contains(index) }
    private func validSet(_ index: Int, _ setIndex: Int) -> Bool {
        validExercise(index) && state.days[state.activeDay].exercises[index].sets.indices.contains(setIndex)
    }

    private static func readState(at url: URL) throws -> WorkoutState {
        try JSONDecoder().decode(WorkoutState.self, from: Data(contentsOf: url))
    }

}

private struct ExportEnvelope: Decodable { let state: WorkoutState }
private enum ImportError: Error { case invalidSchedule }
