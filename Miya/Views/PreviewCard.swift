//
//  PreviewCard.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import SwiftUI

/// A tile in a section grid: a square cover image (or SF Symbol fallback) with
/// the title below. Used at `cardSize` on Home and larger on the section detail.
struct PreviewCard: View {
    static let cardSize = 84.0

    let title: String
    let systemImage: String
    var imageURL: URL? = nil
    var size: CGFloat = PreviewCard.cardSize

    var body: some View {
        VStack(spacing: 8) {
            tile
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: size)
    }

    private var tile: some View {
        ZStack {
            Color(.systemGray6)
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .failure:
                        glyph
                    @unknown default:
                        glyph
                    }
                }
            } else {
                glyph
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var glyph: some View {
        Image(systemName: systemImage)
            .font(.title3)
            .foregroundStyle(.secondary)
    }
}

extension PreviewCard {
    init(item: HomeSectionItem, size: CGFloat = PreviewCard.cardSize) {
        self.init(
            title: item.title,
            systemImage: item.systemImage,
            imageURL: item.imageURL,
            size: size
        )
    }
}

/// The trailing tile that stands in for the remaining items in a section and
/// acts as the "see the full list" affordance. Store-free: the caller wires the tap.
struct MoreCard: View {
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Color(.systemGray6)
                Image(systemName: "arrow.right")
                    .font(.title3)
            }
            .foregroundStyle(.primary)
            .frame(width: PreviewCard.cardSize, height: PreviewCard.cardSize)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.primary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            Text("More")
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(width: PreviewCard.cardSize)
    }
}

#Preview {
    HStack(alignment: .top, spacing: 12) {
        PreviewCard(title: "Midnight City", systemImage: "music.note")
        PreviewCard(
            title: "Redbone",
            systemImage: "music.note",
            imageURL: URL(string: "https://picsum.photos/seed/miya-redbone/600")
        )
        MoreCard()
    }
    .padding()
}
