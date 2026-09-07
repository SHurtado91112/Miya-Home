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
            case authorTapped(AuthorRef)
            case expandTapped
        }
        enum Delegate: Equatable {
            case viewAlbumTapped(albumID: Album.ID)
            case authorTapped(AuthorRef)
            /// The user dismissed this preview from its mini bar or the close button.
            case closed
        }
        case view(View)
        case binding(BindingAction<State>)
        case delegate(Delegate)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .view(.closeTapped):
                return .send(.delegate(.closed))

            case .view(.toggleMetadataTapped):
                state.showsMetadata.toggle()
                return .none

            case .view(.viewAlbumTapped):
                guard let albumID = state.item.albumID else { return .none }
                return .send(.delegate(.viewAlbumTapped(albumID: albumID)))

            case let .view(.authorTapped(ref)):
                return .send(.delegate(.authorTapped(ref)))

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

    private var miniPhoto: some View { PhotoMiniBar(store: store) }

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
            if let author = store.item.author {
                Button("By \(author.name)") { send(.authorTapped(author)) }
                    .font(.body)
                    .padding(.top, 4)
                    .accessibilityHint("Shows all items by \(author.name)")
            }
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

/// The collapsed photo bar — thumbnail, title/subtitle, close. Used inside the
/// preview sheet and, when a song preview is also open, as a docked bar in
/// `MediaPreviewView`.
@ViewAction(for: PhotoPreviewFeature.self)
struct PhotoMiniBar: View {
    let store: StoreOf<PhotoPreviewFeature>

    var body: some View {
        HStack(spacing: 12) {
            CoverTile(
                systemImage: store.item.systemImage,
                imageURL: store.item.smallImageURL,
                size: 44,
                cornerRadius: 6
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(store.item.title)
                    .font(.body)
                    .lineLimit(1)
                Text(store.item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button { send(.closeTapped) } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close photo preview")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { send(.expandTapped) }
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
