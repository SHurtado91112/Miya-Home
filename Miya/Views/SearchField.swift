//
//  SearchField.swift
//  Miya
//
//  The editable serif search field shown on the section / author detail lists.
//  Focus is owned by the parent (via an injected `FocusState.Binding`) so the
//  reducer can request focus when the screen is pushed from a search bar.
//

import SwiftUI

struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .font(.body)
                .focused(isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .lineLimit(1)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SearchFieldPreview: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        SearchField(text: $text, placeholder: "Search Music", isFocused: $focused)
            .padding()
    }
}

#Preview {
    SearchFieldPreview()
}
