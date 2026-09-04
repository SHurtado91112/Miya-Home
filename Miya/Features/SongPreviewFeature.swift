//
//  SongPreviewFeature.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct SongPreviewFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var item: HomeSectionItem
        var isPlaying = false
        var id: HomeSectionItem.ID { item.id }
    }

    enum Action: ViewAction {
        enum View {
            case closeTapped
            case playPauseTapped
        }
        case view(View)
    }

    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.closeTapped):
                return .run { _ in await dismiss() }

            case .view(.playPauseTapped):
                state.isPlaying.toggle()
                return .none
            }
        }
    }
}

@ViewAction(for: SongPreviewFeature.self)
struct SongPreviewView: View {
    let store: StoreOf<SongPreviewFeature>

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 24)

            artwork
                .frame(maxWidth: 320)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                .padding(.horizontal, 32)

            VStack(spacing: 4) {
                Text(store.item.title)
                    .font(.title)
                    .multilineTextAlignment(.center)
                Text(store.item.subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.horizontal, 32)

            scrubber
                .padding(.top, 28)
                .padding(.horizontal, 32)

            transport
                .padding(.top, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Button { send(.closeTapped) } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
            .buttonStyle(.plain)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var artwork: some View {
        ZStack {
            Color(.systemGray5)
            if let url = store.item.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .failure:
                        artworkGlyph
                    @unknown default:
                        artworkGlyph
                    }
                }
            } else {
                artworkGlyph
            }
        }
    }

    private var artworkGlyph: some View {
        Image(systemName: store.item.systemImage)
            .font(.system(size: 64))
            .foregroundStyle(.secondary)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(value: .constant(0.3))
                .disabled(true)
                .tint(.primary)
            HStack {
                Text("0:52")
                Spacer()
                Text("-2:14")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var transport: some View {
        HStack(spacing: 48) {
            Image(systemName: "backward.fill")
                .font(.title)
                .foregroundStyle(.secondary)

            Button { send(.playPauseTapped) } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.primary)
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)

            Image(systemName: "forward.fill")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SongPreviewView(
                store: Store(
                    initialState: SongPreviewFeature.State(item: HomeSection.mocks[0].items[0])
                ) {
                    SongPreviewFeature()
                }
            )
        }
}
