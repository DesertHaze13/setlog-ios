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

struct WorkoutState: Codable, Equatable {
    var activeDay: Int
    var days: [WorkoutDay]
    var updatedAt: Double

    var isValid: Bool {
        days.count == 7 && days.map(\.day) == ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            && days.allSatisfy { day in
                Set(day.exercises.map(\.id)).count == day.exercises.count && day.exercises.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty }
            }
    }
}
