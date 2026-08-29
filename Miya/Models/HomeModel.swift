//
//  HomeModel.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import SwiftUI

@Observable class HomeModel {
    var sections: [HomeSection]
    let title: String
    
    init(title: String) {
        self.title = title
        self.sections = [
            HomeSection(id: 0, title: "Music", items: [
                HomeSectionItem(id: 0, data: Data(), metaData: [:]),
                HomeSectionItem(id: 1, data: Data(), metaData: [:]),
                HomeSectionItem(id: 2, data: Data(), metaData: [:]),
                HomeSectionItem(id: 3, data: Data(), metaData: [:]),
                HomeSectionItem(id: 4, data: Data(), metaData: [:]),
            ]),
            HomeSection(id: 1, title: "Photos", items: [
                HomeSectionItem(id: 0, data: Data(), metaData: [:]),
                HomeSectionItem(id: 1, data: Data(), metaData: [:]),
                HomeSectionItem(id: 2, data: Data(), metaData: [:]),
                HomeSectionItem(id: 3, data: Data(), metaData: [:]),
                HomeSectionItem(id: 4, data: Data(), metaData: [:]),
            ])
        ]
    }
}


protocol Preview {
    var actions: [String] { get }
}

struct HomeSectionItem: Identifiable {
    var id: Int
    var data: Data
    var metaData: Dictionary<String, String>
}

struct HomeSection: Identifiable {
    var id: Int
    var title: String
    var items: [HomeSectionItem]
}
