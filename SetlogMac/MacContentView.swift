import SwiftUI

private let gymGreen = Color(red: 0.49, green: 0.77, blue: 0.12)

struct MacContentView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked: Set<String> = []
    @State private var email = ""
    @State private var password = ""
    @State private var showAccount = false

    private var day: WorkoutDay { store.currentDay }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<Int?>(get: { store.state.activeDay }, set: { if let index = $0 { store.selectDay(index) } })) {
                ForEach(store.state.days.indices, id: \.self) { index in
                    let item = store.state.days[index]
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.day).font(.headline)
                            Text(item.focus).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("\(item.progress)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(item.isFinished ? gymGreen : .secondary)
                    }.tag(index)
                }
            }
            .navigationTitle("Dony's Lifts")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.syncLabel).font(.caption).foregroundStyle(.secondary)
                    Button(store.accountEmail ?? "Sign in to sync") { showAccount = true }
                        .buttonStyle(.link)
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
                    if day.day == "Friday" {
                        Picker("Today's plan", selection: Binding(get: { day.selectedPlan ?? "Glutes & Isolation" }, set: { store.setPlan($0) })) {
                            Text("Glutes & Isolation").tag("Glutes & Isolation")
                            Text("Run + Glutes + Abs").tag("Run + Glutes + Abs")
                        }.pickerStyle(.segmented)
                    }
                    ForEach(day.visibleExerciseIndices, id: \.self) { index in
                        exerciseCard(index)
                    }
                    VStack(alignment: .leading) {
                        Text("Workout notes").font(.headline)
                        TextEditor(text: Binding(get: { day.notes }, set: { store.setNotes($0) }))
                            .frame(minHeight: 90).padding(8)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Toggle("Mark day finished", isOn: Binding(get: { day.finished }, set: { store.setFinished($0) }))
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
        let editable = unlocked.contains(item.id)
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
                    }.buttonStyle(.plain).disabled(store.cloudConflict)
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
                Button("Add set", systemImage: "plus") { store.addSet(exercise: index) }
                    .disabled(store.cloudConflict)
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
}
