//
//  Font.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//


import SwiftUI
 
extension Font {
    private static let titleFontName = "Snell Roundhand"
    private static let fontName = "Times New Roman"
    
    static var largeTitle: Font {
        .custom(titleFontName, size: 48)
    }
    
    static var title: Font {
        .custom(titleFontName, size: 36)
    }
    
    static var headline: Font {
        .custom(fontName, size: 24)
    }
    
    static var body: Font {
        .custom(fontName, size: 16)
    }
    
    static var caption: Font {
        .custom(fontName, size: 12)
    }
    
    static func custom(size: CGFloat) -> Font {
        .custom(fontName, size: size)
    }
}
