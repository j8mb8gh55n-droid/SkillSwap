//
//  SupabaseManager.swift
//  SkillSwap
//
//  Created by mac on 07/05/1448 AH.
//

//
//  SupabaseManager.swift
//  SkillSwap
//

import Foundation
import Supabase


enum SupabaseManager {

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = 30
        #if DEBUG
        return URLSession(configuration: configuration, delegate: AuthDiagnosticsSessionDelegate(), delegateQueue: nil)
        #else
        return URLSession(configuration: configuration)
        #endif
    }()

    static let client = SupabaseClient(
        supabaseURL: URL(
            string: "https://ilszwmkqccdqrlyroeye.supabase.co"
        )!,
        supabaseKey: "sb_publishable_15g2YvWOH2X1soId69Wgyg_G9ka0Qx6",
        options: SupabaseClientOptions(global: .init(session: session))
    )
}
