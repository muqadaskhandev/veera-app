//
//  WorkoutPlanView.swift
//  VerraOS
//

import SwiftUI
import UniformTypeIdentifiers
import AVKit
import PhotosUI

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
    @State private var sessionNotes = ""
    @State private var sessionNotesKey = ""
    @State private var freestyleName = ""
    @State private var freestyleSetsText = ""
    @State private var freestyleRepsText = ""
    @State private var freestyleWeightText = ""
    @State private var editorTarget: EditorTarget?
    @State private var copyDayTarget = false
    @State private var copyWeekTarget = false
    @State private var draggingID: UUID?
    @State private var toast: ToastData?
    @State private var libraryResults: [LibraryExercise] = []
    @State private var selectedCategory: ExerciseCategoryFilter = .all
    @State private var previewExercise: LibraryExercise?
    @State private var searchTask: Task<Void, Never>?
    @State private var didResolveClientWeek = false
    @State private var progressExercise: WorkoutExercise?

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

    /// Uniquely identifies the currently viewed day so session notes reload
    /// whenever the user switches week or day, instead of leaking across days.
    private var dayKey: String { "\(weekIndex)-\(selectedDayIndex)" }

    /// Ad-hoc exercises logged from the Freestyle tab (tagged so they stay
    /// separate from the Detailed builder's structured sections).
    private var freestyleItems: [WorkoutExercise] {
        selectedDay?.exercises.filter { $0.kind == .exercise && $0.category == "Freestyle" } ?? []
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

    private var trimmedSearch: String {
        exerciseSearch.trimmingCharacters(in: .whitespaces)
    }

    private var visibleLibraryResults: [LibraryExercise] {
        Array(libraryResults.prefix(12))
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
                    if let focus = selectedDay?.focus, !focus.isEmpty {
                        dayFocusBanner(focus)
                    }
                    if !isReadOnly { modeToggle }
                    if mode == .builder || isReadOnly { builderSection } else { freestyleSection }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .frame(maxHeight: .infinity)
            .tabScrollContent()
            .formKeyboardBehavior()
        }
        .background(Theme.Color.background)
        .toast($toast)
        .task {
            await profile.refreshModule(.workout, for: client, week: weekIndex)
            if isReadOnly, !didResolveClientWeek {
                await resolveClientWeekToPlan()
                didResolveClientWeek = true
            }
        }
        .task(id: weekIndex) {
            await profile.refreshModule(.workout, for: client, week: weekIndex)
        }
        .task(id: dayKey) {
            syncSessionNotesIfNeeded()
        }
        .onChange(of: exerciseSearch) { _, _ in
            scheduleLibraryRefresh()
        }
        .onChange(of: selectedCategory) { _, _ in
            scheduleLibraryRefresh()
        }
        .onChange(of: searchSectionID) { _, sectionID in
            if sectionID != nil {
                scheduleLibraryRefresh()
            }
        }
        .sheet(item: $progressExercise) { exercise in
            ExerciseProgressSheet(client: client, exerciseName: exercise.name, exerciseID: exercise.exerciseID)
        }
        .sheet(item: $previewExercise) { exercise in
            ExerciseDetailSheet(exercise: exercise, isEditable: !isReadOnly) { updated in
                if let index = libraryResults.firstIndex(where: { $0.id == updated.id }) {
                    libraryResults[index] = updated
                }
            }
        }
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
                    .foregroundStyle(
                        isReadOnly && weekIndex >= weekCount - 1
                            ? Theme.Color.inkFaint
                            : Theme.Color.ink
                    )
                    .frame(width: 34, height: 34)
                    .background(Theme.Color.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly && weekIndex >= weekCount - 1)
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 7) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                let isSelected = index == selectedDayIndex
                let exerciseCount = day.exercises.filter { $0.kind == .exercise }.count
                let hasNotes = !(day.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                let hasPlan = exerciseCount > 0 || day.exercises.contains(where: { $0.kind == .rest }) || hasNotes
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selectedDayIndex = index }
                } label: {
                    VStack(spacing: 5) {
                        Text(day.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isSelected ? Theme.Color.accentInk : Theme.Color.inkMuted)
                        if exerciseCount > 0 {
                            Text("\(exerciseCount)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(isSelected ? Theme.Color.accentInk : Theme.Color.ink)
                        } else if hasPlan {
                            Image(systemName: hasNotes ? "square.and.pencil" : "moon.zzz.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(isSelected ? Theme.Color.accentInk : Theme.Color.inkMuted)
                        } else {
                            Circle()
                                .fill(Theme.Color.inkFaint.opacity(0.45))
                                .frame(width: 7, height: 7)
                        }
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
                saveDetailedButton
                sessionLogCard
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: draggingID)
    }

    private var emptyState: some View {
        let isRest = selectedDay?.isRest == true && !(selectedDay?.exercises.isEmpty ?? true)
        return VStack(spacing: 10) {
            Image(systemName: isRest ? "moon.zzz.fill" : "text.alignleft")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
            Text(isReadOnly ? (isRest ? "Rest day" : "No plan yet") : "Start with a header")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Color.ink)
            Text(
                isReadOnly
                    ? (isRest
                        ? "No training programmed for this day — try another day or week."
                        : "Your coach hasn't added a workout for this day yet. Check other days or weeks above.")
                    : "Create a section header first, then add exercises and rest days beneath it."
            )
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

    private func dayFocusBanner(_ focus: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Color.accentInk)
            Text(focus)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.Color.accent.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
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
                onCommit: { sets, reps, weightKg in updateSetsReps(item, sets: sets, reps: reps, weightKg: weightKg) },
                onEdit: {
                    editorTarget = .editExercise(item)
                },
                onDelete: { deleteExercise(item) },
                onShowProgress: item.isRestItem ? nil : { progressExercise = item }
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
        SectionCard(title: "Exercise Library", icon: "magnifyingglass") {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkFaint)
                    TextField("Search exercises", text: $exerciseSearch)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.Color.ink)
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

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ExerciseCategoryFilter.allCases) { filter in
                            ExerciseCategoryChip(
                                title: filter.label,
                                isSelected: selectedCategory == filter
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    selectedCategory = filter
                                }
                            }
                        }
                    }
                }

                if visibleLibraryResults.isEmpty {
                    if trimmedSearch.isEmpty {
                        Text("Browse the library or search by name.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Color.inkFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        searchResultRow(name: trimmedSearch, isCreate: true)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleLibraryResults.enumerated()), id: \.element.id) { index, exercise in
                            libraryResultRow(exercise)
                            if index < visibleLibraryResults.count - 1 {
                                Rectangle().fill(Theme.Color.hairline).frame(height: 1)
                            }
                        }
                        if !trimmedSearch.isEmpty,
                           !visibleLibraryResults.contains(where: { $0.name.caseInsensitiveCompare(trimmedSearch) == .orderedSame }) {
                            Rectangle().fill(Theme.Color.hairline).frame(height: 1)
                            searchResultRow(name: trimmedSearch, isCreate: true)
                        }
                    }
                }
            }
        }
    }

    private func libraryResultRow(_ exercise: LibraryExercise) -> some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(url: exercise.imageURL)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                Text(exercise.categoryLabel)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Theme.Color.inkMuted)
            }

            Spacer(minLength: 0)

            Button {
                previewExercise = exercise
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            .buttonStyle(.plain)

            Button {
                addExercise(from: exercise)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
    }

    private func searchResultRow(name: String, isCreate: Bool = false) -> some View {
        Button {
            if isCreate {
                addCustomExercise(named: name)
            }
        } label: {
            HStack {
                Text(isCreate ? "Create custom “\(name)”" : name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                Spacer()
                Image(systemName: isCreate ? "square.and.pencil" : "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func scheduleLibraryRefresh() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await refreshLibrary()
        }
    }

    @MainActor
    private func refreshLibrary() async {
        guard let token = AuthStore.accessToken else {
            libraryResults = []
            return
        }
        let query = trimmedSearch.isEmpty ? nil : trimmedSearch
        if let exercises = try? await VerraAPI.fetchExercises(
            query: query,
            category: selectedCategory.apiValue,
            accessToken: token
        ) {
            libraryResults = exercises.map(LibraryExercise.init)
        }
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

    /// Reloads the local notes draft from the current day whenever the user
    /// navigates to a different day/week, so edits never leak across days.
    private func syncSessionNotesIfNeeded() {
        guard sessionNotesKey != dayKey else { return }
        sessionNotes = selectedDay?.notes ?? ""
        sessionNotesKey = dayKey
    }

    private func saveSessionNotes() {
        let trimmed = sessionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateSelectedDay { day in day.notes = trimmed.isEmpty ? nil : trimmed }
        sessionNotes = trimmed
        sessionNotesKey = dayKey
        Task { @MainActor in
            await profile.flushWorkoutPersist(clientID: client.id, week: weekIndex)
            // Re-bind from store so a server echo can't leave the field blank.
            sessionNotes = selectedDay?.notes ?? trimmed
            sessionNotesKey = dayKey
        }
        toast = ToastData(message: "Session logged", icon: "checkmark.circle.fill")
    }

    private var sessionLogCard: some View {
        SectionCard(title: "Session Log", icon: "square.and.pencil") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Post-workout notes (e.g. focused on squat form, knee flare-up)…", text: $sessionNotes, axis: .vertical)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(5...12)
                    .padding(Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                if let saved = selectedDay?.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !saved.isEmpty,
                   saved == sessionNotes.trimmingCharacters(in: .whitespacesAndNewlines) {
                    Text("Saved to this day — visible in the week strip.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                Button(action: saveSessionNotes) {
                    Text("Save Log")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(sessionNotes.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(sessionNotes.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
        }
    }

    private var saveDetailedButton: some View {
        VStack(spacing: 8) {
            Button {
                saveDetailedWorkout()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15, weight: .bold))
                    Text("Save Workout").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Theme.Color.accentInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save Workout")

            Text("Saves this day's plan and session notes to the weekly view.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
                .frame(maxWidth: .infinity, alignment: .center)
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

            SectionCard(title: "Logged Exercises", icon: "list.bullet") {
                VStack(spacing: 10) {
                    if freestyleItems.isEmpty {
                        Text("No exercises logged yet for this day.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Color.inkFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(freestyleItems.enumerated()), id: \.element.id) { index, item in
                                freestyleItemRow(item)
                                if index < freestyleItems.count - 1 {
                                    Rectangle().fill(Theme.Color.hairline).frame(height: 1)
                                }
                            }
                        }
                    }
                    freestyleAddRow
                }
            }

            saveFreestyleButton
            sessionLogCard
        }
    }

    private func freestyleItemRow(_ item: WorkoutExercise) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.inkMuted)
                    }
                    if let weightKg = item.weightKg {
                        Text(WorkoutPlanView.weightLabel(weightKg))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.accentInk)
                    }
                }
            }
            Spacer(minLength: 6)
            Button { progressExercise = item } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
            }
            .buttonStyle(.plain)
            Button { deleteExercise(item) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.danger.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private var freestyleAddRow: some View {
        VStack(spacing: 8) {
            TextField("Exercise name", text: $freestyleName)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Theme.Color.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))

            HStack(spacing: 8) {
                miniField(placeholder: "Sets", text: $freestyleSetsText)
                miniField(placeholder: "Reps", text: $freestyleRepsText)
                miniField(placeholder: "Weight (kg)", text: $freestyleWeightText, isDecimal: true)
            }

            Button(action: addFreestyleExercise) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                    Text("Add Exercise").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Theme.Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            .buttonStyle(.plain)
            .disabled(freestyleName.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(freestyleName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
    }

    private func miniField(placeholder: String, text: Binding<String>, isDecimal: Bool = false) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.Color.ink)
            .multilineTextAlignment(.center)
            .keyboardType(isDecimal ? .decimalPad : .numberPad)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 8))
    }

    private var saveFreestyleButton: some View {
        VStack(spacing: 8) {
            Button {
                saveFreestyleWorkout()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15, weight: .bold))
                    Text("Save Freestyle Workout").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Theme.Color.accentInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save Freestyle Workout")

            Text("Saves logged exercises and session notes to this day.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private static func weightLabel(_ kg: Double) -> String {
        let trimmed = kg.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(kg)) : String(format: "%.1f", kg)
        return "\(trimmed) kg"
    }

    // MARK: Actions

    private func startAddExercise(headerID: UUID) {
        exerciseSearch = ""
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            searchSectionID = (searchSectionID == headerID) ? nil : headerID
        }
    }

    private func addExercise(from exercise: LibraryExercise) {
        insertItem(
            WorkoutExercise(
                exerciseID: exercise.id,
                name: exercise.name,
                category: exercise.category
            ),
            underHeaderID: searchSectionID
        )
        exerciseSearch = ""
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { searchSectionID = nil }
        toast = ToastData(message: "Added \(exercise.name)", icon: "checkmark.circle.fill")
    }

    private func addCustomExercise(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task { @MainActor in
            var exerciseID: UUID?
            if let token = AuthStore.accessToken,
               let created = try? await VerraAPI.createExercise(
                    name: trimmed,
                    category: "Custom",
                    description: nil,
                    accessToken: token
               ) {
                exerciseID = created.id
            }
            insertItem(
                WorkoutExercise(exerciseID: exerciseID, name: trimmed, category: "Custom"),
                underHeaderID: searchSectionID
            )
            exerciseSearch = ""
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { searchSectionID = nil }
            toast = ToastData(message: "Added \(trimmed)", icon: "checkmark.circle.fill")
        }
    }

    private func addFreestyleExercise() {
        let trimmed = freestyleName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        insertItem(
            WorkoutExercise(
                name: trimmed,
                sets: Int(freestyleSetsText),
                reps: Int(freestyleRepsText),
                category: "Freestyle",
                kind: .exercise,
                weightKg: Double(freestyleWeightText)
            ),
            underHeaderID: nil
        )
        freestyleName = ""
        freestyleSetsText = ""
        freestyleRepsText = ""
        freestyleWeightText = ""
        Task { await profile.flushWorkoutPersist(clientID: client.id, week: weekIndex) }
        toast = ToastData(message: "Added \(trimmed)", icon: "checkmark.circle.fill")
    }

    private func saveFreestyleWorkout() {
        if !freestyleName.trimmingCharacters(in: .whitespaces).isEmpty {
            addFreestyleExercise()
        }
        let trimmedNotes = sessionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateSelectedDay { day in
            day.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            day.focus = focus.rawValue
        }
        sessionNotes = trimmedNotes
        sessionNotesKey = dayKey
        Task { @MainActor in
            await profile.flushWorkoutPersist(clientID: client.id, week: weekIndex)
            sessionNotes = selectedDay?.notes ?? trimmedNotes
            sessionNotesKey = dayKey
        }
        toast = ToastData(message: "Freestyle workout saved", icon: "checkmark.circle.fill")
    }

    private func saveDetailedWorkout() {
        let trimmedNotes = sessionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateSelectedDay { day in
            day.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            if day.focus == nil || day.focus?.isEmpty == true, !day.exercises.isEmpty {
                day.focus = "Workout"
            }
        }
        sessionNotes = trimmedNotes
        sessionNotesKey = dayKey
        Task { @MainActor in
            await profile.flushWorkoutPersist(clientID: client.id, week: weekIndex)
            sessionNotes = selectedDay?.notes ?? trimmedNotes
            sessionNotesKey = dayKey
        }
        let count = selectedDay?.exercises.filter { $0.kind == .exercise }.count ?? 0
        toast = ToastData(
            message: count > 0 ? "Workout saved (\(count) exercises)" : "Workout saved",
            icon: "checkmark.circle.fill"
        )
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
            if day.focus == nil || day.focus?.isEmpty == true {
                day.focus = mode == .freestyle ? focus.rawValue : "Workout"
            }
        }
    }

    private func stepWeek(_ delta: Int) {
        let target: Int
        if isReadOnly {
            target = min(max(0, weekIndex + delta), max(0, weekCount - 1))
        } else {
            target = max(0, weekIndex + delta)
            // Stepping forward past the last week generates a new blank week (trainer only).
            if delta > 0 { profile.ensureWorkoutWeek(client.id, week: target) }
        }
        guard target != weekIndex else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { weekIndex = target }
    }

    /// Clients often land on Week 1 / today while the coach edited a later week.
    /// Prefetch weeks and jump to the one that actually has today's training.
    @MainActor
    private func resolveClientWeekToPlan() async {
        let initialCount = profile.workoutWeekCount(for: client.id)
        for week in 0..<initialCount {
            await profile.refreshModule(.workout, for: client, week: week)
        }
        let count = profile.workoutWeekCount(for: client.id)
        for week in initialCount..<count {
            await profile.refreshModule(.workout, for: client, week: week)
        }

        let day = selectedDayIndex
        var bestWithTraining: Int?
        var bestWithAny: Int?
        for week in (0..<profile.workoutWeekCount(for: client.id)).reversed() {
            let days = profile.workoutWeek(for: client.id, week: week)
            guard days.indices.contains(day) else { continue }
            let exercises = days[day].exercises
            if exercises.contains(where: { $0.kind == .exercise }) {
                bestWithTraining = week
                break
            }
            if bestWithAny == nil, !exercises.isEmpty {
                bestWithAny = week
            }
        }

        let target = bestWithTraining ?? bestWithAny ?? weekIndex
        if target != weekIndex {
            weekIndex = target
        }
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

    private func updateSetsReps(_ ex: WorkoutExercise, sets: Int?, reps: Int?, weightKg: Double?) {
        mutateSelectedDay { day in
            guard let i = day.exercises.firstIndex(where: { $0.id == ex.id }) else { return }
            day.exercises[i].sets = sets
            day.exercises[i].reps = reps
            day.exercises[i].weightKg = weightKg
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
    var onCommit: (Int?, Int?, Double?) -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onShowProgress: (() -> Void)?

    @State private var setsText: String
    @State private var repsText: String
    @State private var weightText: String

    init(
        item: WorkoutExercise,
        isReadOnly: Bool = false,
        onCommit: @escaping (Int?, Int?, Double?) -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onShowProgress: (() -> Void)? = nil
    ) {
        self.item = item
        self.isReadOnly = isReadOnly
        self.onCommit = onCommit
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onShowProgress = onShowProgress
        _setsText = State(initialValue: item.sets.map(String.init) ?? "")
        _repsText = State(initialValue: item.reps.map(String.init) ?? "")
        _weightText = State(initialValue: item.weightKg.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0) } ?? "")
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                    if let category = item.category {
                        Text(category.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Theme.Color.inkMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 6)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
                // Clients can log the weight they actually used, even though
                // the rest of the plan stays read-only.
                field(placeholder: "kg", text: $weightText, keyboard: .decimalPad, width: 52)
                if let onShowProgress {
                    Button(action: onShowProgress) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Color.accent)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Color.inkFaint)
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.name)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(Theme.Color.ink)
                                .lineLimit(1)
                            if item.isLinkedToLibrary {
                                Image(systemName: "link")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.Color.accent)
                            }
                        }
                        if let category = item.category {
                            Text(category.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(Theme.Color.inkMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 6)
                if let onShowProgress {
                    Button(action: onShowProgress) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Color.accent)
                    }
                    .buttonStyle(.plain)
                }
                field(placeholder: "Sets", text: $setsText, keyboard: .numberPad)
                Text("×")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Color.inkFaint)
                field(placeholder: "Reps", text: $repsText, keyboard: .numberPad)
                field(placeholder: "kg", text: $weightText, keyboard: .decimalPad, width: 52)
                deleteButton
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func field(placeholder: String, text: Binding<String>, keyboard: UIKeyboardType, width: CGFloat = 46) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.Color.ink)
            .multilineTextAlignment(.center)
            .keyboardType(keyboard)
            .frame(width: width)
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
        onCommit(Int(setsText), Int(repsText), Double(weightText))
    }

    static func weightLabel(_ kg: Double) -> String {
        let trimmed = kg.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(kg)) : String(format: "%.1f", kg)
        return "\(trimmed) kg"
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
                    .foregroundStyle(Theme.Color.ink)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))

                if !isHeader {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Sets (optional)")
                            TextField("—", text: $setsText)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Color.ink)
                                .keyboardType(.numberPad)
                                .padding(Theme.Spacing.sm)
                                .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Reps (optional)")
                            TextField("—", text: $repsText)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Color.ink)
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
            exerciseID: exercise?.exerciseID,
            name: trimmed,
            sets: isHeader ? nil : Int(setsText),
            reps: isHeader ? nil : Int(repsText),
            category: exercise?.category,
            kind: isHeader ? .header : .exercise,
            weightKg: isHeader ? nil : exercise?.weightKg
        )
        onSave(result)
        dismiss()
    }
}

// MARK: - Exercise detail sheet

private struct ExerciseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: LibraryExercise
    var isEditable: Bool = false
    var onUpdated: (LibraryExercise) -> Void = { _ in }

    @State private var detail: LibraryExercise
    @State private var videoURL: URL?
    @State private var imagePickerItem: PhotosPickerItem?
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var uploadMessage: String?

    init(exercise: LibraryExercise, isEditable: Bool = false, onUpdated: @escaping (LibraryExercise) -> Void = { _ in }) {
        self.exercise = exercise
        self.isEditable = isEditable
        self.onUpdated = onUpdated
        _detail = State(initialValue: exercise)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ExerciseThumbnail(url: detail.imageURL, cornerRadius: Theme.Radius.md, placeholderIcon: "figure.strengthtraining.traditional")
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                    Text(detail.categoryLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.Color.accent.opacity(0.25), in: Capsule())

                    if let description = detail.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isEditable {
                        VStack(spacing: 10) {
                            PhotosPicker(selection: $imagePickerItem, matching: .images) {
                                uploadButton(title: "Upload Image", icon: "photo")
                            }
                            PhotosPicker(selection: $videoPickerItem, matching: .videos) {
                                uploadButton(title: "Upload Demo Video", icon: "video")
                            }
                            if let uploadMessage {
                                Text(uploadMessage)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Theme.Color.inkMuted)
                            }
                        }
                    }

                    if detail.videoURL != nil {
                        if let videoURL {
                            VideoPlayer(player: AVPlayer(url: videoURL))
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                        } else {
                            ProgressView("Loading demo video…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Color.background)
            .navigationTitle(detail.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .task(id: detail.videoURL) {
                guard let path = detail.videoURL else {
                    videoURL = nil
                    return
                }
                videoURL = await ChatAttachmentLoader.localVideoURL(for: path)
            }
            .onChange(of: imagePickerItem) { _, item in
                guard let item else { return }
                Task { await uploadImage(from: item) }
            }
            .onChange(of: videoPickerItem) { _, item in
                guard let item else { return }
                Task { await uploadVideo(from: item) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func uploadButton(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(isUploading ? "Uploading…" : title)
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(Theme.Color.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.Color.surfaceMuted, in: Capsule())
    }

    @MainActor
    private func applyUpdate(_ dto: VerraAPI.ExerciseDTO) {
        let updated = LibraryExercise(from: dto)
        detail = updated
        onUpdated(updated)
        uploadMessage = "Media updated"
    }

    private func uploadImage(from item: PhotosPickerItem) async {
        guard isEditable, let token = AuthStore.accessToken else { return }
        isUploading = true
        defer {
            isUploading = false
            imagePickerItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let dto = try? await VerraAPI.uploadExerciseImage(exerciseID: detail.id, imageData: data, accessToken: token) else {
            await MainActor.run { uploadMessage = "Image upload failed" }
            return
        }
        await MainActor.run { applyUpdate(dto) }
    }

    private func uploadVideo(from item: PhotosPickerItem) async {
        guard isEditable, let token = AuthStore.accessToken else { return }
        isUploading = true
        defer {
            isUploading = false
            videoPickerItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let dto = try? await VerraAPI.uploadExerciseVideo(exerciseID: detail.id, videoData: data, accessToken: token) else {
            await MainActor.run { uploadMessage = "Video upload failed" }
            return
        }
        await MainActor.run { applyUpdate(dto) }
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

// MARK: - Exercise progress sheet

/// Shows logged weight over time for a single exercise, pulled across every
/// week that's been programmed for this client (matched by library exercise
/// ID when linked, otherwise by name).
private struct ExerciseProgressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileStore.self) private var profile
    let client: Client
    let exerciseName: String
    let exerciseID: UUID?

    @State private var isLoading = true

    private var points: [(week: Int, weightKg: Double)] {
        var results: [(Int, Double)] = []
        let weekCount = profile.workoutWeekCount(for: client.id)
        for week in 0..<weekCount {
            let matches = profile.workoutWeek(for: client.id, week: week)
                .flatMap(\.exercises)
                .filter { ex in
                    guard let weightKg = ex.weightKg, weightKg > 0 else { return false }
                    if let exerciseID, let matchID = ex.exerciseID { return matchID == exerciseID }
                    return ex.name.caseInsensitiveCompare(exerciseName) == .orderedSame
                }
                .compactMap(\.weightKg)
            if let best = matches.max() {
                results.append((week, best))
            }
        }
        return results
    }

    private var trend: ExerciseWeightTrend {
        ExerciseWeightTrend(values: points.map(\.weightKg))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if points.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    trendSummary
                    chartCard
                    if points.count < 2 {
                        Text("Log this exercise across another week to unlock a clearer trend.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Color.inkMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.background)
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .bold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            let weekCount = profile.workoutWeekCount(for: client.id)
            for week in 0..<weekCount {
                await profile.refreshModule(.workout, for: client, week: week)
            }
            isLoading = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
            Text("No recorded weights yet")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Color.ink)
            Text("Log a weight for \(exerciseName) on this exercise to start tracking progress.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var trendSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: trend.symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(trend.tint)
                .frame(width: 40, height: 40)
                .background(trend.tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(trend.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                Text(trend.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
            }
            Spacer(minLength: 0)
            if let delta = trend.deltaLabel {
                Text(delta)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(trend.tint)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Weight over time")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Color.inkMuted)
                Spacer()
                if let last = points.last {
                    Text(BuilderItemRow.weightLabel(last.weightKg))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                }
            }
            ExerciseTrendChart(values: points.map(\.weightKg))
            HStack {
                Text("Week \((points.first?.week ?? 0) + 1)")
                Spacer()
                Text("Week \((points.last?.week ?? 0) + 1)")
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Theme.Color.inkFaint)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }
}

/// Classifies weight history as increasing, decreasing, or consistent.
private struct ExerciseWeightTrend {
    enum Direction {
        case increasing, decreasing, consistent, insufficient
    }

    let direction: Direction
    let deltaKg: Double?

    init(values: [Double]) {
        guard values.count >= 2, let first = values.first, let last = values.last else {
            direction = .insufficient
            deltaKg = nil
            return
        }
        let delta = last - first
        deltaKg = delta
        // Treat small absolute/relative changes as flat so day-to-day noise
        // doesn't read as a trend.
        let threshold = max(abs(first) * 0.02, 0.5)
        if abs(delta) < threshold {
            direction = .consistent
        } else if delta > 0 {
            direction = .increasing
        } else {
            direction = .decreasing
        }
    }

    var title: String {
        switch direction {
        case .increasing: return "Increasing"
        case .decreasing: return "Decreasing"
        case .consistent: return "Consistent"
        case .insufficient: return "Getting started"
        }
    }

    var subtitle: String {
        switch direction {
        case .increasing: return "Working weight is trending up over time."
        case .decreasing: return "Working weight is trending down over time."
        case .consistent: return "Working weight has stayed about the same."
        case .insufficient: return "Need at least two weeks of logged weights."
        }
    }

    var symbol: String {
        switch direction {
        case .increasing: return "arrow.up.right"
        case .decreasing: return "arrow.down.right"
        case .consistent: return "arrow.right"
        case .insufficient: return "chart.line.uptrend.xyaxis"
        }
    }

    var tint: Color {
        switch direction {
        case .increasing: return Color(hex: 0x57C77B)
        case .decreasing: return Theme.Color.danger
        case .consistent: return Theme.Color.inkMuted
        case .insufficient: return Theme.Color.inkFaint
        }
    }

    var deltaLabel: String? {
        guard let deltaKg else { return nil }
        let trimmed = abs(deltaKg).truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(abs(deltaKg)))
            : String(format: "%.1f", abs(deltaKg))
        let sign = deltaKg > 0 ? "+" : (deltaKg < 0 ? "−" : "")
        return "\(sign)\(trimmed) kg"
    }
}

/// Minimal Path-based line chart (no Swift Charts dependency) matching the
/// visual language of `WeightTrendChart`.
private struct ExerciseTrendChart: View {
    let values: [Double]
    var height: CGFloat = 150

    private var lo: Double { (values.min() ?? 0) * 0.95 }
    private var hi: Double { max((values.max() ?? 1) * 1.05, lo + 0.001) }

    private func y(_ value: Double, in h: CGFloat) -> CGFloat {
        let span = max(hi - lo, 0.001)
        return h - CGFloat((value - lo) / span) * h
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts: [CGPoint] = values.enumerated().map { i, v in
                let x = values.count <= 1 ? w / 2 : w * CGFloat(i) / CGFloat(values.count - 1)
                return CGPoint(x: x, y: y(v, in: h))
            }
            ZStack {
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: CGPoint(x: first.x, y: h))
                    p.addLine(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    if let last = pts.last {
                        p.addLine(to: CGPoint(x: last.x, y: h))
                    }
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Theme.Color.accent.opacity(0.35), Theme.Color.accent.opacity(0)], startPoint: .top, endPoint: .bottom))

                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(Theme.Color.ink, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))

                ForEach(Array(pts.enumerated()), id: \.offset) { index, pt in
                    Circle()
                        .fill(index == pts.count - 1 ? Theme.Color.accent : Theme.Color.surface)
                        .frame(width: index == pts.count - 1 ? 12 : 9, height: index == pts.count - 1 ? 12 : 9)
                        .overlay(Circle().stroke(Theme.Color.ink, lineWidth: index == pts.count - 1 ? 2.5 : 2))
                        .position(pt)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: values)
        }
        .frame(height: height)
    }
}
