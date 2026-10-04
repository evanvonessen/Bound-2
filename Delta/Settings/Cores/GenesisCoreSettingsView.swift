//
//  GenesisCoreSettingsView.swift
//  Delta
//
//  Created by Caroline Moore on 8/18/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import SwiftUI

struct GenesisCoreSettingsView: CoreSettingsView
{
    var system: System { .genesis }
    @Environment(\.openURL) var openURL
}

#Preview {
    NavigationView {
        GenesisCoreSettingsView()
    }
}
