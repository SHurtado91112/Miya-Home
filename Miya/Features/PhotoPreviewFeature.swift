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
    @ObservableState
    struct State: Equatable, Identifiable {
        var item: HomeSectionItem
        var showsMetadata = false
        var id: HomeSectionItem.ID { item.id }
    }

    enum Action: ViewAction {
        enum View {
            case closeTapped
            case toggleMetadataTapped
        }
        case view(View)
    }

    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.closeTapped):
                return .run { _ in await dismiss() }

            case .view(.toggleMetadataTapped):
                state.showsMetadata.toggle()
                return .none
            }
        }
    }
}

@ViewAction(for: PhotoPreviewFeature.self)
struct PhotoPreviewView: View {
    let store: StoreOf<PhotoPreviewFeature>

    private static let maxScale: CGFloat = 4
    private static let doubleTapScale: CGFloat = 2.5

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    var body: some View {
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
        .fullScreenCover(isPresented: .constant(true)) {
            PhotoPreviewView(
                store: Store(
                    initialState: PhotoPreviewFeature.State(item: HomeSection.mocks[1].items[0])
                ) {
                    PhotoPreviewFeature()
                }
            )
        }
}
