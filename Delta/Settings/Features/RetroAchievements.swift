//
//  RetroAchievements.swift
//  Delta
//
//  Created by Riley Testut on 3/3/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import DeltaFeatures

struct RetroAchievementsOptions
{
    @Option(name: "Hardcore Mode", description: "Disables features that could provide an unfair advantage, such as cheats and save states.")
    var isHardcoreModeEnabled: Bool = true
}
