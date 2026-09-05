//
//  AuthorRow.swift
//  Miya
//
//  Shown above filtered results when a search query matches an author's name:
//  a profile affordance that opens a list of only that author's items.
//

import SwiftUI

struct AuthorRow: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), author")
        .accessibilityHint("Shows all items by \(name)")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    VStack(spacing: 12) {
        AuthorRow(name: "Radiohead") {}
        AuthorRow(name: "Steven Hurtado") {}
    }
    .padding()
}
