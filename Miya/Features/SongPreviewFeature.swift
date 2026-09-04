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
    /// The collapsed "mini player" detent — tall enough for artwork, title, and transport controls.
    static let miniDetent: PresentationDetent = .height(88)

    @ObservableState
    struct State: Equatable, Identifiable {
        var item: HomeSectionItem
        var isPlaying = false
        var detent: PresentationDetent = .large
        var id: HomeSectionItem.ID { item.id }
    }

    enum Action: ViewAction, BindableAction {
        enum View {
            case closeTapped
            case playPauseTapped
            case expandTapped
        }
        case view(View)
        case binding(BindingAction<State>)
    }

    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .view(.closeTapped):
                return .run { _ in await dismiss() }

            case .view(.playPauseTapped):
                state.isPlaying.toggle()
                return .none

            case .view(.expandTapped):
                state.detent = .large
                return .none

            case .binding:
                return .none
            }
        }
    }
}

@ViewAction(for: SongPreviewFeature.self)
struct SongPreviewView: View {
    @Bindable var store: StoreOf<SongPreviewFeature>

    var body: some View {
        Group {
            if store.detent == .large {
                fullPlayer
            } else {
                miniPlayer
            }
        }
        .presentationDetents([SongPreviewFeature.miniDetent, .large], selection: $store.detent)
        .presentationBackgroundInteraction(.enabled(upThrough: SongPreviewFeature.miniDetent))
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)
    }

    private var fullPlayer: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 24)

            artwork(size: 320, cornerRadius: 16)
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
    }

    private var miniPlayer: some View {
        HStack(spacing: 12) {
            artwork(size: 44, cornerRadius: 6)

            Text(store.item.title)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Button { send(.playPauseTapped) } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button { send(.closeTapped) } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { send(.expandTapped) }
    }

    private func artwork(size: CGFloat, cornerRadius: CGFloat) -> some View {
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
                        artworkGlyph(size: size)
                    @unknown default:
                        artworkGlyph(size: size)
                    }
                }
            } else {
                artworkGlyph(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func artworkGlyph(size: CGFloat) -> some View {
        Image(systemName: store.item.systemImage)
            .font(.system(size: size * 0.2))
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
