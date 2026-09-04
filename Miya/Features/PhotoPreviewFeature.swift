//
//  PhotoPreviewFeature.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct PhotoPreviewFeature {
    /// Height of the collapsed "mini" bar — thumbnail and title only.
    static let miniPlayerHeight: CGFloat = 88
    /// The collapsed mini-bar detent.
    static let miniDetent: PresentationDetent = .height(miniPlayerHeight)

    @ObservableState
    struct State: Equatable, Identifiable {
        var item: HomeSectionItem
        var showsMetadata = false
        var detent: PresentationDetent = .large
        var id: HomeSectionItem.ID { item.id }
    }

    enum Action: ViewAction, BindableAction {
        enum View {
            case closeTapped
            case toggleMetadataTapped
            case viewAlbumTapped
            case expandTapped
        }
        enum Delegate: Equatable {
            case viewAlbumTapped(albumID: Album.ID)
        }
        case view(View)
        case binding(BindingAction<State>)
        case delegate(Delegate)
    }

    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .view(.closeTapped):
                return .run { _ in await dismiss() }

            case .view(.toggleMetadataTapped):
                state.showsMetadata.toggle()
                return .none

            case .view(.viewAlbumTapped):
                guard let albumID = state.item.albumID else { return .none }
                return .send(.delegate(.viewAlbumTapped(albumID: albumID)))

            case .view(.expandTapped):
                state.detent = .large
                return .none

            case .binding, .delegate:
                return .none
            }
        }
    }
}

@ViewAction(for: PhotoPreviewFeature.self)
struct PhotoPreviewView: View {
    @Bindable var store: StoreOf<PhotoPreviewFeature>

    private static let maxScale: CGFloat = 4
    private static let doubleTapScale: CGFloat = 2.5

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        Group {
            if store.detent == .large {
                fullPhoto
            } else {
                miniPhoto
            }
        }
        .presentationDetents([PhotoPreviewFeature.miniDetent, .large], selection: $store.detent)
        .presentationBackgroundInteraction(.enabled(upThrough: PhotoPreviewFeature.miniDetent))
        .presentationDragIndicator(.hidden)
    }

    private var fullPhoto: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            image
                .scaleEffect(scale * pinch)
                .offset(x: offset.width + drag.width, y: offset.height + drag.height)
                .gesture(magnification)
                .simultaneousGesture(panning)
                .onTapGesture(count: 2) { toggleZoom() }
                .animation(.spring(duration: 0.3), value: scale)
                .animation(.spring(duration: 0.3), value: offset)

            chrome

            if store.showsMetadata {
                metadata
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusBarHidden()
        .animation(.snappy, value: store.showsMetadata)
    }

    private var miniPhoto: some View {
        HStack(spacing: 12) {
            thumbnail(size: 44, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.item.title)
                    .font(.body)
                    .lineLimit(1)
                Text(store.item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

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

    private var image: some View {
        ZStack {
            if let url = store.item.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case let .success(image):
                        image.resizable().scaledToFit()
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
    }

    private var glyph: some View {
        Image(systemName: store.item.systemImage)
            .font(.system(size: 72))
            .foregroundStyle(.white.opacity(0.6))
    }

    private func thumbnail(size: CGFloat, cornerRadius: CGFloat) -> some View {
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
                        thumbnailGlyph(size: size)
                    @unknown default:
                        thumbnailGlyph(size: size)
                    }
                }
            } else {
                thumbnailGlyph(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func thumbnailGlyph(size: CGFloat) -> some View {
        Image(systemName: store.item.systemImage)
            .font(.system(size: size * 0.3))
            .foregroundStyle(.secondary)
    }

    private var chrome: some View {
        VStack {
            HStack {
                iconButton("xmark") { send(.closeTapped) }
                Spacer()
                iconButton("info.circle") { send(.toggleMetadataTapped) }
            }
            Spacer()
        }
        .padding(16)
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.title2)
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.35), in: Circle())
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.item.title).font(.headline)
            Text(store.item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(store.item.detail)
                .font(.body)
                .foregroundStyle(.secondary)
            if store.item.albumID != nil {
                Button("View Album") { send(.viewAlbumTapped) }
                    .font(.body)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .environment(\.colorScheme, .dark)
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                scale = min(max(scale * value.magnification, 1), Self.maxScale)
                if scale <= 1 { offset = .zero }
            }
    }

    private var panning: some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in
                guard scale > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard scale > 1 else { return }
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private func toggleZoom() {
        if scale > 1 {
            scale = 1
            offset = .zero
        } else {
            scale = Self.doubleTapScale
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            PhotoPreviewView(
                store: Store(
                    initialState: PhotoPreviewFeature.State(item: HomeSection.mocks[1].items[0])
                ) {
                    PhotoPreviewFeature()
                }
            )
        }
}
