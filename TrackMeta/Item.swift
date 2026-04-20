//
//  Item.swift
//  TrackMeta
//
//  Created by Tobias Pottier on 20/04/2026.
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
