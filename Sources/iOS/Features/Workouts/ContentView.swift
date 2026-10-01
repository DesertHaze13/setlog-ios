import SwiftUI
import UniformTypeIdentifiers
import Combine

private enum GymColor {
    static let green = Color(red: 0.72, green: 1, blue: 0.2)
    static let slate = Color(red: 0.27, green: 0.34, blue: 0.38)
    static let teal = Color(red: 0.11, green: 0.72, blue: 0.67)
}

struct ContentView: View {
    @ObservedObject var store: WorkoutStore
    @StateObject private var fitness = FitnessActivityStore()
    @EnvironmentObject private var theme: SolarTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlockedDays: Set<Int> = []
    @State private var showImporter = false
    @State private var pendingDeletion: SetDeletion?
    @State private var pendingExerciseDeletion: Int?
    @State private var showNewExercise = false
    @State private var showYearCalendar = false
    @State private var newExerciseName = ""
    @State private var newExerciseSets = 3
    @State private var newExerciseReps = "10"
    @State private var newExerciseLast = ""
    @State private var newExerciseNote = ""
    @State private var accountEmail = ""
    @State private var accountPassword = ""
    @State private var createAccount = false
    @State private var fitnessDate = Date()

    private var day: WorkoutDay { store.currentDay }
    private var unlocked: Bool { !store.isViewingPastWeek && unlockedDays.contains(store.state.activeDay) }
    private var card: Color { colorScheme == .dark ? Color(.secondarySystemBackground) : .white }
    private var surface: Color { colorScheme == .dark ? .black : Color(.systemGroupedBackground) }
    private let weekOrder = [1, 2, 3, 4, 5, 6, 0]
    private func isToday(_ index: Int) -> Bool {
        !store.isViewingPastWeek && index == Calendar.current.component(.weekday, from: Date()) - 1
    }
    private var fitnessDateLabel: String {
        Calendar.current.isDateInToday(fitnessDate) ? "Today" : fitnessDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private func selectScheduleDay(_ index: Int) {
        store.selectDay(index)
        let calendar = Calendar.current
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let weekStart = store.selectedWeekDate
        let startWeekday = calendar.component(.weekday, from: weekStart) - 1
        let dayOffset = (index - startWeekday + 7) % 7
        let weekDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? fitnessDate
        let chosenDate = weekDate > Date() ? Date() : weekDate
        fitnessDate = chosenDate
        store.selectRecordDate(weekDate)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    if geometry.size.width >= 720 {
                        iPadDashboard
                            .padding(.horizontal, 24)
                            .padding(.bottom, 44)
                            .frame(maxWidth: 1500)
                            .frame(maxWidth: .infinity)
                    } else {
                        phoneDashboard
                            .padding(.horizontal, 16)
                            .padding(.bottom, 38)
                            .frame(maxWidth: 820)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .background(surface.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): store.importWorkout(from: url)
            case .failure: store.message = "Could not open the selected file."
            }
        }
        .alert("Dony's Lifts", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK", role: .cancel) { store.message = nil }
        } message: { Text(store.message ?? "") }
        .confirmationDialog("Delete this set?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), presenting: pendingDeletion) { target in
            Button("Delete set", role: .destructive) {
                store.removeSet(exercise: target.exerciseIndex, set: target.setIndex)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { target in
            Text("Set \(target.setIndex + 1) of \(target.exerciseName) and its recorded load and reps will be removed.")
        }
        .confirmationDialog("Delete this workout card?", isPresented: Binding(get: { pendingExerciseDeletion != nil }, set: { if !$0 { pendingExerciseDeletion = nil } })) {
            Button("Delete workout card", role: .destructive) {
                if let index = pendingExerciseDeletion { store.removeExercise(index) }
                pendingExerciseDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingExerciseDeletion = nil }
        } message: { Text("This exercise and all its recorded sets will be removed from the selected day.") }
        .sheet(isPresented: $showNewExercise) { newExerciseSheet }
        .sheet(isPresented: $showYearCalendar) {
            YearCalendarView(history: store.state.history, days: store.state.days,
                             weekRecords: store.state.weekRecords) { date in
                store.selectWeek(containing: date)
                selectScheduleDay(store.state.activeDay)
            }
        }
        .onChange(of: scenePhase) { _, value in
            if value == .active { Task { await store.refreshFromCloud(); theme.update(); fitness.refreshIfNeeded(force: true) } }
        }
        .onReceive(Timer.publish(every: 4, on: .main, in: .common).autoconnect()) { _ in
            Task { await store.refreshFromCloud() }
            theme.update()
            fitness.refreshIfNeeded()
        }
        .task { fitness.refreshIfNeeded() }
    }

    private var phoneDashboard: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            hero
                .motionCard()
            schedule
                .motionCard()
            overview
                .motionCard()
            fitnessCard
                .motionCard()
            if day.day == "Friday" { fridayChoice.motionCard() }
            controlBar
                .motionCard()
            ForEach(day.visibleExerciseIndices, id: \.self) { index in
                exerciseCard(index)
                    .motionCard()
            }
            if unlocked { addExerciseButton }
            notesCard
                .motionCard()
            migrationCard
                .motionCard()
        }
    }

    private var iPadDashboard: some View {
        let columns = [GridItem(.adaptive(minimum: 310, maximum: 520), spacing: 18, alignment: .top)]
        return VStack(alignment: .leading, spacing: 18) {
            header
                .padding(.leading, 96)
            wideSchedule
                .motionCard()
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                hero.motionCard()
                overview.motionCard()
                fitnessCard.motionCard()
                controlBar.motionCard()
                if day.day == "Friday" { fridayChoice.motionCard() }
                notesCard.motionCard()
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Exercises")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                Spacer()
                Text("\(day.visibleExerciseIndices.count) MOVEMENTS")
                    .font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(day.visibleExerciseIndices, id: \.self) { index in
                    exerciseCard(index)
                        .motionCard()
                }
                if unlocked { addExerciseButton }
            }
            migrationCard
                .motionCard()
        }
    }

    private var wideSchedule: some View {
        HStack(spacing: 10) {
            ForEach(weekOrder, id: \.self) { index in
                let item = store.visibleDays[index]
                Button { selectScheduleDay(index) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.short.uppercased())
                                .font(.caption2.weight(.heavy)).tracking(0.5)
                            Spacer()
                            if isToday(index) {
                                Text("TODAY").font(.system(size: 9, weight: .black))
                            }
                        }
                        Text(item.day)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Label(item.isFinished ? "FINISHED" : "NOT FINISHED · \(item.progress)%",
                              systemImage: item.isFinished ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 10, weight: .heavy))
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .frame(minHeight: 104)
                    .background(item.isFinished ? GymColor.green.opacity(colorScheme == .dark ? 0.28 : 0.38) : card,
                                in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(index == store.state.activeDay ? GymColor.green : .clear, lineWidth: 2.5))
                    .shadow(color: index == store.state.activeDay ? GymColor.green.opacity(0.24) : .clear, radius: 8, y: 3)
                }
                .buttonStyle(SpringFlashButtonStyle())
                .accessibilityLabel("\(item.day), \(item.isFinished ? "finished" : "not finished"), \(item.progress)% complete")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.title2.bold()).foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(GymColor.green, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 0) {
                Text("TRAINING JOURNAL").font(.caption2.bold()).tracking(1.4).foregroundStyle(GymColor.green)
                Text("Dony's Lifts").font(.system(size: 28, weight: .black, design: .rounded)).tracking(-1.2)
                    .lineLimit(1).minimumScaleFactor(0.72).allowsTightening(true)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            Menu {
                Button { theme.setMode(.device) } label: {
                    Label("Follow device appearance", systemImage: theme.mode == .device ? "checkmark" : "iphone")
                }
                Button { theme.setMode(.sun) } label: {
                    Label("Follow sunrise & sunset", systemImage: theme.mode == .sun ? "checkmark" : "sun.horizon")
                }
            } label: {
                Image(systemName: theme.mode == .device ? "iphone" : theme.dark == true ? "moon.fill" : "sun.max.fill")
                    .font(.caption2.weight(.semibold)).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(card, in: Capsule())
            }
            .accessibilityLabel("Appearance: \(theme.label)")
        }
        .padding(.top, 8)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                Text(day.day + (isToday(store.state.activeDay) ? " · Today" : ""))
                    .font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                Text(day.title)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.65).lineLimit(2).tracking(-2)
                Text(day.focus).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(spacing: 9) {
                Text("\(day.visibleSets.filter(\.done).count) / \(day.visibleSets.count)")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundStyle(GymColor.green)
                Text("\(day.progress)% complete").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text("SETS LOGGED").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(.secondary)
                Toggle("Finished", isOn: Binding(get: { day.isFinished }, set: { store.setFinished($0) }))
                    .labelsHidden().tint(GymColor.green).scaleEffect(0.78)
                Label(day.isFinished ? "Finished" : "Not finished",
                      systemImage: day.isFinished ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(day.isFinished ? GymColor.green : surface, in: Capsule())
                    .foregroundStyle(day.isFinished ? .black : .primary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28).fill(card)
                .overlay { AmbientLiftGlow().clipShape(RoundedRectangle(cornerRadius: 28)) }
        }
    }

    private var fitnessCard: some View {
        VStack(alignment: .leading, spacing: 9) {
          HStack(spacing: 12) {
            if let summary = fitness.summary {
                AppleFitnessRingView(summary: summary)
                    .frame(width: 54, height: 54)
                    .accessibilityLabel("Apple Fitness rings for \(fitnessDateLabel)")
            } else {
                Image(systemName: "heart.text.clipboard")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, height: 54)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Apple Fitness").font(.subheadline.weight(.bold))
                Text(fitness.summary == nil ? fitness.status : "Activity for \(fitnessDateLabel)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
          }
          HStack {
            Text("Activity date").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Button(fitness.hasRequestedAccess ? "Refresh" : "Connect") {
                if fitness.hasRequestedAccess {
                    fitness.refreshIfNeeded(force: true)
                } else {
                    Task { await fitness.connect() }
                }
            }
            .font(.caption.weight(.bold))
            DatePicker("Fitness date", selection: $fitnessDate, in: ...Date(), displayedComponents: .date)
                .labelsHidden().datePickerStyle(.compact).frame(maxWidth: 108)
                .onChange(of: fitnessDate) { _, date in fitness.selectDate(date) }
          }
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(weekOrder, id: \.self) { index in
                let item = store.visibleDays[index]
                    Button { selectScheduleDay(index) } label: {
                        VStack(spacing: 3) {
                            Text(item.short.uppercased())
                                .font(.system(size: 11, weight: .black)).tracking(0.1)
                            Image(systemName: item.isFinished ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.system(size: 20, weight: .bold))
                            Text(item.isFinished ? "DONE" : "\(item.progress)%")
                                .font(.system(size: 9, weight: .heavy))
                                .lineLimit(1).minimumScaleFactor(0.8)
                            if isToday(index) {
                                Text("TODAY")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(colorScheme == .dark ? GymColor.green : Color(red: 0.24, green: 0.48, blue: 0.03))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 79)
                        .background(item.isFinished ? GymColor.green.opacity(colorScheme == .dark ? 0.28 : 0.38) : card,
                                    in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13)
                            .strokeBorder(index == store.state.activeDay ? GymColor.green : .clear, lineWidth: 2.5))
                        .shadow(color: index == store.state.activeDay ? GymColor.green.opacity(0.24) : .clear, radius: 7, y: 3)
                    }
                    .buttonStyle(SpringFlashButtonStyle())
                    .accessibilityLabel("\(item.day), \(item.isFinished ? "finished" : "not finished"), \(item.progress)% complete")
                }
            }
            Text("CHECK = FINISHED AT 80%+  ·  OUTLINE = SELECTED DAY")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(store.isViewingPastWeek ? "Week of \(store.selectedWeekDate.formatted(.dateTime.month(.abbreviated).day()))" : "This week").font(.headline)
                Spacer()
                if store.isViewingPastWeek {
                    Button("Current week") { store.selectCurrentWeek() }.font(.caption.weight(.bold))
                }
                Button("Year calendar", systemImage: "calendar") { showYearCalendar = true }
                    .font(.caption.weight(.bold))
                    .buttonStyle(SpringFlashButtonStyle())
            }
            HStack(spacing: 4) {
                ForEach(weekOrder, id: \.self) { index in
                    let item = store.visibleDays[index]
                    VStack(spacing: 5) {
                        Group {
                            if item.isFinished { Image(systemName: "checkmark").font(.caption.bold()) }
                            else { Text("\(item.progress)%").font(.caption2.bold()) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 37)
                        .background(item.isFinished ? GymColor.green : surface, in: Circle())
                        .foregroundStyle(item.isFinished ? .black : .secondary)
                        Text(item.short).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var fridayChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Friday plan").font(.headline)
            ForEach(["Glutes & Isolation", "Run + Glutes + Abs"], id: \.self) { plan in
                Button { store.setPlan(plan) } label: {
                    HStack {
                        Image(systemName: day.selectedPlan == plan ? "largecircle.fill.circle" : "circle")
                        Text(plan)
                        Spacer()
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(12)
                    .background(day.selectedPlan == plan ? GymColor.green.opacity(0.16) : surface, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(SpringFlashButtonStyle())
            }
        }
        .padding(16)
        .background(card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var controlBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(day.visibleSets.filter(\.done).count) of \(day.visibleSets.count) sets").font(.headline)
                Spacer()
                Label(store.syncLabel, systemImage: store.accountEmail == nil ? "iphone" : "cloud")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            ProgressView(value: Double(day.progress), total: 100).tint(GymColor.green)
            Button {
                if unlocked { unlockedDays.remove(store.state.activeDay) }
                else { unlockedDays.insert(store.state.activeDay) }
            } label: {
                Label(unlocked ? "Entries unlocked" : "Unlock entries", systemImage: unlocked ? "lock.open" : "lock")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity).padding(12)
                    .background(GymColor.green, in: RoundedRectangle(cornerRadius: 13))
                    .foregroundStyle(.black)
            }
            .buttonStyle(SpringFlashButtonStyle())
            .disabled(store.isViewingPastWeek)
        }
        .padding(16)
        .background(card, in: RoundedRectangle(cornerRadius: 22))
    }

    private func exerciseCard(_ index: Int) -> some View {
        let item = day.exercises[index]
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(item.targetSets) sets · target \(item.targetReps)")
                        .font(.caption2.weight(.black)).textCase(.uppercase).tracking(1.1).foregroundStyle(GymColor.green)
                    Text(item.name).font(.system(size: 24, weight: .black, design: .rounded)).tracking(-0.6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("LAST").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(.secondary)
                    if unlocked {
                        TextField("Last", text: Binding(get: { item.last }, set: { store.setLast($0, exercise: index) }))
                            .multilineTextAlignment(.trailing)
                            .font(.subheadline.weight(.bold)).frame(minWidth: 75)
                    } else {
                        Text(item.last.isEmpty ? "—" : item.last).font(.subheadline.weight(.bold)).lineLimit(2)
                    }
                }
                .padding(10)
                .background(surface, in: RoundedRectangle(cornerRadius: 13))
            }
            if unlocked {
                Button(role: .destructive) { pendingExerciseDeletion = index } label: {
                    Label("Delete workout card", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
            }
            if let note = item.note { Text(note).font(.subheadline).foregroundStyle(.secondary) }
            Divider()
            HStack {
                Text("SET").frame(width: 26)
                Text("KG / LOAD").frame(maxWidth: .infinity)
                Text("REPS / TIME").frame(maxWidth: .infinity)
                Text("DONE").frame(width: 42)
                if unlocked { Text("DEL").frame(width: 38) }
            }
            .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            ForEach(item.sets.indices, id: \.self) { setIndex in
                let entry = item.sets[setIndex]
                HStack(spacing: 6) {
                    Text("\(setIndex + 1)").font(.subheadline.bold()).foregroundStyle(.secondary).frame(width: 26)
                    if unlocked {
                        TextField("Load", text: Binding(get: { entry.weight }, set: { store.setWeight($0, exercise: index, set: setIndex) }))
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(.plain)
                            .setCell(surface)
                        TextField("Reps", text: Binding(get: { entry.reps }, set: { store.setReps($0, exercise: index, set: setIndex) }))
                            .textFieldStyle(.plain)
                            .setCell(surface)
                    } else {
                        Text(entry.weight.isEmpty ? (item.last.isEmpty ? "—" : item.last) : entry.weight)
                            .setCell(surface)
                        Text(entry.reps.isEmpty ? item.targetReps : entry.reps)
                            .setCell(surface)
                    }
                    Button { store.toggleSet(exercise: index, set: setIndex) } label: {
                        Image(systemName: entry.done ? "checkmark" : "circle.fill")
                            .font(.title3.bold())
                            .foregroundStyle(entry.done ? .black : Color(.tertiarySystemFill))
                            .frame(width: 39, height: 39)
                            .background(entry.done ? GymColor.green : Color(.tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(SpringFlashButtonStyle())
                    .disabled(store.isViewingPastWeek)
                    .accessibilityLabel("\(item.name), set \(setIndex + 1), \(entry.done ? "done" : "not done")")
                    if unlocked {
                        Button {
                            pendingDeletion = SetDeletion(exerciseIndex: index, setIndex: setIndex, exerciseName: item.name)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                                .frame(width: 38, height: 39)
                        }
                        .buttonStyle(SpringFlashButtonStyle())
                        .accessibilityLabel("Delete \(item.name) set \(setIndex + 1)")
                    }
                }
            }
            Button { store.addSet(exercise: index) } label: {
                Label("Add set", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5])))
            }
            .buttonStyle(SpringFlashButtonStyle())
            .disabled(store.isViewingPastWeek)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workout notes").font(.headline)
            TextEditor(text: Binding(get: { day.notes }, set: { store.setNotes($0) }))
                .disabled(store.isViewingPastWeek)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 95)
                .padding(8)
                .background(surface, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityLabel("Workout notes")
        }
        .padding(16)
        .background(card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var addExerciseButton: some View {
        Button { showNewExercise = true } label: {
            Label("Add workout card", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(card, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(SpringFlashButtonStyle())
        .accessibilityHint("Adds an exercise to \(day.day); unlock entries first")
    }

    private var newExerciseSheet: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Exercise name", text: $newExerciseName)
                    Stepper("\(newExerciseSets) sets", value: $newExerciseSets, in: 1...30)
                    TextField("Target reps or time", text: $newExerciseReps)
                    TextField("Last weight or load", text: $newExerciseLast)
                    TextField("Notes (optional)", text: $newExerciseNote)
                }
                if day.day == "Friday" {
                    Text("This card will be added to the selected Friday plan: \(day.selectedPlan ?? "Glutes & Isolation").")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New workout card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showNewExercise = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addExercise(name: newExerciseName, targetSets: newExerciseSets,
                                          targetReps: newExerciseReps, last: newExerciseLast, note: newExerciseNote)
                        newExerciseName = ""
                        newExerciseSets = 3
                        newExerciseReps = "10"
                        newExerciseLast = ""
                        newExerciseNote = ""
                        showNewExercise = false
                    }
                    .disabled(newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var migrationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shared data").font(.headline)
            if let email = store.accountEmail {
                Text("Signed in as \(email)").font(.subheadline).foregroundStyle(.secondary)
                Text(store.syncLabel).font(.caption).foregroundStyle(.secondary)
                if store.cloudConflict {
                    Text("This device's copy and the shared copy differ. Nothing was overwritten.")
                        .font(.caption).foregroundStyle(.orange)
                    HStack {
                        Button("Use shared copy") { Task { await store.useSharedCopy() } }
                        Button("Keep this copy") { Task { await store.keepIPhoneCopy() } }
                    }.buttonStyle(.bordered)
                }
                Button("Sign out") { store.signOut() }.buttonStyle(.bordered)
            } else {
                Text("Sign in on the website first, then use the same email and password here. The website's reviewed five Thursday sets become the shared copy.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("Email", text: $accountEmail)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $accountPassword)
                    .textContentType(createAccount ? .newPassword : .password)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(store.accountBusy ? "Connecting…" : createAccount ? "Create account" : "Sign in & sync") {
                        let password = accountPassword
                        accountPassword = ""
                        Task { await store.signIn(email: accountEmail.trimmingCharacters(in: .whitespacesAndNewlines), password: password, create: createAccount) }
                    }
                    .buttonStyle(.borderedProminent).tint(GymColor.green).foregroundStyle(.black)
                    .disabled(store.accountBusy || accountEmail.isEmpty || accountPassword.count < 6)
                    Button(createAccount ? "I have an account" : "Create account") { createAccount.toggle() }
                        .buttonStyle(.bordered)
                }
            }
            Divider()
            Text("Local backup").font(.subheadline.weight(.semibold))
            HStack {
                Button("Import JSON") { showImporter = true }.buttonStyle(.bordered)
                if let url = store.exportURL() {
                    ShareLink(item: url) { Label("Back up", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(card, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct YearCalendarView: View {
    let history: [String: WorkoutSnapshot]
    let days: [WorkoutDay]
    let weekRecords: [String: [WorkoutDay]]
    let onSelectWeek: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var selectedDate: Date? = Date()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    private func weekKey(_ date: Date) -> String {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let monday = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let parts = calendar.dateComponents([.year, .month, .day], from: monday)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func snapshot(_ date: Date) -> WorkoutSnapshot? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let key = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        let week = weekKey(date)
        let index = calendar.component(.weekday, from: date) - 1
        if let archived = weekRecords[week], archived.indices.contains(index) {
            let day = archived[index]
            return WorkoutSnapshot(progress: day.progress, finished: day.isFinished,
                                   completedSets: day.visibleSets.filter(\.done).count, totalSets: day.visibleSets.count)
        }
        if let recorded = history[key] { return recorded }
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        guard date <= Date(),
              let thisWeek = mondayCalendar.dateInterval(of: .weekOfYear, for: Date()),
              thisWeek.contains(date) else { return nil }
        guard days.indices.contains(index) else { return nil }
        let day = days[index]
        return WorkoutSnapshot(progress: day.progress, finished: day.isFinished,
                               completedSets: day.visibleSets.filter(\.done).count, totalSets: day.visibleSets.count)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                    Text("Tap any date to view its Monday–Sunday week. The highlighted row is the selected week. Older workout details stay saved; past weeks are read-only.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let selectedDate {
                        let result = snapshot(selectedDate)
                        HStack {
                            Text(selectedDate.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                            Spacer()
                            Text(result.map { "\($0.progress)% · \($0.completedSets)/\($0.totalSets) sets" } ?? "No record")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(14)
                        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                    Button("Show selected week") {
                        if let selectedDate { onSelectWeek(selectedDate); dismiss() }
                    }
                    .disabled(selectedDate == nil)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 14)], spacing: 14) {
                        ForEach(1...12, id: \.self) { month in monthCard(month).id(month) }
                    }
                    }
                    .padding(16)
                }
                .onAppear {
                    let now = Date()
                    year = Calendar.current.component(.year, from: now)
                    selectedDate = now
                    DispatchQueue.main.async {
                        proxy.scrollTo(Calendar.current.component(.month, from: now), anchor: .center)
                    }
                }
            }
            .navigationTitle("\(year) workouts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                        Button { year += 1 } label: { Image(systemName: "chevron.right") }
                            .disabled(year >= Calendar.current.component(.year, from: Date()))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let selectedDate { onSelectWeek(selectedDate) }
                        dismiss()
                    }
                }
            }
        }
    }

    private func monthCard(_ month: Int) -> some View {
        let calendar = Calendar.current
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let count = calendar.range(of: .day, in: .month, for: first)!.count
        let offset = (calendar.component(.weekday, from: first) + 5) % 7
        return VStack(alignment: .leading, spacing: 9) {
            Text(first.formatted(.dateTime.month(.wide))).font(.headline)
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(weekdays.indices, id: \.self) { index in
                    Text(weekdays[index]).font(.caption2.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                ForEach(0..<(offset + count), id: \.self) { position in
                    if position < offset {
                        Color.clear.frame(height: 47)
                    } else {
                        let number = position - offset + 1
                        let date = calendar.date(from: DateComponents(year: year, month: month, day: number))!
                        let result = snapshot(date)
                        Button { selectedDate = date } label: {
                            VStack(spacing: 1) {
                                Text("\(number)").font(.system(size: 11, weight: .semibold))
                                if let result {
                                    if result.finished { Image(systemName: "checkmark").font(.system(size: 10, weight: .black)) }
                                    Text("\(result.progress)%").font(.system(size: 9, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity).frame(height: 47)
                            .background(result?.finished == true ? GymColor.green : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(
                                weekKey(date) == (selectedDate.map(weekKey) ?? weekKey(Date()))
                                    ? (result?.finished == true ? .black : GymColor.green) : .clear, lineWidth: 2.5))
                            .foregroundStyle(result?.finished == true ? .black : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)), \(result.map { "\($0.progress) percent complete" } ?? "no record")")
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct SetDeletion {
    let exerciseIndex: Int
    let setIndex: Int
    let exerciseName: String
}

private struct AmbientLiftGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var drift = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Circle()
                    .fill(GymColor.green.opacity(colorScheme == .dark ? 0.16 : 0.12))
                    .frame(width: geometry.size.width * 0.7)
                    .blur(radius: 45)
                    .offset(x: drift ? geometry.size.width * 0.55 : geometry.size.width * 0.05,
                            y: drift ? -45 : 70)
                Circle()
                    .fill(GymColor.teal.opacity(colorScheme == .dark ? 0.13 : 0.08))
                    .frame(width: geometry.size.width * 0.42)
                    .blur(radius: 35)
                    .offset(x: drift ? -geometry.size.width * 0.37 : 30, y: drift ? 55 : -40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 11).repeatForever(autoreverses: true), value: drift)
            .onAppear { if !reduceMotion { drift = true } }
            .onChange(of: reduceMotion) { _, enabled in drift = !enabled }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MotionCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shouldReduceMotion = reduceMotion
        return content.scrollTransition(.interactive, axis: .vertical) { view, phase in
            view
                .scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.965)
                .opacity(shouldReduceMotion || phase.isIdentity ? 1 : 0.78)
                .offset(y: shouldReduceMotion || phase.isIdentity ? 0 : 10)
        }
    }
}

private struct CornerFlashShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX + 5, y = rect.minY + 5
        let right = rect.maxX - 5, bottom = rect.maxY - 5
        let length = min(13, min(rect.width, rect.height) / 4)
        return Path { path in
            path.move(to: CGPoint(x: x, y: y + length)); path.addLine(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x + length, y: y))
            path.move(to: CGPoint(x: right - length, y: y)); path.addLine(to: CGPoint(x: right, y: y)); path.addLine(to: CGPoint(x: right, y: y + length))
            path.move(to: CGPoint(x: right, y: bottom - length)); path.addLine(to: CGPoint(x: right, y: bottom)); path.addLine(to: CGPoint(x: right - length, y: bottom))
            path.move(to: CGPoint(x: x + length, y: bottom)); path.addLine(to: CGPoint(x: x, y: bottom)); path.addLine(to: CGPoint(x: x, y: bottom - length))
        }
    }
}

private struct SpringFlashButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AnimatedTapButton(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct TapBloomValues {
    var scale = 0.82
    var opacity = 0.0
}

private struct AnimatedTapButton<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloomCount = 0

    var body: some View {
        label
            .scaleEffect(reduceMotion ? 1 : isPressed ? 0.96 : 1)
            .overlay {
                CornerFlashShape()
                    .stroke(GymColor.green.opacity(isPressed ? 0.9 : 0), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .allowsHitTesting(false)
            }
            .overlay {
                if !reduceMotion {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(GymColor.green, lineWidth: 2)
                        Image(systemName: "sparkle")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(GymColor.green)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .offset(x: 7, y: -7)
                        Image(systemName: "sparkle")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(GymColor.teal)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .offset(x: -5, y: 5)
                    }
                    .keyframeAnimator(initialValue: TapBloomValues(), trigger: bloomCount) { content, value in
                        content.scaleEffect(value.scale).opacity(value.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(0.82, duration: 0.01)
                            SpringKeyframe(1.18, duration: 0.52, spring: .smooth)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0, duration: 0.01)
                            CubicKeyframe(0.85, duration: 0.12)
                            CubicKeyframe(0, duration: 0.40)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.58), value: isPressed)
            .onChange(of: isPressed) { wasPressed, pressed in
                if wasPressed && !pressed && !reduceMotion { bloomCount += 1 }
            }
    }
}

private extension View {
    func motionCard() -> some View { modifier(MotionCardModifier()) }

    func setCell(_ background: Color) -> some View {
        self.font(.subheadline.weight(.semibold))
            .lineLimit(1).minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: 39)
            .multilineTextAlignment(.center)
            .background(background, in: RoundedRectangle(cornerRadius: 11))
    }
}
