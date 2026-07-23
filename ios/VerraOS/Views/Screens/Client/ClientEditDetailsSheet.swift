//
//  ClientEditDetailsSheet.swift
//  VerraOS
//

import PhotosUI
import SwiftUI

struct ClientEditDetailsSheet: View {
    @Bindable var account: ClientAccountStore

    @Environment(TrainerStore.self) private var trainer
    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String
    @State private var age: String
    @State private var heightFeet: String
    @State private var heightInches: String
    @State private var startWeight: String
    @State private var goalWeight: String
    @State private var pickerItem: PhotosPickerItem?
    @State private var draftAvatarData: Data?
    @State private var pendingAvatarData: Data?
    @State private var toast: ToastData?
    @State private var didPopulateWeights = false

    private enum Field: Hashable {
        case name, age, heightFeet, heightInches, startWeight, goalWeight
    }
    @FocusState private var focusedField: Field?

    private var unit: WeightUnit { trainer.units }

    init(account: ClientAccountStore) {
        self.account = account
        _draftName = State(initialValue: account.name)
        _draftAvatarData = State(initialValue: account.avatarData)

        let client = account.client
        _age = State(initialValue: client?.age.map { "\($0)" } ?? "")
        if let cm = client?.heightCm {
            let totalInches = Int((Double(cm) / 2.54).rounded())
            _heightFeet = State(initialValue: "\(totalInches / 12)")
            _heightInches = State(initialValue: "\(totalInches % 12)")
        } else {
            _heightFeet = State(initialValue: "")
            _heightInches = State(initialValue: "")
        }
        // Weight fields depend on the trainer's preferred unit, which isn't
        // available from the environment yet inside `init` — populated in
        // `onAppear` via `populateWeights()` instead.
        _startWeight = State(initialValue: "")
        _goalWeight = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    photoSection
                    field(label: "Display Name", text: $draftName, placeholder: "Your name")
                    detailsSection
                    accountCard
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 44)
            }
            .background(Theme.Color.background)
            .navigationTitle("Edit Profile")
            .preferredColorScheme(.light)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(account.isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.Color.accent, in: Capsule())
                    .disabled(account.isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }.fontWeight(.semibold)
                }
            }
            .toast($toast)
            .onChange(of: pickerItem) { _, newValue in
                guard let newValue else { return }
                Task { await loadImage(newValue) }
            }
            .onAppear {
                guard !didPopulateWeights else { return }
                didPopulateWeights = true
                populateWeights()
            }
        }
    }

    private func populateWeights() {
        let client = account.client
        let startKg = client?.weightKg.map(Double.init) ?? 0
        let goalKg = client?.goalWeightKg.map(Double.init) ?? 0
        startWeight = startKg > 0 ? formatWeight(unit.fromKg(startKg)) : ""
        goalWeight = goalKg > 0 ? formatWeight(unit.fromKg(goalKg)) : ""
    }

    private func formatWeight(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("Your Details")
            field(label: "Age", text: $age, placeholder: "—", keyboard: .numberPad)
            heightField
            weightField(label: "Start weight", text: $startWeight, field: .startWeight)
            weightField(label: "Goal weight", text: $goalWeight, field: .goalWeight)
        }
    }

    private var heightField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Height")
            HStack(spacing: Theme.Spacing.sm) {
                unitBox(text: $heightFeet, unit: "ft", field: .heightFeet)
                unitBox(text: $heightInches, unit: "in", field: .heightInches)
            }
        }
    }

    private func weightField(label: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)
            HStack {
                TextField("", text: text, prompt: Text("—").foregroundStyle(Theme.Color.inkFaint))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                    .tint(Theme.Color.ink)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: field)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                Text(unit.short)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { focusedField = field }
        }
    }

    private func unitBox(text: Binding<String>, unit: String, field: Field) -> some View {
        HStack {
            TextField("", text: text, prompt: Text("—").foregroundStyle(Theme.Color.inkFaint))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
                .tint(Theme.Color.ink)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: field)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            Text(unit)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
    }

    private var photoSection: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    avatar
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                        .frame(width: 34, height: 34)
                        .background(Theme.Color.accent, in: Circle())
                        .overlay(Circle().stroke(Theme.Color.background, lineWidth: 3))
                }
            }
            .buttonStyle(.plain)

            Text("Tap to change photo")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var avatar: some View {
        Group {
            if let data = draftAvatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Theme.Color.ink)
                    .overlay(
                        Text(account.initials)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.accent)
                    )
            }
        }
        .frame(width: 108, height: 108)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Color.accent, lineWidth: 2.5).padding(-5))
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Account")
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Email")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkFaint)
                    Text(account.email.isEmpty ? "Not set" : account.email)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    @MainActor
    private func save() async {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toast = ToastData(message: "Name is required", icon: "exclamationmark.triangle.fill")
            return
        }

        let parsedAge = Int(age.trimmingCharacters(in: .whitespaces))
        let feet = Int(heightFeet.trimmingCharacters(in: .whitespaces))
        let inches = Int(heightInches.trimmingCharacters(in: .whitespaces))
        let heightCm: Int? = (feet != nil || inches != nil)
            ? Client.cm(fromFeet: feet ?? 0, inches: inches ?? 0)
            : nil
        let startKg = parse(startWeight).map { Int(unit.toKg($0).rounded()) }
        let goalKg = parse(goalWeight).map { Int(unit.toKg($0).rounded()) }

        do {
            try await account.save(
                displayName: trimmed,
                avatarUpload: pendingAvatarData,
                age: parsedAge,
                heightCm: heightCm,
                weightKg: startKg,
                goalWeightKg: goalKg
            )
            pendingAvatarData = nil
            draftAvatarData = account.avatarData
            dismiss()
        } catch {
            toast = ToastData(message: error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
    }

    private func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private func loadImage(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        let resized = image.resized(maxDimension: 512)
        if let jpeg = resized.jpegData(compressionQuality: 0.82) {
            await MainActor.run {
                draftAvatarData = jpeg
                pendingAvatarData = jpeg
            }
        }
    }

    private func field(
        label: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        let field: Field = keyboard == .numberPad ? .age : .name
        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)
            TextField(placeholder, text: text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
                .keyboardType(keyboard)
                .focused($focusedField, equals: field)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { self.focusedField = field }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.Color.inkFaint)
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
