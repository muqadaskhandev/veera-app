//
//  ProfileModuleRouter.swift
//  VerraOS
//
//  Maps a ModuleRoute to the correct module screen, looking the client up live
//  from the store so edits stay reflected.
//

import SwiftUI

struct ProfileModuleRouter: View {
    let route: ModuleRoute
    /// Client-side wearable connection state, threaded into WearableDataView so
    /// the synced charts hide when nothing is connected. `nil` (trainer) always
    /// shows charts.
    var wearablesConnected: Bool? = nil
    var onBack: () -> Void

    @Environment(ClientStore.self) private var clientStore
    @Environment(ProfileStore.self) private var profile

    private var client: Client? { clientStore.clients.first { $0.id == route.clientID } }

    var body: some View {
        Group {
            if let client {
                Group {
                    switch route.module {
                    case .wearables: WearableDataView(client: client, connectionState: wearablesConnected, onBack: onBack)
                    case .workout: WorkoutPlanView(client: client, onBack: onBack)
                    case .nutrition: NutritionPlanView(client: client, onBack: onBack)
                    case .weight: WeightTrackingView(client: client, onBack: onBack)
                    case .photos: ProgressPhotosView(client: client, onBack: onBack)
                    case .financials: ClientFinancialsView(clientID: route.clientID, onBack: onBack)
                    }
                }
                .task(id: route.module) {
                    guard route.module != .workout else { return }
                    await profile.refreshModule(route.module, for: client)
                }
            } else {
                VStack { Spacer(); Text("Client unavailable").foregroundStyle(Theme.Color.inkMuted); Spacer() }
                    .background(Theme.Color.background)
            }
        }
    }
}
