import Foundation
import Combine
import WatchConnectivity

final class WatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    private weak var store: WorkoutStore?
    private var observation: AnyCancellable?

    @MainActor func connect(store: WorkoutStore) {
        guard WCSession.isSupported() else { return }
        self.store = store
        let session = WCSession.default
        session.delegate = self
        session.activate()
        observation = store.$state.sink { [weak self] state in self?.send(state) }
    }

    private func send(_ state: WorkoutState) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(state) else { return }
        try? WCSession.default.updateApplicationContext(["state": data])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { Task { @MainActor in if let store { send(store.state) } } }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    private func handle(_ command: [String: Any]) {
        Task { @MainActor in
            guard let store, !store.cloudConflict,
                  let weekStart = command["weekStart"] as? String, weekStart == store.state.weekStart,
                  let day = command["day"] as? Int, store.state.days.indices.contains(day),
                  let exerciseID = command["exercise"] as? String,
                  let exercise = store.state.days[day].exercises.firstIndex(where: { $0.id == exerciseID }),
                  let action = command["action"] as? String else { return }
            let originalDay = store.state.activeDay
            let originalWeek = store.selectedWeekDate
            store.selectCurrentWeek()
            store.selectDay(day)
            defer { store.selectDay(originalDay); store.selectWeek(containing: originalWeek) }
            switch action {
            case "done":
                guard let index = command["set"] as? Int,
                      let done = command["value"] as? Bool,
                      store.state.days[day].exercises[exercise].sets.indices.contains(index) else { return }
                if store.state.days[day].exercises[exercise].sets[index].done != done {
                    store.toggleSet(exercise: exercise, set: index)
                }
            case "add": store.addSet(exercise: exercise)
            case "remove":
                if let index = command["set"] as? Int { store.removeSet(exercise: exercise, set: index) }
            case "weight":
                if let index = command["set"] as? Int, let value = command["value"] as? String {
                    store.setWeight(value, exercise: exercise, set: index)
                }
            case "reps":
                if let index = command["set"] as? Int, let value = command["value"] as? String {
                    store.setReps(value, exercise: exercise, set: index)
                }
            default: break
            }
            send(store.state)
        }
    }
}
