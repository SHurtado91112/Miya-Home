//
//  PreviewCard.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import SwiftUI

/// A single square tile in a Home section's preview grid.
struct PreviewCard: View {
    static let cardSize = 84.0

    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .frame(width: Self.cardSize, height: Self.cardSize, alignment: .center)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

extension PreviewCard {
    init(item: HomeSectionItem) {
        self.init(title: item.title, systemImage: item.systemImage)
    }
}

/// The trailing tile that stands in for the remaining items in a section and
/// acts as the "see the full list" affordance. Store-free: the caller wires the tap.
struct MoreCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.right")
                .font(.title3)
            Text("More")
                .font(.caption)
        }
        .foregroundStyle(.primary)
        .frame(width: PreviewCard.cardSize, height: PreviewCard.cardSize, alignment: .center)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.primary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
    }
}

#Preview {
    HStack(spacing: 12) {
        PreviewCard(title: "Midnight City", systemImage: "music.note")
        MoreCard()
    }
    .padding()
}
