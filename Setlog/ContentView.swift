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
    @State private var accountEmail = ""
    @State private var accountPassword = ""
    @State private var createAccount = false
    @State private var fitnessDate = Date()

    private var day: WorkoutDay { store.currentDay }
    private var unlocked: Bool { unlockedDays.contains(store.state.activeDay) }
    private var card: Color { colorScheme == .dark ? Color(.secondarySystemBackground) : .white }
    private var surface: Color { colorScheme == .dark ? .black : Color(.systemGroupedBackground) }
    private var fitnessDateLabel: String {
        Calendar.current.isDateInToday(fitnessDate) ? "Today" : fitnessDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private func selectScheduleDay(_ index: Int) {
        store.selectDay(index)
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: fitnessDate)?.start ?? calendar.startOfDay(for: fitnessDate)
        let startWeekday = calendar.component(.weekday, from: weekStart) - 1
        let dayOffset = (index - startWeekday + 7) % 7
        let weekDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? fitnessDate
        let chosenDate = weekDate > Date() ? (calendar.date(byAdding: .day, value: -7, to: weekDate) ?? weekDate) : weekDate
        fitnessDate = chosenDate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    hero
                    schedule
                    overview
                    fitnessCard
                    if day.day == "Friday" { fridayChoice }
                    controlBar
                    ForEach(day.visibleExerciseIndices, id: \.self) { index in
                        exerciseCard(index)
                    }
                    notesCard
                    migrationCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 38)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
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
        .onChange(of: scenePhase) { _, value in
            if value == .active { Task { await store.refreshFromCloud(); theme.update(); fitness.refreshIfNeeded() } }
        }
        .onReceive(Timer.publish(every: 4, on: .main, in: .common).autoconnect()) { _ in
            Task { await store.refreshFromCloud() }
            theme.update()
            fitness.refreshIfNeeded()
        }
        .task { fitness.refreshIfNeeded() }
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
            }
            Spacer()
            Menu {
                Button { theme.setMode(.device) } label: {
                    Label("Follow iPhone appearance", systemImage: theme.mode == .device ? "checkmark" : "iphone")
                }
                Button { theme.setMode(.sun) } label: {
                    Label("Follow sunrise & sunset", systemImage: theme.mode == .sun ? "checkmark" : "sun.horizon")
                }
            } label: {
                Label(theme.label, systemImage: theme.mode == .device ? "iphone" : theme.dark == true ? "moon.fill" : "sun.max.fill")
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
                Text(day.day + (store.state.activeDay == Calendar.current.component(.weekday, from: Date()) - 1 ? " · Today" : ""))
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
                Text("SETS LOGGED").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(.secondary)
                Toggle("Finished", isOn: Binding(get: { day.isFinished }, set: { store.setFinished($0) }))
                    .labelsHidden().tint(GymColor.green).scaleEffect(0.78)
                Text(day.isFinished ? "Finished" : "Not finished")
                    .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card, in: RoundedRectangle(cornerRadius: 28))
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
            if fitness.summary == nil {
                Button(fitness.hasRequestedAccess ? "Refresh" : "Connect") { Task { await fitness.connect() } }
                    .font(.caption.weight(.bold))
            }
            DatePicker("Fitness date", selection: $fitnessDate, in: ...Date(), displayedComponents: .date)
                .labelsHidden().datePickerStyle(.compact).frame(maxWidth: 108)
                .onChange(of: fitnessDate) { _, date in fitness.selectDate(date) }
          }
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var schedule: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.state.days.indices, id: \.self) { index in
                    let item = store.state.days[index]
                    Button { selectScheduleDay(index) } label: {
                        VStack(spacing: 3) {
                            Text(item.short).font(.caption2.bold()).foregroundStyle(.secondary)
                            HStack(spacing: 2) {
                                Text(index == Calendar.current.component(.weekday, from: Date()) - 1 ? "Today" : "\(index + 1)")
                                if item.isFinished { Image(systemName: "checkmark").font(.caption2.bold()) }
                            }.font(.caption.weight(.heavy))
                        }
                        .frame(minWidth: 54, minHeight: 48)
                        .background(index == store.state.activeDay ? GymColor.green : card, in: RoundedRectangle(cornerRadius: 15))
                        .foregroundStyle(index == store.state.activeDay ? .black : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("This week").font(.headline)
                Spacer()
                Text("80% completes a day").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(store.state.days.indices, id: \.self) { index in
                    let item = store.state.days[index]
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
                .buttonStyle(.plain)
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
            .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
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
                        .buttonStyle(.plain)
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
            .buttonStyle(.plain)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workout notes").font(.headline)
            TextEditor(text: Binding(get: { day.notes }, set: { store.setNotes($0) }))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 95)
                .padding(8)
                .background(surface, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityLabel("Workout notes")
        }
        .padding(16)
        .background(card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var migrationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shared data").font(.headline)
            if let email = store.accountEmail {
                Text("Signed in as \(email)").font(.subheadline).foregroundStyle(.secondary)
                Text(store.syncLabel).font(.caption).foregroundStyle(.secondary)
                if store.cloudConflict {
                    Text("Your iPhone copy and the shared copy differ. Nothing was overwritten.")
                        .font(.caption).foregroundStyle(.orange)
                    HStack {
                        Button("Use shared copy") { Task { await store.useSharedCopy() } }
                        Button("Keep iPhone copy") { Task { await store.keepIPhoneCopy() } }
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

private struct SetDeletion {
    let exerciseIndex: Int
    let setIndex: Int
    let exerciseName: String
}

private extension View {
    func setCell(_ background: Color) -> some View {
        self.font(.subheadline.weight(.semibold))
            .lineLimit(1).minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: 39)
            .multilineTextAlignment(.center)
            .background(background, in: RoundedRectangle(cornerRadius: 11))
    }
}
