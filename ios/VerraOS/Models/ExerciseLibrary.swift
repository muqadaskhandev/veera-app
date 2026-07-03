//
//  ExerciseLibrary.swift
//  VerraOS
//

import SwiftUI

/// Server-backed exercise from the shared library.
struct LibraryExercise: Identifiable, Hashable {
    let id: UUID
    let name: String
    let category: String
    let description: String?
    let imageURL: String?
    let videoURL: String?

    init(from dto: VerraAPI.ExerciseDTO) {
        id = dto.id
        name = dto.name
        category = dto.category
        description = dto.description
        imageURL = dto.imageURL
        videoURL = dto.videoURL
    }

    var categoryLabel: String {
        category.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

enum ExerciseCategoryFilter: String, CaseIterable, Identifiable {
    case all
    case strength
    case conditioning
    case accessory
    case mobility
    case cardio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .strength: return "Strength"
        case .conditioning: return "Conditioning"
        case .accessory: return "Accessory"
        case .mobility: return "Mobility"
        case .cardio: return "Cardio"
        }
    }

    var apiValue: String? {
        self == .all ? nil : rawValue
    }
}
