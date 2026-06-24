//
//  WorkoutPlanView.swift
//  VerraOS
//

import SwiftUI
import UniformTypeIdentifiers

private enum EntryMode: String, CaseIterable, Identifiable {
    case builder = "Detailed"
    case freestyle = "Freestyle"
    var id: String { rawValue }
}

private enum WorkoutFocus: String, CaseIterable, Identifiable {
    case upper = "Upper Body"
    case lower = "Lower Body"
    case cardio = "Cardio"
    case assessment = "Assessment"
    var id: String { rawValue }
}

/// What the editor sheet is currently editing. Using a single `item`-driven
/// sheet guarantees the correct fields render on first present (no stale flags).
private enum EditorTarget: Identifiable {
    case addHeader
    case editHeader(WorkoutExercise)
    case editExercise(WorkoutExercise)

    var id: String {
        switch self {
        case .addHeader: return "add-header"
        case .editHeader(let ex): return "edit-header-\(ex.id)"
        case .editExercise(let ex): return "edit-exercise-\(ex.id)"
        }
    }

    var isHeader: Bool {
        switch self {
        case .addHeader, .editHeader: return true
        case .editExercise: return false
        }
    }

    var exercise: WorkoutExercise? {
        switch self {
        case .addHeader: return nil
        case .editHeader(let ex), .editExercise(let ex): return ex
        }
    }
}

/// A header and the exercise/rest items nested beneath it. A `header` of `nil`
/// represents the default top section for items added before any header.
private struct BuilderSection: Identifiable {
    let id: UUID
    let header: WorkoutExercise?
    var items: [WorkoutExercise]
}

struct WorkoutPlanView: View {
    let client: Client
    var onBack: () -> Void

    @Environment(ProfileStore.self) private var profile
    @Environment(\.isReadOnly) private var isReadOnly

    @State private var weekIndex = 0
    @State private var selectedDayIndex: Int
    @State private var mode: EntryMode = .builder
    @State private var exerciseSearch = ""
    @State private var searchSectionID: UUID?
    @State private var focus: WorkoutFocus = .upper
    @State private var freestyleNotes = ""
    @State private var builderNotes = ""
    @State private var editorTarget: EditorTarget?
    @State private var copyDayTarget = false
    @State private var copyWeekTarget = false
    @State private var draggingID: UUID?
    @State private var toast: ToastData?

    private static let defaultSectionID = UUID()

    init(client: Client, onBack: @escaping () -> Void) {
        self.client = client
        self.onBack = onBack
        // Open on today's day of the week (Mon-based index 0...6).
        let weekday = Calendar.current.component(.weekday, from: Date())
        _selectedDayIndex = State(initialValue: (weekday + 5) % 7)
    }

    private var week: [WorkoutDay] { profile.workoutWeek(for: client.id, week: weekIndex) }
    private var selectedDay: WorkoutDay? {
        week.indices.contains(selectedDayIndex) ? week[selectedDayIndex] : nil
    }

    private var sections: [BuilderSection] {
        guard let day = selectedDay else { return [] }
        var result: [BuilderSection] = []
        var current = BuilderSection(id: Self.defaultSectionID, header: nil, items: [])
        for ex in day.exercises {
            if ex.isHeader {
                if current.header != nil || !current.items.isEmpty { result.append(current) }
                current = BuilderSection(id: ex.id, header: ex, items: [])
            } else {
                current.items.append(ex)
            }
        }
        if current.header != nil || !current.items.isEmpty { result.append(current) }
        return result
    }

    private var filteredLibrary: [String] {
        let q = exerciseSearch.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return ProfileDemo.exerciseLibrary.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ProfileTopBar(
                title: "Workout Plan",
                subtitle: client.name.firstWord,
                trailing: isReadOnly ? nil : AnyView(weekMenu),
                onBack: onBack
            )
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.md) {
                    weekSelector
                    weekStrip
                    if !isReadOnly { modeToggle }
                    if mode == .builder || isReadOnly { builderSection } else { freestyleSection }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, 100)
            }
        }
        .background(Theme.Color.background)
        .toast($toast)
        .sheet(item: $editorTarget) { target in
            ExerciseEditorSheet(
                exercise: target.exercise,
                isHeader: target.isHeader,
                onSave: saveExercise,
                onDelete: target.exercise == nil ? nil : { deleteExercise(target.exercise!) }
            )
        }
        .confirmationDialog("Copy this day to…", isPresented: $copyDayTarget, titleVisibility: .visible) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                if index != selectedDayIndex {
                    Button(day.label) {
                        profile.copyDay(fromIndex: selectedDayIndex, toIndex: index, id: client.id, week: weekIndex)
                        toast = ToastData(message: "Copied to \(day.label)", icon: "doc.on.doc.fill")
                    }
                }
            }
        }
        .confirmationDialog("Copy this week to…", isPresented: $copyWeekTarget, titleVisibility: .visible) {
            ForEach(weekTargets, id: \.self) { target in
                Button("Week \(target + 1)") {
                    profile.copyWeek(from: weekIndex, to: target, id: client.id)
                    toast = ToastData(message: "Copied to Week \(target + 1)", icon: "doc.on.doc.fill")
                }
            }
            Button("New Week (Week \(weekCount + 1))") {
                let target = weekCount
                profile.copyWeek(from: weekIndex, to: target, id: client.id)
                toast = ToastData(message: "Copied to Week \(target + 1)", icon: "doc.on.doc.fill")
            }
        }
    }

    /// Existing weeks other than the current one (a brand-new week is offered separately).
    private var weekTargets: [Int] { (0..<weekCount).filter { $0 != weekIndex } }

    private var weekCount: Int { profile.workoutWeekCount(for: client.id) }

    private var weekMenu: some View {
        Menu {
            Button { copyDayTarget = true } label: {
                Label("Copy Day To…", systemImage: "doc.on.doc")
            }
            Button { copyWeekTarget = true } label: {
                Label("Copy Week To…", systemImage: "calendar")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.Color.ink)
                .frame(width: 42, height: 42)
                .background(Theme.Color.surface, in: Circle())
                .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    private var weekSelector: some View {
        HStack(spacing: 12) {
            Button { stepWeek(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(weekIndex == 0 ? Theme.Color.inkFaint : Theme.Color.ink)
                    .frame(width: 34, height: 34)
                    .background(Theme.Color.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(weekIndex == 0)

            Text("Week \(weekIndex + 1)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Color.ink)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())

            Button { stepWeek(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                    .frame(width: 34, height: 34)
                    .background(Theme.Color.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 7) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                let isSelected = index == selectedDayIndex
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selectedDayIndex = index }
                } label: {
                    VStack(spacing: 6) {
                        Text(day.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isSelected ? Theme.Color.accentInk : Theme.Color.inkMuted)
                        Circle()
                            .fill(day.isRest ? Theme.Color.inkFaint.opacity(0.5) : (isSelected ? Theme.Color.accentInk : Theme.Color.accent))
                            .frame(width: 7, height: 7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(isSelected ? Theme.Color.accent : Theme.Color.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Color.hairline, lineWidth: isSelected ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            ForEach(EntryMode.allCases) { item in
                let isActive = item == mode
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { mode = item }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(isActive ? Theme.Color.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.Color.surfaceMuted, in: Capsule())
    }

    // MARK: Builder

    private var builderSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            if sections.isEmpty {
                emptyState
            } else {
                ForEach(sections) { section in
                    sectionCard(section)
                }
            }
            if !isReadOnly {
                addHeaderButton
                sessionLogCard(notes: $builderNotes)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: draggingID)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
            Text(isReadOnly ? "No plan yet" : "Start with a header")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Color.ink)
            Text(isReadOnly ? "Your coach hasn't added a workout for this day yet." : "Create a section header first, then add exercises and rest days beneath it.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }

    private func sectionCard(_ section: BuilderSection) -> some View {
        VStack(spacing: 0) {
            if let header = section.header {
                headerRow(header)
            }
            if section.items.isEmpty {
                Text("No items yet — add an exercise or rest day below.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.Color.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 14)
                    .dropDestination(for: String.self) { ids, _ in handleDrop(ids, beforeID: nil, sectionHeaderID: section.header?.id) } isTargeted: { _ in }
            } else {
                ForEach(section.items) { item in
                    itemRow(item, isLast: item.id == section.items.last?.id)
                }
            }
            if let header = section.header, !isReadOnly {
                if searchSectionID == header.id { inlineSearchCard }
                sectionActions(headerID: header.id)
            }
        }
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }

    private func sectionActions(headerID: UUID) -> some View {
        HStack(spacing: 8) {
            actionButton(title: "Add Exercise", icon: "plus") { startAddExercise(headerID: headerID) }
            actionButton(title: "Rest Day", icon: "moon.zzz") { addRestDay(underHeaderID: headerID) }
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Color.hairline).frame(height: 1) }
    }

    private var addHeaderButton: some View {
        Button { editorTarget = .addHeader } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                Text("Add Header").font(.system(size: 14.5, weight: .bold))
            }
            .foregroundStyle(Theme.Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(Theme.Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }

    private func headerRow(_ header: WorkoutExercise) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Color.accentInk.opacity(0.6))
            Text(header.name.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.Color.accentInk)
            Spacer()
            if !isReadOnly {
                Button {
                    editorTarget = .editHeader(header)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk.opacity(0.7))
                }
                .buttonStyle(.plain)
                Button { deleteExercise(header) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.Color.accent.opacity(0.55))
        .opacity(draggingID == header.id ? 0.4 : 1)
        .contentShape(Rectangle())
        .modifier(reorderModifier(id: header.id, name: header.name, beforeID: header.id, sectionHeaderID: nil))
    }

    /// Builds a reorder (drag + drop) modifier for a builder row, disabled in
    /// read-only mode so clients can view but not rearrange the plan.
    private func reorderModifier(id: UUID, name: String, beforeID: UUID, sectionHeaderID: UUID?) -> ReorderModifier {
        ReorderModifier(
            enabled: !isReadOnly,
            id: id,
            name: name,
            onDrop: { ids in handleDrop(ids, beforeID: beforeID, sectionHeaderID: sectionHeaderID) }
        )
    }

    private func itemRow(_ item: WorkoutExercise, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            BuilderItemRow(
                item: item,
                isReadOnly: isReadOnly,
                onCommit: { sets, reps in updateSetsReps(item, sets: sets, reps: reps) },
                onEdit: {
                    editorTarget = .editExercise(item)
                },
                onDelete: { deleteExercise(item) }
            )
            .opacity(draggingID == item.id ? 0.4 : 1)
            .modifier(reorderModifier(id: item.id, name: item.name, beforeID: item.id, sectionHeaderID: nil))
            if !isLast {
                Rectangle().fill(Theme.Color.hairline).frame(height: 1).padding(.leading, 14)
            }
        }
    }

    private func dragPreview(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.Color.ink)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.Color.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.Color.accent, lineWidth: 1.5))
    }

    // MARK: Inline search

    private var inlineSearchCard: some View {
        SectionCard(title: "Add Exercise", icon: "magnifyingglass") {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkFaint)
                    TextField("Type an exercise name", text: $exerciseSearch)
                        .font(.system(size: 14.5, weight: .medium))
                        .autocorrectionDisabled()
                    Button {
                        exerciseSearch = ""
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { searchSectionID = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.Color.inkFaint)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(Theme.Color.surfaceMuted, in: Capsule())

                if exerciseSearch.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Start typing to search the library.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredLibrary.prefix(8).enumerated()), id: \.offset) { index, name in
                            searchResultRow(name)
                            if index < min(filteredLibrary.count, 8) - 1 {
                                Rectangle().fill(Theme.Color.hairline).frame(height: 1)
                            }
                        }
                        if filteredLibrary.isEmpty {
                            searchResultRow(exerciseSearch.trimmingCharacters(in: .whitespaces), isCreate: true)
                        }
                    }
                }
            }
        }
    }

    private func searchResultRow(_ name: String, isCreate: Bool = false) -> some View {
        Button {
            addExercise(named: name)
        } label: {
            HStack {
                Text(isCreate ? "Create “\(name)”" : name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: Action buttons

    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(title).font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Theme.Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
    }

    // MARK: Session log

    private func sessionLogCard(notes: Binding<String>) -> some View {
        SectionCard(title: "Session Log", icon: "square.and.pencil") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Post-workout notes (e.g. focused on squat form, knee flare-up)…", text: notes, axis: .vertical)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(5...12)
                    .padding(Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                Button {
                    toast = ToastData(message: "Session logged", icon: "checkmark.circle.fill")
                    notes.wrappedValue = ""
                } label: {
                    Text("Save Log")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(notes.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(notes.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
        }
    }

    // MARK: Freestyle

    private var freestyleSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            SectionCard(title: "Focus", icon: "scope") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(WorkoutFocus.allCases) { item in
                        let isActive = item == focus
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { focus = item }
                        } label: {
                            Text(item.rawValue)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(isActive ? Theme.Color.accent : Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            sessionLogCard(notes: $freestyleNotes)
        }
    }

    // MARK: Actions

    private func startAddExercise(headerID: UUID) {
        exerciseSearch = ""
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            searchSectionID = (searchSectionID == headerID) ? nil : headerID
        }
    }

    private func addExercise(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        insertItem(WorkoutExercise(name: trimmed), underHeaderID: searchSectionID)
        exerciseSearch = ""
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { searchSectionID = nil }
        toast = ToastData(message: "Added \(trimmed)", icon: "checkmark.circle.fill")
    }

    private func addRestDay(underHeaderID headerID: UUID) {
        insertItem(WorkoutExercise(name: "Rest Day", kind: .rest), underHeaderID: headerID)
        toast = ToastData(message: "Rest day added", icon: "moon.zzz.fill")
    }

    /// Inserts an item at the end of the section owned by `headerID` (just before
    /// the next header), or at the end of the day when no header is given.
    private func insertItem(_ item: WorkoutExercise, underHeaderID headerID: UUID?) {
        mutateSelectedDay { day in
            var arr = day.exercises
            if let headerID, let hi = arr.firstIndex(where: { $0.id == headerID }) {
                var insertAt = arr.count
                if hi + 1 < arr.count {
                    for j in (hi + 1)..<arr.count where arr[j].isHeader {
                        insertAt = j
                        break
                    }
                }
                arr.insert(item, at: insertAt)
            } else {
                arr.append(item)
            }
            day.exercises = arr
            if day.focus == nil { day.focus = "Workout" }
        }
    }

    private func stepWeek(_ delta: Int) {
        let target = max(0, weekIndex + delta)
        guard target != weekIndex else { return }
        // Stepping forward past the last week generates a new blank week.
        if delta > 0 { profile.ensureWorkoutWeek(client.id, week: target) }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { weekIndex = target }
    }

    private func saveExercise(_ result: WorkoutExercise) {
        var wasNew = false
        mutateSelectedDay { day in
            if let idx = day.exercises.firstIndex(where: { $0.id == result.id }) {
                day.exercises[idx] = result
            } else {
                day.exercises.append(result)
                wasNew = true
                if day.focus == nil { day.focus = "Workout" }
            }
        }
        toast = ToastData(message: wasNew ? "Added \(result.name)" : "Saved", icon: "checkmark.circle.fill")
    }

    private func updateSetsReps(_ ex: WorkoutExercise, sets: Int?, reps: Int?) {
        mutateSelectedDay { day in
            guard let i = day.exercises.firstIndex(where: { $0.id == ex.id }) else { return }
            day.exercises[i].sets = sets
            day.exercises[i].reps = reps
        }
    }

    private func deleteExercise(_ ex: WorkoutExercise) {
        mutateSelectedDay { day in
            day.exercises.removeAll { $0.id == ex.id }
        }
        toast = ToastData(message: "Removed", icon: "trash.fill")
    }

    /// Reorders the dragged item to before `beforeID`, or to the end of the
    /// section identified by `sectionHeaderID` when dropped on an empty zone.
    private func handleDrop(_ ids: [String], beforeID: UUID?, sectionHeaderID: UUID?) -> Bool {
        guard let raw = ids.first, let movingID = UUID(uuidString: raw) else { return false }
        var didMove = false
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            mutateSelectedDay { day in
                var arr = day.exercises
                guard let from = arr.firstIndex(where: { $0.id == movingID }) else { return }
                let item = arr.remove(at: from)
                if let beforeID, let t = arr.firstIndex(where: { $0.id == beforeID }) {
                    arr.insert(item, at: t)
                } else if let sectionHeaderID, let h = arr.firstIndex(where: { $0.id == sectionHeaderID }) {
                    // Insert right after the section header (empty section drop).
                    arr.insert(item, at: h + 1)
                } else {
                    arr.append(item)
                }
                day.exercises = arr
                didMove = true
            }
        }
        draggingID = nil
        return didMove
    }

    /// Mutates the currently selected day by index, so it stays correct even when
    /// the store regenerates day identifiers between reads.
    private func mutateSelectedDay(_ transform: (inout WorkoutDay) -> Void) {
        let index = selectedDayIndex
        profile.mutateWeek(client.id, week: weekIndex) { days in
            guard days.indices.contains(index) else { return }
            transform(&days[index])
        }
    }
}

// MARK: - Builder item row (exercise or rest day) with inline sets/reps

private struct BuilderItemRow: View {
    let item: WorkoutExercise
    let isReadOnly: Bool
    var onCommit: (Int?, Int?) -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var setsText: String
    @State private var repsText: String

    init(item: WorkoutExercise, isReadOnly: Bool = false, onCommit: @escaping (Int?, Int?) -> Void, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.item = item
        self.isReadOnly = isReadOnly
        self.onCommit = onCommit
        self.onEdit = onEdit
        self.onDelete = onDelete
        _setsText = State(initialValue: item.sets.map(String.init) ?? "")
        _repsText = State(initialValue: item.reps.map(String.init) ?? "")
    }

    var body: some View {
        if item.isRestItem {
            restRow
        } else {
            exerciseRow
        }
    }

    private var restRow: some View {
        HStack(spacing: 10) {
            if !isReadOnly {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
            Text("Rest Day")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
            Spacer()
            if !isReadOnly { deleteButton }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var exerciseRow: some View {
        HStack(spacing: 10) {
            if isReadOnly {
                Text(item.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 6)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
            } else {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Color.inkFaint)
                Button(action: onEdit) {
                    Text(item.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 6)
                field(placeholder: "Sets", text: $setsText)
                Text("×")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Color.inkFaint)
                field(placeholder: "Reps", text: $repsText)
                deleteButton
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func field(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .frame(width: 46)
            .padding(.vertical, 7)
            .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: text.wrappedValue) { _, _ in commit() }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Color.danger.opacity(0.8))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private func commit() {
        onCommit(Int(setsText), Int(repsText))
    }
}

// MARK: - Exercise editor sheet

private struct ExerciseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: WorkoutExercise?
    let isHeader: Bool
    var onSave: (WorkoutExercise) -> Void
    var onDelete: (() -> Void)?

    @State private var name: String
    @State private var setsText: String
    @State private var repsText: String

    init(exercise: WorkoutExercise?, isHeader: Bool, onSave: @escaping (WorkoutExercise) -> Void, onDelete: (() -> Void)?) {
        self.exercise = exercise
        self.isHeader = isHeader
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: exercise?.name ?? "")
        _setsText = State(initialValue: exercise?.sets.map(String.init) ?? "")
        _repsText = State(initialValue: exercise?.reps.map(String.init) ?? "")
    }

    private var title: String {
        if isHeader { return exercise == nil ? "Add Header" : "Edit Header" }
        return exercise == nil ? "Add Exercise" : "Edit Exercise"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                fieldLabel(isHeader ? "Section name" : "Exercise name")
                TextField(isHeader ? "e.g. Warm-up" : "e.g. Bench Press", text: $name)
                    .font(.system(size: 18, weight: .semibold))
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))

                if !isHeader {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Sets (optional)")
                            TextField("—", text: $setsText)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .keyboardType(.numberPad)
                                .padding(Theme.Spacing.sm)
                                .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Reps (optional)")
                            TextField("—", text: $repsText)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .keyboardType(.numberPad)
                                .padding(Theme.Spacing.sm)
                                .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        }
                    }
                }

                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text(isHeader ? "Delete Header" : "Delete Exercise")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Color.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.Color.danger.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(isHeader ? 260 : 360)])
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Theme.Color.inkFaint)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let result = WorkoutExercise(
            id: exercise?.id ?? UUID(),
            name: trimmed,
            sets: isHeader ? nil : Int(setsText),
            reps: isHeader ? nil : Int(repsText),
            kind: isHeader ? .header : .exercise
        )
        onSave(result)
        dismiss()
    }
}

// MARK: - Reorder modifier

/// Adds drag-and-drop reordering to a builder row, or passes the row through
/// untouched when disabled (read-only client viewing).
private struct ReorderModifier: ViewModifier {
    let enabled: Bool
    let id: UUID
    let name: String
    let onDrop: ([String]) -> Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .draggable(id.uuidString) {
                    Text(name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.Color.surface, in: Capsule())
                        .overlay(Capsule().stroke(Theme.Color.accent, lineWidth: 1.5))
                }
                .dropDestination(for: String.self) { ids, _ in onDrop(ids) } isTargeted: { _ in }
        } else {
            content
        }
    }
}
