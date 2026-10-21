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

    static let client = SupabaseClient(
        supabaseURL: URL(
            string: "https://ilszwmkqccdqrlyroeye.supabase.co"
        )!,
        supabaseKey: "sb_publishable_15g2YvWOH2X1soId69Wgyg_G9ka0Qx6"
    )
}
