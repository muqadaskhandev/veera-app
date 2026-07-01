//
//  AddEditAppointmentView.swift
//  VerraOS
//

import SwiftUI

/// The appointment types surfaced in the editor's segmented toggle.
enum AppointmentType: CaseIterable, Identifiable {
    case training
    case consultation

    var id: Self { self }

    var label: String {
        switch self {
        case .training: return "Training"
        case .consultation: return "Consultation"
        }
    }

    var tag: SessionTag {
        switch self {
        case .training: return .training
        case .consultation: return .consult
        }
    }

    init(tag: SessionTag) {
        switch tag {
        case .consult: self = .consultation
        default: self = .training
        }
    }
}

/// Add or edit an appointment. Reached from the Schedule "+" button (new) or the
/// detail card's Edit action (pre-filled).
struct AddEditAppointmentView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// nil → creating a new appointment; non-nil → editing.
    let existing: Session?
    var onSaved: (String) -> Void

    @State private var selectedClient: Client?
    @State private var date: Date
    @State private var endDate: Date
    @State private var type: AppointmentType
    @State private var notes: String
    @State private var repeatWeekly: Bool
    @State private var selectedWeekdays: Set<Int> = []
    @State private var skippedDays: Set<Int> = []
    @State private var clientSearch: String = ""
    @State private var showConflictAlert = false
    @State private var conflictMessage = ""
    @State private var pendingCommit: (() -> Void)?

    /// Mon–Sun chips. Values are `Calendar` weekday ints (1 = Sun … 7 = Sat).
    private let weekdayOptions: [(label: String, value: Int)] = [
        ("Mon", 2), ("Tue", 3), ("Wed", 4), ("Thu", 5), ("Fri", 6), ("Sat", 7), ("Sun", 1)
    ]

    init(existing: Session?, onSaved: @escaping (String) -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        let tag = existing?.accent ?? .training
        _type = State(initialValue: AppointmentType(tag: tag))
        _notes = State(initialValue: existing?.notes ?? "")
        _repeatWeekly = State(initialValue: false)
        let start = Self.initialDate(for: existing)
        _date = State(initialValue: start)
        let duration = existing?.durationMinutes ?? 60
        _endDate = State(initialValue: start.addingTimeInterval(Double(duration) * 60))
    }

    private var isEditing: Bool { existing != nil }

    private var filteredClients: [Client] {
        guard !clientSearch.isEmpty else { return store.clients }
        return store.clients.filter { $0.name.localizedCaseInsensitiveContains(clientSearch) }
    }

    private var canSave: Bool {
        selectedClient != nil
    }

    /// Recurring multi-day selection only applies to brand-new training sessions.
    private var supportsRecurrence: Bool { type == .training && !isEditing }
    private var isMultiDay: Bool { supportsRecurrence && !selectedWeekdays.isEmpty }

    private var startMinutes: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 9) * 60 + (c.minute ?? 0)
    }

    private var endMinutes: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: endDate)
        return (c.hour ?? 10) * 60 + (c.minute ?? 0)
    }

    private var durationMinutes: Int {
        endMinutes > startMinutes ? endMinutes - startMinutes : 60
    }

    /// Live remaining-session balance for the picked client.
    private var clientRemaining: Int {
        store.clients.first { $0.id == selectedClient?.id }?.sessionsRemaining ?? 0
    }

    /// How many sessions the series may generate. Repeat stops once the balance
    /// is used up; a one-off multi-day pick just covers the chosen weekdays.
    private var sessionCap: Int {
        repeatWeekly ? max(selectedWeekdays.count, clientRemaining) : selectedWeekdays.count
    }

    /// Concrete dates (within June 2026) the series will land on, capped.
    private func occurrenceDates() -> [Date] {
        guard isMultiDay else { return [] }
        let cal = Calendar.current
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        var result: [Date] = []
        var offset = 0
        let maxScan = repeatWeekly ? 7 * 8 : 7
        while offset < maxScan && result.count < sessionCap {
            if let day = cal.date(byAdding: .day, value: offset, to: weekStart) {
                let comps = cal.dateComponents([.year, .month, .weekday], from: day)
                if comps.year == 2026, comps.month == 6,
                   let wd = comps.weekday, selectedWeekdays.contains(wd),
                   let dt = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) {
                    result.append(dt)
                }
            }
            offset += 1
        }
        return result
    }

    private var activeOccurrences: [Date] {
        occurrenceDates().filter { !skippedDays.contains(Calendar.current.component(.day, from: $0)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    typePicker
                    clientSelector
                    dateTimeSection
                    if !currentConflicts.isEmpty { conflictBanner }
                    if supportsRecurrence { recurrenceSection }
                    notesSection
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 40)
            }
            .background(Theme.Color.background)
            .navigationTitle(isEditing ? "Edit Appointment" : "New Appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSave ? Theme.Color.ink : Theme.Color.inkFaint)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: preselectClient)
            .alert("Schedule Conflict", isPresented: $showConflictAlert) {
                Button("Cancel", role: .cancel) { pendingCommit = nil }
                Button("Save Anyway") {
                    pendingCommit?()
                    pendingCommit = nil
                }
            } message: {
                Text(conflictMessage)
            }
        }
    }

    private var currentConflicts: [ScheduleConflict] {
        if isMultiDay {
            return activeOccurrences.flatMap { occurrence in
                let dom = Calendar.current.component(.day, from: occurrence)
                return store.detectConflicts(
                    dayOfMonth: dom,
                    startMinutes: startMinutes,
                    durationMinutes: durationMinutes,
                    excludingSessionID: existing?.id
                )
            }
        }
        let day = Calendar.current.component(.day, from: date)
        return store.detectConflicts(
            dayOfMonth: day,
            startMinutes: startMinutes,
            durationMinutes: durationMinutes,
            excludingSessionID: existing?.id
        )
    }

    private var conflictBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(hex: 0xE08A3C))
                Text("Time conflict detected")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
            }
            ForEach(currentConflicts) { conflict in
                HStack(spacing: 6) {
                    Text("•")
                    Text("\(conflict.title) · \(conflict.timeRange)")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.Color.inkMuted)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xE08A3C).opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Color(hex: 0xE08A3C).opacity(0.35), lineWidth: 1))
    }

    // MARK: Sections

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Session Type")
            HStack(spacing: 6) {
                ForEach(AppointmentType.allCases) { item in
                    let isActive = item == type
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { type = item }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(item.tag.tint).frame(width: 8, height: 8)
                            Text(item.label)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(isActive ? Theme.Color.accent : Theme.Color.surface, in: Capsule())
                        .overlay(Capsule().stroke(isActive ? .clear : Theme.Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var clientSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Client")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkFaint)
                TextField("Search roster", text: $clientSearch)
                    .font(.system(size: 15, weight: .medium))
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 12)
            .background(Theme.Color.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))

            VStack(spacing: 0) {
                ForEach(filteredClients) { client in
                    let isSelected = client.id == selectedClient?.id
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { selectedClient = client }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(isSelected ? Theme.Color.ink : Theme.Color.surfaceMuted)
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Text(client.initials)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.inkMuted)
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(client.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.Color.ink)
                                Text("\(client.sessionsRemaining) sessions left")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.Color.inkMuted)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x57C77B))
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if client.id != filteredClients.last?.id {
                        Rectangle().fill(Theme.Color.hairline).frame(height: 1).padding(.leading, 62)
                    }
                }
                if filteredClients.isEmpty {
                    Text("No clients match \"\(clientSearch)\"")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                }
            }
            .padding(.vertical, 4)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Date & Time")
            VStack(spacing: 0) {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 6)
                Rectangle().fill(Theme.Color.hairline).frame(height: 1).padding(.horizontal, Theme.Spacing.md)
                DatePicker("Start time", selection: $date, displayedComponents: .hourAndMinute)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 6)
                Rectangle().fill(Theme.Color.hairline).frame(height: 1).padding(.horizontal, Theme.Spacing.md)
                DatePicker("End time", selection: $endDate, displayedComponents: .hourAndMinute)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 6)
            }
            .font(.system(size: 15, weight: .semibold))
            .tint(Theme.Color.ink)
            .padding(.vertical, 6)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Notes")
            TextField("Add session notes", text: $notes, axis: .vertical)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(3...6)
                .padding(Theme.Spacing.md)
                .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Repeat On")
            HStack(spacing: 6) {
                ForEach(weekdayOptions, id: \.value) { option in
                    let isOn = selectedWeekdays.contains(option.value)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            if isOn { selectedWeekdays.remove(option.value) }
                            else { selectedWeekdays.insert(option.value) }
                            skippedDays.removeAll()
                        }
                    } label: {
                        Text(option.label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isOn ? Theme.Color.accentInk : Theme.Color.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isOn ? Theme.Color.accent : Theme.Color.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isOn ? .clear : Theme.Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle(isOn: $repeatWeekly) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeat Weekly")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                    Text("Repeats the chosen days until \(selectedClient?.name.firstWord ?? "the client")'s sessions run out.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
            }
            .tint(Theme.Color.accent)
            .disabled(selectedWeekdays.isEmpty)
            .opacity(selectedWeekdays.isEmpty ? 0.5 : 1)
            .padding(.top, 2)

            if isMultiDay { occurrencePreview }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }

    private var occurrencePreview: some View {
        let dates = occurrenceDates()
        let activeCount = dates.filter { !skippedDays.contains(Calendar.current.component(.day, from: $0)) }.count
        return VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Theme.Color.hairline).frame(height: 1)
            HStack {
                sectionLabel("Sessions")
                Spacer()
                Text("\(activeCount) scheduled")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Theme.Color.accent, in: Capsule())
            }
            ForEach(dates, id: \.self) { day in
                let dom = Calendar.current.component(.day, from: day)
                let skipped = skippedDays.contains(dom)
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                        if skipped { skippedDays.remove(dom) } else { skippedDays.insert(dom) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: skipped ? "circle" : "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(skipped ? Theme.Color.inkFaint : Color(hex: 0x57C77B))
                        Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(skipped ? Theme.Color.inkFaint : Theme.Color.ink)
                            .strikethrough(skipped, color: Theme.Color.inkFaint)
                        Spacer()
                        if skipped {
                            Text("Skipped")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.Color.inkFaint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.Color.inkFaint)
    }

    // MARK: Actions

    private func preselectClient() {
        guard selectedClient == nil, let existing else { return }
        selectedClient = store.clients.first { $0.name == existing.clientName }
    }

    private func save() {
        let conflicts = currentConflicts
        if !conflicts.isEmpty {
            conflictMessage = conflicts.map { "\($0.title) (\($0.timeRange))" }.joined(separator: "\n")
            pendingCommit = commitSave
            showConflictAlert = true
            return
        }
        commitSave()
    }

    private func commitSave() {
        let tag = type.tag
        let name = selectedClient?.name ?? "Client"
        let initials = selectedClient?.initials ?? "?"
        let location = existing?.location ?? "Studio A"

        if isMultiDay {
            let days = activeOccurrences
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                for occurrence in days {
                    let dom = Calendar.current.component(.day, from: occurrence)
                    store.upsert(Session.make(
                        id: UUID(),
                        clientName: name,
                        initials: initials,
                        dayOfMonth: dom,
                        startMinutes: startMinutes,
                        durationMinutes: durationMinutes,
                        accent: tag,
                        location: location,
                        notes: notes,
                        isCompleted: false
                    ))
                }
            }
            let count = days.count
            onSaved("\(count) appointment\(count == 1 ? "" : "s") added")
            dismiss()
            return
        }

        let day = Calendar.current.component(.day, from: date)
        let session = Session.make(
            id: existing?.id ?? UUID(),
            clientName: name,
            initials: initials,
            dayOfMonth: day,
            startMinutes: startMinutes,
            durationMinutes: durationMinutes,
            accent: tag,
            location: location,
            notes: notes,
            isCompleted: existing?.isCompleted ?? false
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            store.upsert(session)
        }

        let verb = isEditing ? "updated" : "added"
        onSaved("Appointment \(verb)")
        dismiss()
    }

    private static func initialDate(for existing: Session?) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = existing?.dayOfMonth ?? 17
        let minutes = existing?.startMinutes ?? 540
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        return Calendar.current.date(from: comps) ?? Date()
    }
}
