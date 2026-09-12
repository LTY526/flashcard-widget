//
//  Item.swift
//  flashcard-widget
//
//  Created by User on 9/12/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
