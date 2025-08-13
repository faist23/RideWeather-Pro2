//
//  Item.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/12/25.
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
