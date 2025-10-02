//
//  RunOnce.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import Foundation

func runOnce(per key: String, _ work: () -> Void) {
    let k = "once.\(key)"
    if !UserDefaults.standard.bool(forKey: k) {
        work()
        UserDefaults.standard.set(true, forKey: k)
    }
}
#if DEBUG
// DevTools.nukeAndReseed(context)  // uncomment to reset locally, then comment back
#endif
