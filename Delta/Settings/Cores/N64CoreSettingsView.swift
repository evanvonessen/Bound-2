//
//  N64CoreSettingsView.swift
//  Delta
//
//  Created by Caroline Moore on 8/18/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import SwiftUI

struct N64CoreSettingsView: CoreSettingsView
{
    var system: System { .n64 }
    @Environment(\.openURL) var openURL
}

#Preview {
    NavigationView {
        N64CoreSettingsView()
    }
}
