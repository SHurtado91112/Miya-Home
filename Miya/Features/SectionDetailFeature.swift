//
//  SectionDetailFeature.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct SectionDetailFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var section: HomeSection
        var id: HomeSection.ID { section.id }
    }

    enum Action {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}

struct SectionDetailView: View {
    let store: StoreOf<SectionDetailFeature>

    var body: some View {
        List {
            // Header — matches HomeView's in-list large title
            Text(store.section.title).font(.largeTitle).listRowSeparator(.hidden)

            ForEach(store.section.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: item.systemImage)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text(item.title).font(.headline)
                    }
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.grouped)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(32)
        .padding(16)
        .scrollClipDisabled()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .serifBackButton()
    }
}

#Preview {
    NavigationStack {
        SectionDetailView(
            store: Store(
                initialState: SectionDetailFeature.State(section: HomeSection.mocks[0])
            ) {
                SectionDetailFeature()
            }
        )
    }
}
