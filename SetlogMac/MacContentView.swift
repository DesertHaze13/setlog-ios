import SwiftUI

private let gymGreen = Color(red: 0.49, green: 0.77, blue: 0.12)

private struct MacAmbientGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geometry in
            Circle()
                .fill(gymGreen.opacity(0.14))
                .frame(width: min(geometry.size.width * 0.55, 430))
                .blur(radius: 55)
                .offset(x: drift ? geometry.size.width * 0.62 : geometry.size.width * 0.2,
                        y: drift ? -70 : 55)
                .animation(reduceMotion ? nil : .easeInOut(duration: 12).repeatForever(autoreverses: true), value: drift)
                .onAppear { if !reduceMotion { drift = true } }
                .onChange(of: reduceMotion) { _, enabled in drift = !enabled }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MacMotionCard: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shouldReduceMotion = reduceMotion
        return content.scrollTransition(.interactive, axis: .vertical) { view, phase in
            view.scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.975)
                .opacity(shouldReduceMotion || phase.isIdentity ? 1 : 0.82)
        }
    }
}

private struct MacMotionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MacTapButton(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct MacBloomValues {
    var scale = 0.82
    var opacity = 0.0
}

private struct MacTapButton<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloomCount = 0

    var body: some View {
        label
            .scaleEffect(reduceMotion ? 1 : isPressed ? 0.96 : 1)
            .overlay {
                if !reduceMotion {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(gymGreen, lineWidth: 2)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(gymGreen)
                                .offset(x: 7, y: -7)
                        }
                        .keyframeAnimator(initialValue: MacBloomValues(), trigger: bloomCount) { content, value in
                            content.scaleEffect(value.scale).opacity(value.opacity)
                        } keyframes: { _ in
                            KeyframeTrack(\.scale) {
                                LinearKeyframe(0.82, duration: 0.01)
                                SpringKeyframe(1.16, duration: 0.48, spring: .smooth)
                            }
                            KeyframeTrack(\.opacity) {
                                LinearKeyframe(0, duration: 0.01)
                                CubicKeyframe(0.8, duration: 0.11)
                                CubicKeyframe(0, duration: 0.36)
                            }
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .onChange(of: isPressed) { wasPressed, pressed in
                if wasPressed && !pressed && !reduceMotion { bloomCount += 1 }
            }
    }
}

private extension View {
    func motionCard() -> some View { modifier(MacMotionCard()) }
}

struct MacContentView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked: Set<String> = []
    @State private var email = ""
    @State private var password = ""
    @State private var showAccount = false
    @State private var showNewExercise = false
    @State private var showYearCalendar = false
    @State private var newExerciseName = ""
    @State private var newExerciseSets = 3
    @State private var newExerciseReps = "10"
    @State private var newExerciseLast = ""
    @State private var pendingDeleteExercise: Int?
    private let weekOrder = [1, 2, 3, 4, 5, 6, 0]

    private var day: WorkoutDay { store.currentDay }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<Int?>(get: { store.state.activeDay }, set: { if let index = $0 { store.selectDay(index) } })) {
                ForEach(weekOrder, id: \.self) { index in
                    let item = store.visibleDays[index]
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.day).font(.headline)
                            Text(item.focus).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Label("\(item.progress)%", systemImage: item.isFinished ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(item.isFinished ? gymGreen : .secondary)
                    }.tag(index)
                        .accessibilityLabel("\(item.day), \(item.isFinished ? "finished" : "not finished"), \(item.progress)% complete")
                }
            }
            .navigationTitle("Dony's Lifts")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.syncLabel).font(.caption).foregroundStyle(.secondary)
                    Button(store.accountEmail ?? "Sign in to sync") { showAccount = true }
                        .buttonStyle(.link)
                    Button("Year calendar", systemImage: "calendar") { showYearCalendar = true }
                        .buttonStyle(.link)
                    if store.isViewingPastWeek {
                        Button("Current week") { store.selectCurrentWeek() }.buttonStyle(.link)
                    }
                }.padding()
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.day.uppercased()).font(.caption.weight(.bold)).foregroundStyle(gymGreen)
                            Text(day.title).font(.largeTitle.bold())
                            Text(day.focus).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(day.progress)%").font(.title.monospacedDigit().bold())
                            Text(day.isFinished ? "Finished" : "In progress").foregroundStyle(day.isFinished ? gymGreen : .secondary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 20).fill(.background)
                            .overlay { MacAmbientGlow().clipShape(RoundedRectangle(cornerRadius: 20)) }
                    }
                    .motionCard()
                    if store.isViewingPastWeek {
                        Text("Week of \(store.selectedWeekDate.formatted(.dateTime.month(.abbreviated).day())) · Past workout record (read-only)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(gymGreen)
                    }
                    if day.day == "Friday" {
                        Picker("Today's plan", selection: Binding(get: { day.selectedPlan ?? "Glutes & Isolation" }, set: { store.setPlan($0) })) {
                            Text("Glutes & Isolation").tag("Glutes & Isolation")
                            Text("Run + Glutes + Abs").tag("Run + Glutes + Abs")
                        }.pickerStyle(.segmented)
                            .disabled(store.isViewingPastWeek)
                    }
                    ForEach(day.visibleExerciseIndices, id: \.self) { index in
                        exerciseCard(index)
                            .motionCard()
                    }
                    Button("Add workout card", systemImage: "plus.circle.fill") { showNewExercise = true }
                        .buttonStyle(MacMotionButtonStyle())
                        .disabled(store.cloudConflict || store.isViewingPastWeek)
                    VStack(alignment: .leading) {
                        Text("Workout notes").font(.headline)
                        TextEditor(text: Binding(get: { day.notes }, set: { store.setNotes($0) }))
                            .disabled(store.isViewingPastWeek)
                            .frame(minHeight: 90).padding(8)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .motionCard()
                    Toggle("Mark day finished", isOn: Binding(get: { day.finished }, set: { store.setFinished($0) }))
                        .disabled(store.isViewingPastWeek)
                    if store.cloudConflict {
                        VStack(alignment: .leading) {
                            Text("Shared record changed elsewhere").font(.headline)
                            Text("Choose the copy to keep before recording more sets.").foregroundStyle(.secondary)
                            HStack {
                                Button("Use shared copy") { Task { await store.useSharedCopy() } }
                                Button("Keep this Mac copy") { Task { await store.keepIPhoneCopy() } }
                            }
                        }.padding().background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(28).frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle(day.day)
        }
        .tint(gymGreen)
        .sheet(isPresented: $showAccount) { accountSheet }
        .sheet(isPresented: $showNewExercise) { newExerciseSheet }
        .sheet(isPresented: $showYearCalendar) {
            MacYearCalendarView(history: store.state.history, days: store.state.days,
                                weekRecords: store.state.weekRecords) { date in store.selectWeek(containing: date) }
        }
        .confirmationDialog("Delete this workout card and its sets?", isPresented: Binding(get: { pendingDeleteExercise != nil }, set: { if !$0 { pendingDeleteExercise = nil } })) {
            Button("Delete workout card", role: .destructive) {
                if let index = pendingDeleteExercise { store.removeExercise(index) }
                pendingDeleteExercise = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteExercise = nil }
        }
        .alert("Dony's Lifts", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshFromCloud() } }
        }
        .task {
            while !Task.isCancelled {
                await store.refreshFromCloud()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private func exerciseCard(_ index: Int) -> some View {
        let item = day.exercises[index]
        let editable = !store.isViewingPastWeek && unlocked.contains(item.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.title2.bold())
                    Text("\(item.targetSets) sets · target \(item.targetReps)")
                        .font(.caption.weight(.bold)).foregroundStyle(gymGreen)
                    if let note = item.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button(editable ? "Lock" : "Unlock", systemImage: editable ? "lock.open" : "lock") {
                    if editable { unlocked.remove(item.id) } else { unlocked.insert(item.id) }
                }
                .buttonStyle(MacMotionButtonStyle())
                .disabled(store.isViewingPastWeek)
            }
            HStack {
                Text("Last:").foregroundStyle(.secondary)
                if editable {
                    TextField("Last", text: Binding(get: { item.last }, set: { store.setLast($0, exercise: index) }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 150)
                } else { Text(item.last).fontWeight(.semibold) }
            }
            ForEach(item.sets.indices, id: \.self) { setIndex in
                let entry = item.sets[setIndex]
                HStack(spacing: 12) {
                    Button { store.toggleSet(exercise: index, set: setIndex) } label: {
                        Image(systemName: entry.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(entry.done ? gymGreen : .secondary)
                    }.buttonStyle(MacMotionButtonStyle()).disabled(store.cloudConflict || store.isViewingPastWeek)
                    Text("Set \(setIndex + 1)").frame(width: 50, alignment: .leading)
                    if editable {
                        TextField("Load", text: Binding(get: { entry.weight }, set: { store.setWeight($0, exercise: index, set: setIndex) }))
                            .textFieldStyle(.roundedBorder)
                        TextField("Reps / time", text: Binding(get: { entry.reps }, set: { store.setReps($0, exercise: index, set: setIndex) }))
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { store.removeSet(exercise: index, set: setIndex) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                    } else {
                        Text(entry.weight.isEmpty ? "—" : entry.weight).frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.reps.isEmpty ? "—" : entry.reps).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.font(.body.monospacedDigit())
            }
            if editable {
                HStack {
                    Button("Add set", systemImage: "plus") { store.addSet(exercise: index) }
                        .buttonStyle(MacMotionButtonStyle())
                    Button("Delete workout card", systemImage: "trash", role: .destructive) { pendingDeleteExercise = index }
                }.disabled(store.cloudConflict)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator.opacity(0.25)))
    }

    private var accountSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Private sync").font(.title2.bold())
            if let account = store.accountEmail {
                Text("Signed in as \(account)")
                Text(store.syncLabel).foregroundStyle(.secondary)
                Button("Sign out") { store.signOut(); showAccount = false }
            } else {
                Text("Use the same email and password as your iPhone and website.")
                    .foregroundStyle(.secondary)
                TextField("Email", text: $email).textContentType(.emailAddress)
                SecureField("Password", text: $password)
                Button(store.accountBusy ? "Signing in…" : "Sign in") {
                    Task { await store.signIn(email: email, password: password, create: false); if store.accountEmail != nil { showAccount = false } }
                }.disabled(email.isEmpty || password.isEmpty || store.accountBusy)
            }
            Button("Close") { showAccount = false }
        }.padding(24).frame(width: 370)
    }

    private var newExerciseSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New workout card").font(.title2.bold())
            TextField("Exercise name", text: $newExerciseName)
            Stepper("\(newExerciseSets) sets", value: $newExerciseSets, in: 1...30)
            TextField("Target reps or time", text: $newExerciseReps)
            TextField("Last weight or load", text: $newExerciseLast)
            HStack {
                Button("Cancel") { showNewExercise = false }
                Button("Add") {
                    store.addExercise(name: newExerciseName, targetSets: newExerciseSets,
                                      targetReps: newExerciseReps, last: newExerciseLast, note: "")
                    newExerciseName = ""
                    newExerciseSets = 3
                    newExerciseReps = "10"
                    newExerciseLast = ""
                    showNewExercise = false
                }.disabled(newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 380)
    }
}

private struct MacYearCalendarView: View {
    let history: [String: WorkoutSnapshot]
    let days: [WorkoutDay]
    let weekRecords: [String: [WorkoutDay]]
    let onSelectWeek: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var selectedDate: Date? = Date()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    private func weekKey(_ date: Date) -> String {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let monday = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let parts = calendar.dateComponents([.year, .month, .day], from: monday)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func snapshot(_ date: Date) -> WorkoutSnapshot? {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let week = weekKey(date)
        let index = calendar.component(.weekday, from: date) - 1
        if let archived = weekRecords[week], archived.indices.contains(index) {
            let day = archived[index]
            return WorkoutSnapshot(progress: day.progress, finished: day.isFinished,
                                   completedSets: day.visibleSets.filter(\.done).count, totalSets: day.visibleSets.count)
        }
        if let item = history[key] { return item }
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        guard date <= Date(), let week = mondayCalendar.dateInterval(of: .weekOfYear, for: Date()),
              week.contains(date) else { return nil }
        guard days.indices.contains(index) else { return nil }
        let day = days[index]
        return WorkoutSnapshot(progress: day.progress, finished: day.isFinished,
                               completedSets: day.visibleSets.filter(\.done).count, totalSets: day.visibleSets.count)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(year) workouts").font(.title2.bold())
                Spacer()
                Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                Button { year += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(year >= Calendar.current.component(.year, from: Date()))
                Button("Done") {
                    if let selectedDate { onSelectWeek(selectedDate) }
                    dismiss()
                }
            }
            Text("Tap any date to choose its full Monday–Sunday week. The selected week is outlined; older records are read-only.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            if let selectedDate {
                let item = snapshot(selectedDate)
                Text("\(selectedDate.formatted(date: .abbreviated, time: .omitted)) · \(item.map { "\($0.progress)% · \($0.completedSets)/\($0.totalSets) sets" } ?? "No record")")
                    .font(.subheadline.weight(.semibold))
                Button("Show selected week") { onSelectWeek(selectedDate); dismiss() }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(1...12, id: \.self) { month in monthCard(month).id(month) }
                    }
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
        }.padding(20).frame(width: 960, height: 720)
    }

    private func monthCard(_ month: Int) -> some View {
        let calendar = Calendar.current
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let count = calendar.range(of: .day, in: .month, for: first)!.count
        let offset = (calendar.component(.weekday, from: first) + 5) % 7
        return VStack(alignment: .leading, spacing: 8) {
            Text(first.formatted(.dateTime.month(.wide))).font(.headline)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { index in
                    Text(["M", "T", "W", "T", "F", "S", "S"][index]).font(.caption2).frame(maxWidth: .infinity)
                }
                ForEach(0..<(offset + count), id: \.self) { position in
                    if position < offset { Color.clear.frame(height: 35) }
                    else {
                        let number = position - offset + 1
                        let date = calendar.date(from: DateComponents(year: year, month: month, day: number))!
                        let item = snapshot(date)
                        Button { selectedDate = date } label: {
                            VStack(spacing: 0) {
                                Text("\(number)").font(.system(size: 10, weight: .medium))
                                if item?.finished == true { Image(systemName: "checkmark").font(.system(size: 8, weight: .black)) }
                                if let item { Text("\(item.progress)%").font(.system(size: 8, weight: .bold)) }
                            }
                            .frame(maxWidth: .infinity).frame(height: 35)
                            .background(item?.finished == true ? gymGreen : Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                                weekKey(date) == (selectedDate.map(weekKey) ?? weekKey(Date()))
                                    ? (item?.finished == true ? .black : gymGreen) : .clear, lineWidth: 2.5))
                            .foregroundStyle(item?.finished == true ? .black : .primary)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
