//
//  StackedCoverCard.swift
//  Miya
//
//  Created by Steven Hurtado on 9/5/26.
//

import ComposableArchitecture
import SwiftUI

/// A section-grid tile for an album: the album's own cover on top of one or two
/// member covers, fanned down and to the right, with the album title below. Same
/// `size × size` footprint and caption as `PreviewCard` so grid rows stay aligned.
struct StackedCoverCard: View {
    struct Cover: Identifiable {
        let id: Int
        let systemImage: String
        var imageURL: URL?
    }

    let title: String
    /// Back-to-front, 1...3 entries (already clamped by `init`).
    let covers: [Cover]
    var size: CGFloat = PreviewCard.cardSize
    var accessibilityText: String?

    var body: some View {
        VStack(spacing: 8) {
            stack
            ReservedCaption(title: title)
        }
        .frame(width: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText ?? "\(title), album"))
    }

    private var stack: some View {
        let layers = Array(covers.prefix(3))
        return ZStack {
            ForEach(Array(layers.enumerated()), id: \.element.id) { index, cover in
                CoverTile(
                    systemImage: cover.systemImage,
                    imageURL: cover.imageURL,
                    size: size * scale(for: layers.count)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(.systemBackground), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                .offset(offset(index: index, count: layers.count))
                .zIndex(Double(index)) // last cover drawn on top
            }
        }
        .frame(width: size, height: size)
        .compositingGroup() // keep the drop shadow inside this cell
    }

    private func scale(for count: Int) -> CGFloat {
        switch count {
        case ...1: 1.0
        case 2: 0.86
        default: 0.78
        }
    }

    private func offset(index: Int, count: Int) -> CGSize {
        switch count {
        case ...1:
            return .zero
        case 2:
            let d = size * 0.07
            return index == 0 ? CGSize(width: -d, height: -d) : CGSize(width: d, height: d)
        default:
            let d = size * 0.11
            switch index {
            case 0: return CGSize(width: -d, height: -d)
            case 1: return .zero
            default: return CGSize(width: d, height: d)
            }
        }
    }
}

extension StackedCoverCard {
    init(album: Album, size: CGFloat = PreviewCard.cardSize) {
        let albumCover = Cover(id: 99, systemImage: album.systemImage, imageURL: album.imageURL)
        let members = album.items
        let covers: [Cover]
        switch members.count {
        case ...1:
            covers = [albumCover]
        case 2:
            covers = [Self.cover(members, 0)].compactMap { $0 } + [albumCover]
        default:
            covers = [Self.cover(members, 0), Self.cover(members, 1)].compactMap { $0 } + [albumCover]
        }
        self.init(
            title: album.title,
            covers: covers,
            size: size,
            accessibilityText: "\(album.title), album, \(members.count) items"
        )
    }

    private static func cover(_ items: IdentifiedArrayOf<HomeSectionItem>, _ i: Int) -> Cover? {
        guard items.indices.contains(i) else { return nil }
        let item = items[i]
        return Cover(id: i, systemImage: item.systemImage, imageURL: item.imageURL)
    }
}

#Preview {
    let threeUp = Album(
        id: "three",
        title: "Album of Three or More",
        subtitle: "Artist",
        systemImage: "square.stack",
        imageURL: URL(string: "https://picsum.photos/seed/miya-album-three/600"),
        items: IdentifiedArray(uniqueElements: (1...4).map { i in
            HomeSectionItem(
                id: "three-\(i)", kind: .song, title: "Track \(i)", subtitle: "Artist",
                systemImage: "music.note", detail: "",
                imageURL: URL(string: "https://picsum.photos/seed/miya-three-\(i)/600")
            )
        })
    )
    let twoUp = Album(
        id: "two",
        title: "Album of Two",
        subtitle: "Artist",
        systemImage: "square.stack",
        imageURL: URL(string: "https://picsum.photos/seed/miya-album-two/600"),
        items: IdentifiedArray(uniqueElements: (1...2).map { i in
            HomeSectionItem(
                id: "two-\(i)", kind: .photo, title: "Photo \(i)", subtitle: "Today",
                systemImage: "photo", detail: "",
                imageURL: URL(string: "https://picsum.photos/seed/miya-two-\(i)/600")
            )
        })
    )
    let empty = Album(
        id: "empty",
        title: "Empty Album",
        subtitle: "Artist",
        systemImage: "square.stack",
        imageURL: URL(string: "https://picsum.photos/seed/miya-album-empty/600"),
        items: []
    )

    return VStack(spacing: 24) {
        HStack(alignment: .top, spacing: 16) {
            StackedCoverCard(album: threeUp)
            StackedCoverCard(album: twoUp)
            StackedCoverCard(album: empty)
        }
        StackedCoverCard(album: threeUp, size: 116)
    }
    .padding()
}
