//
//  SearchBarButton.swift
//  Miya
//
//  A non-editable, tappable search affordance for the Home section headers.
//  Looks like a search field but acts as a button: tapping it navigates to the
//  section's detail list, where a real `SearchField` takes focus.
//

import SwiftUI

struct SearchBarButton: View {
    let placeholder: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(placeholder)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(placeholder)
        .accessibilityHint("Opens the list with the keyboard focused")
        .accessibilityAddTraits([.isSearchField, .isButton])
    }
}

#Preview {
    VStack(spacing: 16) {
        SearchBarButton(placeholder: "Search Music") {}
        SearchBarButton(placeholder: "Search Photos") {}
    }
    .padding()
}
