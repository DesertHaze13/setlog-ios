import SwiftUI
import WatchConnectivity

@main
struct DonyLiftsWatchApp: App {
    @StateObject private var bridge = WatchWorkoutBridge()
    var body: some Scene {
        WindowGroup { WatchHome().environmentObject(bridge) }
    }
}

final class WatchWorkoutBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published var state: WorkoutState?
    @Published var connected = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        load(WCSession.default.receivedApplicationContext)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.connected = activationState == .activated }
        load(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        load(applicationContext)
    }

    private func load(_ context: [String: Any]) {
        guard let data = context["state"] as? Data,
              let decoded = try? JSONDecoder().decode(WorkoutState.self, from: data), decoded.isValid else { return }
        DispatchQueue.main.async { self.state = decoded }
    }

    func perform(_ action: String, day: Int, exercise: String, set: Int? = nil, value: Any? = nil) {
        var command: [String: Any] = ["action": action, "day": day, "exercise": exercise]
        if let set { command["set"] = set }
        if let value { command["value"] = value }
        guard WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(command, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(command)
            }
        } else {
            WCSession.default.transferUserInfo(command)
        }
    }
}

private let liftGreen = Color(red: 0.62, green: 0.9, blue: 0.23)

struct WatchHome: View {
    @EnvironmentObject private var bridge: WatchWorkoutBridge
    var body: some View {
        NavigationStack {
            Group {
                if let state = bridge.state {
                    List(Array(state.days.enumerated()), id: \.offset) { index, day in
                        NavigationLink {
                            WatchDay(dayIndex: index)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(day.day).font(.headline)
                                    Text(day.focus).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text("\(day.progress)%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(day.isFinished ? liftGreen : .secondary)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Waiting for iPhone", systemImage: "iphone.gen3", description: Text("Open Dony's Lifts on your paired iPhone to sync your workout."))
                }
            }
            .navigationTitle("Dony's Lifts")
        }
        .tint(liftGreen)
    }
}

struct WatchDay: View {
    @EnvironmentObject private var bridge: WatchWorkoutBridge
    let dayIndex: Int

    var body: some View {
        Group {
            if let state = bridge.state, state.days.indices.contains(dayIndex) {
                let day = state.days[dayIndex]
                List {
                    Section {
                        Text(day.focus).font(.caption).foregroundStyle(.secondary)
                        Text("\(day.progress)% complete")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(day.isFinished ? liftGreen : .primary)
                    }
                    if day.day == "Friday" {
                        Section("Today's plan") {
                            Text(day.selectedPlan ?? "Glutes & Isolation")
                                .foregroundStyle(.secondary)
                            Text("Choose Friday's plan on iPhone.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(day.visibleExerciseIndices, id: \.self) { index in
                        let item = day.exercises[index]
                        NavigationLink {
                            WatchExercise(dayIndex: dayIndex, exerciseID: item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.headline).lineLimit(2)
                                Text("\(item.sets.filter(\.done).count)/\(item.sets.count) sets · target \(item.targetReps)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !day.notes.isEmpty {
                        Section("Notes") { Text(day.notes).font(.caption) }
                    }
                }
                .navigationTitle(day.day)
            }
        }
    }
}

struct WatchExercise: View {
    @EnvironmentObject private var bridge: WatchWorkoutBridge
    let dayIndex: Int
    let exerciseID: String
    @State private var unlocked = false

    var body: some View {
        Group {
            if let state = bridge.state,
               state.days.indices.contains(dayIndex),
               let exerciseIndex = state.days[dayIndex].exercises.firstIndex(where: { $0.id == exerciseID }) {
                let item = state.days[dayIndex].exercises[exerciseIndex]
                List {
                    Section {
                        Text("Target: \(item.targetSets) sets · \(item.targetReps)")
                            .font(.caption).foregroundStyle(liftGreen)
                        Text("Last: \(item.last)").font(.caption)
                        if let note = item.note, !note.isEmpty { Text(note).font(.caption2).foregroundStyle(.secondary) }
                    }
                    ForEach(item.sets.indices, id: \.self) { index in
                        let entry = item.sets[index]
                        VStack(alignment: .leading, spacing: 5) {
                            Button {
                                bridge.perform("done", day: dayIndex, exercise: exerciseID, set: index, value: !entry.done)
                                bridge.state?.days[dayIndex].exercises[exerciseIndex].sets[index].done.toggle()
                            } label: {
                                HStack {
                                    Image(systemName: entry.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(entry.done ? liftGreen : .secondary)
                                    Text("Set \(index + 1)").font(.headline)
                                    Spacer()
                                    Text(entry.done ? "Done" : "Open").font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                            if unlocked {
                                TextField("Load", text: Binding(
                                    get: { bridge.state?.days[dayIndex].exercises[exerciseIndex].sets[index].weight ?? "" },
                                    set: { bridge.state?.days[dayIndex].exercises[exerciseIndex].sets[index].weight = $0; bridge.perform("weight", day: dayIndex, exercise: exerciseID, set: index, value: $0) }
                                ))
                                TextField("Reps", text: Binding(
                                    get: { bridge.state?.days[dayIndex].exercises[exerciseIndex].sets[index].reps ?? "" },
                                    set: { bridge.state?.days[dayIndex].exercises[exerciseIndex].sets[index].reps = $0; bridge.perform("reps", day: dayIndex, exercise: exerciseID, set: index, value: $0) }
                                ))
                                Button("Delete set", role: .destructive) {
                                    bridge.perform("remove", day: dayIndex, exercise: exerciseID, set: index)
                                    bridge.state?.days[dayIndex].exercises[exerciseIndex].sets.remove(at: index)
                                }.font(.caption)
                            } else {
                                Text("\(entry.weight.isEmpty ? "—" : entry.weight) · \(entry.reps.isEmpty ? "—" : entry.reps) reps")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if unlocked {
                        Button("Add set", systemImage: "plus") {
                            bridge.perform("add", day: dayIndex, exercise: exerciseID)
                            bridge.state?.days[dayIndex].exercises[exerciseIndex].sets.append(
                                SetEntry(weight: item.last == "—" ? "" : item.last, reps: item.targetReps, done: false)
                            )
                        }
                    }
                }
                .navigationTitle(item.name)
                .toolbar {
                    Button(unlocked ? "Lock" : "Unlock", systemImage: unlocked ? "lock.open" : "lock") {
                        unlocked.toggle()
                    }
                }
            }
        }
    }
}
