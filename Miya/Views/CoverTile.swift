//
//  CoverTile.swift
//  Miya
//
//  Created by Steven Hurtado on 9/5/26.
//

import SwiftUI

/// One rounded cover: an async image with an SF Symbol fallback. The phase switch
/// matches the original `PreviewCard` tile so cards render identically.
struct CoverTile: View {
    let systemImage: String
    var imageURL: URL? = nil
    var size: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var glyph: some View {
        Image(systemName: systemImage)
            .font(.title3)
            .foregroundStyle(.secondary)
    }
}

/// Reserves a fixed two-line height (via a hidden two-line reference text) so a
/// one-line title doesn't leave a card shorter than a neighboring two-line one —
/// otherwise the grid centers rows by height and the covers fall out of alignment.
struct ReservedCaption: View {
    let title: String

    var body: some View {
        ZStack(alignment: .top) {
            Text("A\nA").font(.caption).opacity(0).accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    HStack(alignment: .top, spacing: 12) {
        VStack(spacing: 8) {
            CoverTile(systemImage: "music.note", size: 84)
            ReservedCaption(title: "No image")
        }
        VStack(spacing: 8) {
            CoverTile(
                systemImage: "music.note",
                imageURL: URL(string: "https://picsum.photos/seed/miya-redbone/600"),
                size: 84
            )
            ReservedCaption(title: "Redbone")
        }
    }
    .padding()
}
