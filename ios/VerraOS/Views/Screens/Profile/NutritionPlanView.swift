//
//  NutritionPlanView.swift
//  VerraOS
//

import SwiftUI

struct NutritionPlanView: View {
    let client: Client
    var onBack: () -> Void

    @Environment(ProfileStore.self) private var profile
    @Environment(\.isReadOnly) private var isReadOnly

    @State private var editingMacros = false
    @State private var editingNote: NutritionNote?
    @State private var presentNoteEditor = false
    @State private var editingSupplement: Supplement?
    @State private var presentSupplementEditor = false
    @State private var toast: ToastData?

    private var macros: MacroTargets { profile.macros(for: client.id) }
    private var notes: [NutritionNote] { profile.notes(for: client.id) }
    private var supps: [Supplement] { profile.supplements(for: client.id) }

    var body: some View {
        VStack(spacing: 0) {
            ProfileTopBar(title: "Nutrition", subtitle: client.name.firstWord, onBack: onBack)
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.md) {
                    dailyTargets
                    supplements
                    notesCard
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, 100)
            }
        }
        .background(Theme.Color.background)
        .toast($toast)
        .sheet(isPresented: $editingMacros) {
            MacroEditorSheet(macros: macros) { updated in
                profile.setMacros(updated, for: client.id)
                toast = ToastData(message: "Targets updated", icon: "checkmark.circle.fill")
            }
        }
        .sheet(isPresented: $presentNoteEditor) {
            NoteEditorSheet(note: editingNote) { text in
                if let editingNote {
                    profile.updateNote(NutritionNote(id: editingNote.id, text: text), for: client.id)
                    toast = ToastData(message: "Note saved", icon: "checkmark.circle.fill")
                } else {
                    profile.addNote(text, for: client.id)
                    toast = ToastData(message: "Note added", icon: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $presentSupplementEditor) {
            SupplementEditorSheet(supplement: editingSupplement) { name, dosage in
                if let editingSupplement {
                    profile.updateSupplement(Supplement(id: editingSupplement.id, name: name, dosage: dosage), for: client.id)
                    toast = ToastData(message: "Supplement saved", icon: "checkmark.circle.fill")
                } else {
                    profile.addSupplement(name: name, dosage: dosage, for: client.id)
                    toast = ToastData(message: "Supplement added", icon: "plus.circle.fill")
                }
            }
        }
    }

    private var dailyTargets: some View {
        SectionCard(title: "Daily Targets", icon: "target") {
            VStack(spacing: 14) {
                macroBar(label: "Protein", grams: macros.protein, max: 250, tint: Color(hex: 0xE8483D))
                macroBar(label: "Carbs", grams: macros.carbs, max: 350, tint: Color(hex: 0xE8893C))
                macroBar(label: "Fats", grams: macros.fats, max: 120, tint: Color(hex: 0xE7B83C))
                Rectangle().fill(Theme.Color.hairline).frame(height: 1)
                HStack {
                    Text("Daily Energy")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkMuted)
                    Spacer()
                    Text("\(macros.calories.formatted()) kcal")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: macros.calories)
                }
                if !isReadOnly {
                    Button { editingMacros = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .bold))
                            Text("Edit Targets").font(.system(size: 14.5, weight: .bold))
                        }
                        .foregroundStyle(Theme.Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.Color.surfaceMuted, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var supplements: some View {
        SectionCard(title: "Supplements", icon: "pills.fill") {
            VStack(spacing: 10) {
                if supps.isEmpty {
                    Text(isReadOnly ? "No supplements set." : "No supplements yet — add one below.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ForEach(supps) { supp in
                        Button {
                            guard !isReadOnly else { return }
                            editingSupplement = supp
                            presentSupplementEditor = true
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(supp.name)
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(Theme.Color.ink)
                                    if !supp.dosage.isEmpty {
                                        Text(supp.dosage)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(Theme.Color.inkMuted)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if !isReadOnly {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.Color.inkFaint)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if !isReadOnly {
                                Button(role: .destructive) {
                                    profile.deleteSupplement(supp.id, for: client.id)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                        if supp.id != supps.last?.id {
                            Rectangle().fill(Theme.Color.hairline).frame(height: 1)
                        }
                    }
                }
                if !isReadOnly {
                    Button {
                        editingSupplement = nil
                        presentSupplementEditor = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                            Text("Add Supplement").font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(Theme.Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.Color.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notesCard: some View {
        SectionCard(title: "Protocol Notes", icon: "note.text") {
            VStack(spacing: 10) {
                if notes.isEmpty {
                    Text(isReadOnly ? "No notes from your coach yet." : "No notes yet — add one below.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ForEach(notes) { note in
                        Button {
                            guard !isReadOnly else { return }
                            editingNote = note
                            presentNoteEditor = true
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(Theme.Color.accent).frame(width: 6, height: 6).padding(.top, 6)
                                Text(note.text)
                                    .font(.system(size: 14.5, weight: .medium))
                                    .foregroundStyle(Theme.Color.ink)
                                    .lineSpacing(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if !isReadOnly {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.Color.inkFaint)
                                        .padding(.top, 2)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if !isReadOnly {
                                Button(role: .destructive) {
                                    profile.deleteNote(note.id, for: client.id)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                        if note.id != notes.last?.id {
                            Rectangle().fill(Theme.Color.hairline).frame(height: 1)
                        }
                    }
                }
                if !isReadOnly {
                    Button {
                        editingNote = nil
                        presentNoteEditor = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                            Text("Add Note").font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(Theme.Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.Color.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func macroBar(label: String, grams: Int, max: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                Spacer()
                Text("\(grams)g")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Color.surfaceMuted)
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(Double(grams) / Double(max), 1.0)))
                }
            }
            .frame(height: 10)
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: grams)
        }
    }
}

// MARK: - Macro editor

private struct MacroEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let macros: MacroTargets
    var onSave: (MacroTargets) -> Void

    @State private var protein: String
    @State private var carbs: String
    @State private var fats: String

    init(macros: MacroTargets, onSave: @escaping (MacroTargets) -> Void) {
        self.macros = macros
        self.onSave = onSave
        _protein = State(initialValue: String(macros.protein))
        _carbs = State(initialValue: String(macros.carbs))
        _fats = State(initialValue: String(macros.fats))
    }

    private var liveCalories: Int {
        (Int(protein) ?? 0) * 4 + (Int(carbs) ?? 0) * 4 + (Int(fats) ?? 0) * 9
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                macroField(title: "Protein", text: $protein, tint: Color(hex: 0xE8483D))
                macroField(title: "Carbs", text: $carbs, tint: Color(hex: 0xE8893C))
                macroField(title: "Fats", text: $fats, tint: Color(hex: 0xE7B83C))
                HStack {
                    Text("Daily Energy")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkMuted)
                    Spacer()
                    Text("\(liveCalories.formatted()) kcal")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: liveCalories)
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.background)
            .navigationTitle("Edit Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(MacroTargets(protein: Int(protein) ?? 0, carbs: Int(carbs) ?? 0, fats: Int(fats) ?? 0))
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                }
            }
        }
        .presentationDetents([.height(420)])
    }

    private func macroField(title: String, text: Binding<String>, tint: Color) -> some View {
        HStack(spacing: 12) {
            Circle().fill(tint).frame(width: 10, height: 10)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
            Spacer()
            TextField("0", text: text)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("g").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Color.inkMuted)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(Theme.Color.hairline, lineWidth: 1))
    }
}

// MARK: - Note editor

private struct NoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let note: NutritionNote?
    var onSave: (String) -> Void

    @State private var text: String

    init(note: NutritionNote?, onSave: @escaping (String) -> Void) {
        self.note = note
        self.onSave = onSave
        _text = State(initialValue: note?.text ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                TextField("Write a protocol note…", text: $text, axis: .vertical)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(4...10)
                    .padding(Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.background)
            .navigationTitle(note == nil ? "Add Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { onSave(trimmed) }
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.height(300)])
    }
}

// MARK: - Supplement editor

private struct SupplementEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let supplement: Supplement?
    var onSave: (String, String) -> Void

    @State private var name: String
    @State private var dosage: String

    init(supplement: Supplement?, onSave: @escaping (String, String) -> Void) {
        self.supplement = supplement
        self.onSave = onSave
        _name = State(initialValue: supplement?.name ?? "")
        _dosage = State(initialValue: supplement?.dosage ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                fieldLabel("Name")
                TextField("e.g. Creatine Monohydrate", text: $name)
                    .font(.system(size: 17, weight: .semibold))
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))

                fieldLabel("Dosage / notes (optional)")
                TextField("e.g. 5g daily", text: $dosage, axis: .vertical)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1...4)
                    .padding(Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.background)
            .navigationTitle(supplement == nil ? "Add Supplement" : "Edit Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedName.isEmpty {
                            onSave(trimmedName, dosage.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.height(340)])
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Theme.Color.inkFaint)
    }
}
