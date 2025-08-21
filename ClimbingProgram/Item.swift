//
//  Item.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
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
