//
//  TrainerStore.swift
//  VerraOS
//

import SwiftUI

/// Owns the trainer's account profile and settings, synced with the backend.
@Observable
final class TrainerStore {
    var isLoadedFromServer = false
    var calendarPrefsJSON: String?

    var profile: TrainerProfile {
        didSet { schedulePreferencesSave() }
    }

    private var preferencesSaveTask: Task<Void, Never>?
    private var isApplyingServerState = false

    init() {
        profile = .empty
    }

    @MainActor
    func refreshFromServer() async {
        guard let token = AuthStore.accessToken else { return }
        do {
            let response = try await VerraAPI.fetchProfile(accessToken: token)
            await ProfileLoader.applyTrainer(response, to: self)
            if let prefs = try? await VerraAPI.fetchNotificationPreferences(accessToken: token) {
                applyNotificationPreferences(prefs)
            }
        } catch {
            // Keep in-memory profile when offline.
        }
    }

    @MainActor
    func saveToServer(avatarUpload: Data?) async throws {
        guard let token = AuthStore.accessToken else {
            throw APIError.server("Not signed in")
        }

        if let avatarUpload {
            let response = try await VerraAPI.uploadAvatar(
                imageData: avatarUpload,
                filename: "avatar.jpg",
                mimeType: "image/jpeg",
                accessToken: token
            )
            await ProfileLoader.applyTrainer(response, to: self)
        }

        let response = try await VerraAPI.updateProfile(
            accessToken: token,
            body: UpdateProfileBody(
                displayName: profile.name,
                name: profile.name,
                title: profile.title,
                bio: profile.bio,
                specialties: profile.specialties.map(\.rawValue).sorted(),
                weightUnit: profile.weightUnit?.rawValue,
                biometricLoginEnabled: profile.biometricLoginEnabled,
                calendarPrefsJSON: nil
            )
        )
        await ProfileLoader.applyTrainer(response, to: self)
        await savePreferencesToServer()
    }

    @MainActor
    func saveCalendarPrefsJSON(_ json: String) async {
        guard let token = AuthStore.accessToken else { return }
        _ = try? await VerraAPI.updateProfile(
            accessToken: token,
            body: UpdateProfileBody(calendarPrefsJSON: json)
        )
    }

    @MainActor
    func savePreferencesToServer() async {
        guard let token = AuthStore.accessToken else { return }
        _ = try? await VerraAPI.updateNotificationPreferences(
            VerraAPI.UpdateNotificationPreferencesBody(
                notificationsEnabled: profile.notificationsEnabled,
                notifyMoney: profile.notifyMoney,
                notifySchedule: profile.notifySchedule,
                notifyMessages: true,
                notifyActivity: profile.notifyActivity,
                activityMode: profile.activityMode.rawValue,
                quietHoursEnabled: profile.quietHoursEnabled,
                quietStartMinutes: profile.quietStartMinutes,
                quietEndMinutes: profile.quietEndMinutes,
                smsEnabled: nil,
                reminderMinutesBefore: nil
            ),
            accessToken: token
        )
        _ = try? await VerraAPI.updateProfile(
            accessToken: token,
            body: UpdateProfileBody(
                weightUnit: profile.weightUnit?.rawValue,
                biometricLoginEnabled: profile.biometricLoginEnabled
            )
        )
    }

    private func schedulePreferencesSave() {
        guard !isApplyingServerState else { return }
        preferencesSaveTask?.cancel()
        preferencesSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await savePreferencesToServer()
        }
    }

    func applyNotificationPreferences(_ prefs: VerraAPI.NotificationPreferencesDTO) {
        isApplyingServerState = true
        profile.notificationsEnabled = prefs.notificationsEnabled
        profile.notifyMoney = prefs.notifyMoney
        profile.notifySchedule = prefs.notifySchedule
        profile.notifyActivity = prefs.notifyActivity
        profile.activityMode = ActivityAlertMode(rawValue: prefs.activityMode) ?? .personalBests
        profile.quietHoursEnabled = prefs.quietHoursEnabled
        profile.quietStartMinutes = prefs.quietStartMinutes
        profile.quietEndMinutes = prefs.quietEndMinutes
        isApplyingServerState = false
    }

    // MARK: Convenience

    var units: WeightUnit {
        get { profile.weightUnit ?? .kg }
        set { profile.weightUnit = newValue }
    }

    func toggleSpecialty(_ specialty: Specialty) {
        if profile.specialties.contains(specialty) {
            profile.specialties.remove(specialty)
        } else {
            profile.specialties.insert(specialty)
        }
    }
}
