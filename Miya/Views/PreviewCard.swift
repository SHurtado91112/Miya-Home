//
//  PreviewCard.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import SwiftUI


struct PreviewCard: View {
    static let cardSize = 84.0

    let text: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(text)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(width: Self.cardSize, height: Self.cardSize, alignment: .center)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}
