import Foundation
import Combine
import HealthKit
import HealthKitUI
import SwiftUI

@MainActor
final class FitnessActivityStore: ObservableObject {
    @Published private(set) var summary: HKActivitySummary?
    @Published private(set) var status = "Connect Apple Fitness"
    @Published private(set) var hasRequestedAccess = UserDefaults.standard.bool(forKey: "setlog-fitness-access-requested")

    private let store = HKHealthStore()
    private var query: HKActivitySummaryQuery?
    private var queriedDay: Date?
    private(set) var selectedDate = Date()

    func selectDate(_ date: Date) {
        selectedDate = date
        refreshIfNeeded(force: true)
    }

    func connect() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = "Fitness data unavailable on this device"
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [HKObjectType.activitySummaryType()])
            hasRequestedAccess = true
            UserDefaults.standard.set(true, forKey: "setlog-fitness-access-requested")
            refreshIfNeeded(force: true)
        } catch {
            status = "Could not connect Fitness: \(error.localizedDescription)"
        }
    }

    func refreshIfNeeded(force: Bool = false) {
        guard hasRequestedAccess, HKHealthStore.isHealthDataAvailable() else { return }
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: selectedDate)
        guard force || queriedDay != selectedDay || query == nil else { return }
        if let query { store.stop(query) }
        queriedDay = selectedDay
        summary = nil
        status = "Loading Fitness rings…"

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay.addingTimeInterval(86_400)
        var start = calendar.dateComponents([.era, .year, .month, .day], from: selectedDay)
        var end = calendar.dateComponents([.era, .year, .month, .day], from: tomorrow)
        start.calendar = calendar
        end.calendar = calendar
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: start, end: end)
        let query = HKActivitySummaryQuery(predicate: predicate) { [weak self] _, summaries, error in
            self?.accept(summaries, error: error, for: selectedDay)
        }
        query.updateHandler = { [weak self] _, summaries, error in
            self?.accept(summaries, error: error, for: selectedDay)
        }
        self.query = query
        store.execute(query)
    }

    nonisolated private func accept(_ summaries: [HKActivitySummary]?, error: Error?, for date: Date) {
        let latest = summaries?.first
        let errorText = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.queriedDay == date else { return }
            self.summary = latest
            self.status = errorText.map { "Fitness could not load: \($0)" }
                ?? (latest == nil ? "No Fitness rings for this date. Check Health permissions and watch data." : "Apple Fitness")
        }
    }
}

struct AppleFitnessRingView: UIViewRepresentable {
    let summary: HKActivitySummary

    func makeUIView(context: Context) -> HKActivityRingView {
        HKActivityRingView(frame: .zero)
    }

    func updateUIView(_ view: HKActivityRingView, context: Context) {
        view.setActivitySummary(summary, animated: true)
    }
}
