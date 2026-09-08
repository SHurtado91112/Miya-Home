//
//  SectionCardGrid.swift
//  Miya
//
//  Created by Steven Hurtado on 9/7/26.
//

import SwiftUI

/// Layout constants for the app's card grids — Home sections and the album /
/// author / section detail screens. Cards are square and render at their natural
/// edge length; the grid fits as many per row as the available width allows and
/// wraps the rest, so a landscape (wider) layout shows more columns than portrait.
enum SectionCardLayout {
    /// The gap between two cards in a row stays within this range: never tighter
    /// than the lower bound, and up to the upper bound as a row's leftover space
    /// is spread between its cards.
    static let itemGapRange: ClosedRange<CGFloat> = 4...8

    /// A `GridItem` whose columns wrap based on the width the grid is actually
    /// given each layout pass — no geometry measurement, so it re-lays-out
    /// correctly on every rotation (and inside a reusing `List` cell).
    ///
    /// Columns are `naturalSize`, allowed to stretch by up to the width of the
    /// gap range so a row's slack is absorbed evenly; the fixed-size card is
    /// centred in each column, which reads as a gap that flexes across
    /// `itemGapRange` and widens on roomier screens.
    static func column(naturalSize: CGFloat) -> GridItem {
        let flex = itemGapRange.upperBound - itemGapRange.lowerBound
        return GridItem(
            .adaptive(minimum: naturalSize, maximum: naturalSize + flex),
            spacing: itemGapRange.lowerBound,
            alignment: .center
        )
    }
}

/// A wrapping grid of square section cards that adapts to the width it is given:
/// `content` is handed the card edge length to pass to each `PreviewCard` /
/// `StackedCoverCard` / `MoreCard` it builds. More cards fit per row on wider
/// (landscape) layouts; the gap between them flexes to keep each row justified.
struct SectionCardGrid<Content: View>: View {
    /// The square card edge length.
    var naturalCardSize: CGFloat
    /// Vertical gap between rows.
    var rowSpacing: CGFloat = 16
    @ViewBuilder var content: (_ cardSize: CGFloat) -> Content

    var body: some View {
        LazyVGrid(
            columns: [SectionCardLayout.column(naturalSize: naturalCardSize)],
            spacing: rowSpacing
        ) {
            content(naturalCardSize)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 32) {
            ForEach([844.0, 390.0, 320.0, 260.0, 200.0], id: \.self) { width in
                VStack(alignment: .leading, spacing: 8) {
                    Text("width \(Int(width))").font(.caption).foregroundStyle(.secondary)
                    SectionCardGrid(naturalCardSize: PreviewCard.cardSize) { cardSize in
                        ForEach(0..<5) { index in
                            PreviewCard(
                                title: "Item \(index)",
                                systemImage: "music.note",
                                size: cardSize
                            )
                        }
                        MoreCard(size: cardSize)
                    }
                    .frame(width: width)
                    .border(.quaternary)
                }
            }
        }
        .padding()
    }
}
