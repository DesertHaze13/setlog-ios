import Foundation
import Combine

@MainActor
final class WorkoutStore: ObservableObject {
    #if os(macOS)
    private let deviceName = "Mac"
    #else
    private let deviceName = "iPhone"
    #endif
    @Published private(set) var state: WorkoutState
    @Published private(set) var syncLabel = "Saved locally"
    @Published private(set) var accountEmail: String?
    @Published private(set) var cloudConflict = false
    @Published private(set) var accountBusy = false
    @Published var message: String?

    private let localURL: URL
    private var cloudTask: Task<Void, Never>?
    private var cloudRecord: CloudRecord?
    private var pendingCloudSave = false
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
        if isFirstLaunch { normalizeUnrecordedSets() }
        accountEmail = SharedCloud.storedSession()?.email
        persistLocal()
        Task { await refreshFromCloud() }
    }

    var currentDay: WorkoutDay { state.days[state.activeDay] }

    func selectDay(_ index: Int) {
        guard state.days.indices.contains(index) else { return }
        state.activeDay = index
        persistLocal()
    }

    func setPlan(_ plan: String) {
        state.days[state.activeDay].selectedPlan = plan
        changed()
    }

    func setFinished(_ finished: Bool) {
        state.days[state.activeDay].finished = finished
        changed()
    }

    func setNotes(_ notes: String) {
        state.days[state.activeDay].notes = notes
        changed()
    }

    func setLast(_ value: String, exercise index: Int) {
        guard validExercise(index) else { return }
        state.days[state.activeDay].exercises[index].last = value
        changed()
    }

    func setWeight(_ value: String, exercise index: Int, set setIndex: Int) {
        guard validSet(index, setIndex) else { return }
        state.days[state.activeDay].exercises[index].sets[setIndex].weight = value
        changed()
    }

    func setReps(_ value: String, exercise index: Int, set setIndex: Int) {
        guard validSet(index, setIndex) else { return }
        state.days[state.activeDay].exercises[index].sets[setIndex].reps = value
        changed()
    }

    func toggleSet(exercise index: Int, set setIndex: Int) {
        guard validSet(index, setIndex) else { return }
        state.days[state.activeDay].exercises[index].sets[setIndex].done.toggle()
        changed()
    }

    func addSet(exercise index: Int) {
        guard validExercise(index) else { return }
        let item = state.days[state.activeDay].exercises[index]
        state.days[state.activeDay].exercises[index].sets.append(
            SetEntry(weight: item.last == "—" ? "" : item.last, reps: item.targetReps, done: false)
        )
        changed()
    }

    func removeSet(exercise index: Int, set setIndex: Int) {
        guard validSet(index, setIndex) else { return }
        state.days[state.activeDay].exercises[index].sets.remove(at: setIndex)
        changed()
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
                state = remote.state
                state.activeDay = selectedDay
                persistLocal()
                cloudRecord = remote
                rememberSharedTimestamp(remote.state.updatedAt, uid: session.uid)
            }
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
        state = remote.state
        state.activeDay = selectedDay
        persistLocal()
        cloudRecord = remote
        cloudConflict = false
        pendingCloudSave = false
        rememberSharedTimestamp(remote.state.updatedAt, uid: session.uid)
        syncLabel = "Saved on \(deviceName) and shared"
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

    private func changed() {
        state.updatedAt = Date().timeIntervalSince1970 * 1000
        persistLocal()
        if accountEmail != nil && !cloudConflict { scheduleCloudSave() }
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
