//
//  SectionCardGrid.swift
//  Miya
//
//  Created by Steven Hurtado on 9/7/26.
//

import SwiftUI

/// Layout math for the app's justified three-column card grids — Home sections and
/// the album / author / section detail screens. Cards are square and render at a
/// natural edge length when there is room; on narrow layouts they shrink just
/// enough to keep at least `minItemGap` points between neighbours.
enum SectionCardLayout {
    /// The grid is always exactly this many columns wide.
    static let columnCount = 3

    /// The smallest horizontal gap allowed between two cards in a row. Cards shrink
    /// below their natural size rather than let the gap fall under this.
    static let minItemGap: CGFloat = 2

    /// The card edge length for a row `containerWidth` points wide: never larger
    /// than `naturalSize`, and never so large that `columnCount` cards plus the
    /// `minItemGap` gaps between them overflow the row. Falls back to `naturalSize`
    /// until a real width has been measured.
    static func cardSize(containerWidth: CGFloat, naturalSize: CGFloat) -> CGFloat {
        guard containerWidth > 0 else { return naturalSize }
        let totalGap = CGFloat(columnCount - 1) * minItemGap
        let maxSize = (containerWidth - totalGap) / CGFloat(columnCount)
        return min(naturalSize, max(0, maxSize))
    }

    /// `columnCount` flexible columns separated by `minItemGap`. Whatever width is
    /// left once the cards are placed is taken up by the leading / center / trailing
    /// alignments, so the row stays justified edge-to-edge with equal gaps that
    /// grow on wider screens.
    static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: minItemGap, alignment: .leading),
        GridItem(.flexible(), spacing: minItemGap, alignment: .center),
        GridItem(.flexible(), spacing: minItemGap, alignment: .trailing),
    ]
}

/// A justified three-column grid of square section cards that adapts to the width
/// it is given: `content` is handed the resolved card edge length to pass to each
/// `PreviewCard` / `StackedCoverCard` / `MoreCard` it builds. On roomy layouts the
/// cards render at `naturalCardSize`; on narrow ones they shrink so at least
/// `SectionCardLayout.minItemGap` always sits between them.
struct SectionCardGrid<Content: View>: View {
    /// The card edge length to use whenever the row is wide enough for it.
    var naturalCardSize: CGFloat
    /// Vertical gap between rows.
    var rowSpacing: CGFloat = 16
    @ViewBuilder var content: (_ cardSize: CGFloat) -> Content

    @State private var containerWidth: CGFloat = 0

    private var cardSize: CGFloat {
        SectionCardLayout.cardSize(
            containerWidth: containerWidth,
            naturalSize: naturalCardSize
        )
    }

    var body: some View {
        LazyVGrid(columns: SectionCardLayout.columns, spacing: rowSpacing) {
            content(cardSize)
        }
        // `onGeometryChange` (not `onPreferenceChange`) so the callback isn't
        // `@Sendable`: it runs on the main actor and can mutate `@State` safely.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            containerWidth = newWidth
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 32) {
            ForEach([390.0, 320.0, 260.0, 200.0], id: \.self) { width in
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
