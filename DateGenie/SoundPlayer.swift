//  SoundPlayer.swift
//  DateGenie
//  Simple helper to play a system sound when points are awarded.

import Foundation
import AudioToolbox

final class SoundPlayer {
    static let shared = SoundPlayer()
    private init() {}
    
    func playSuccess() {
        // 1102 = ReceivedMessage, pick pleasant short sound
        AudioServicesPlaySystemSound(1102)
    }
}
