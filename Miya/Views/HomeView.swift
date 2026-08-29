//
//  HomeView.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import SwiftUI

struct HomeView: View {
    let model: HomeModel
    
    var body: some View {
        List {
            // Header
            Text(model.title).font(.largeTitle).listRowSeparator(.hidden)
            
            // Sections
            ForEach(model.sections) { section in
                Section(section.title) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: PreviewCard.cardSize))]) {
                        ForEach(section.items) { item in
                            PreviewCard(text: "Hello")
                        }
                    }
                }.font(.headline).textCase(nil).listRowSeparator(.hidden)
            }
        }.listStyle(.grouped).scrollContentBackground(.hidden).listSectionSpacing(32).padding(16).scrollClipDisabled()
    }
}
