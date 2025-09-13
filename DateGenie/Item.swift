//
//  Item.swift
//  DateGenie
//
//  Created by VICTOR EDOCHIE on 7/16/25.
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
