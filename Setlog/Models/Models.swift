import Foundation

struct SetEntry: Codable, Equatable {
    var weight: String
    var reps: String
    var done: Bool
}

struct Exercise: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var targetSets: String
    var targetReps: String
    var last: String
    var note: String?
    var group: String?
    var sets: [SetEntry]
}

struct WorkoutDay: Codable, Equatable {
    var day: String
    var short: String
    var title: String
    var focus: String
    var finished: Bool
    var notes: String
    var selectedPlan: String?
    var exercises: [Exercise]

    var visibleExerciseIndices: [Int] {
        exercises.indices.filter { index in
            day != "Friday" || exercises[index].group == (selectedPlan ?? "Glutes & Isolation")
        }
    }

    var visibleSets: [SetEntry] {
        visibleExerciseIndices.flatMap { exercises[$0].sets }
    }

    var progress: Int {
        let sets = visibleSets
        if sets.isEmpty { return finished ? 100 : 0 }
        return Int((Double(sets.filter(\.done).count) / Double(sets.count) * 100).rounded())
    }

    var isFinished: Bool { finished || progress >= 80 }
}

struct WorkoutSnapshot: Codable, Equatable {
    var progress: Int
    var finished: Bool
    var completedSets: Int
    var totalSets: Int
}

struct WorkoutState: Codable, Equatable {
    var activeDay: Int
    var days: [WorkoutDay]
    var updatedAt: Double
    var history: [String: WorkoutSnapshot] = [:]
    var weekStart: String? = nil
    var weekRecords: [String: [WorkoutDay]] = [:]

    enum CodingKeys: String, CodingKey { case activeDay, days, updatedAt, history, weekStart, weekRecords }

    init(activeDay: Int, days: [WorkoutDay], updatedAt: Double, history: [String: WorkoutSnapshot] = [:]) {
        self.activeDay = activeDay
        self.days = days
        self.updatedAt = updatedAt
        self.history = history
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        activeDay = try values.decode(Int.self, forKey: .activeDay)
        days = try values.decode([WorkoutDay].self, forKey: .days)
        updatedAt = try values.decode(Double.self, forKey: .updatedAt)
        history = try values.decodeIfPresent([String: WorkoutSnapshot].self, forKey: .history) ?? [:]
        weekStart = try values.decodeIfPresent(String.self, forKey: .weekStart)
        weekRecords = try values.decodeIfPresent([String: [WorkoutDay]].self, forKey: .weekRecords) ?? [:]
    }

    var isValid: Bool {
        days.count == 7 && days.map(\.day) == ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            && days.allSatisfy { day in
                Set(day.exercises.map(\.id)).count == day.exercises.count && day.exercises.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty }
            }
    }
}
