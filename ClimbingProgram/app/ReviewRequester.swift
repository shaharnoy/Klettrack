//
//  ReviewRequester.swift
//  ClimbingProgram
//
//  Created by Shahar Noy on 17.11.25.
//

import StoreKit

//iOS native review request
enum ReviewRequester {
    static func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
                return
        }
        SKStoreReviewController.requestReview(in: scene)
    }
}
