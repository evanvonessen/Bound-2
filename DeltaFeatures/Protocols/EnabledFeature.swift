//
//  EnabledFeature.swift
//  Delta
//
//  Created by Riley Testut on 7/2/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation
import Combine

// EnabledFeatures are AnyFeatures that can be explicitly enabled/disabled.
public protocol EnabledFeature: AnyFeature
{
    var isEnabled: Bool { get set }
}

public extension EnabledFeature
{
    var isEnabled: Bool {
        get {
            let isEnabled = UserDefaults.standard.bool(forKey: self.key)
            return isEnabled
        }
        set {
            (self.objectWillChange as? ObservableObjectPublisher)?.send()
            UserDefaults.standard.set(newValue, forKey: self.key)
            
            NotificationCenter.default.post(name: .settingsDidChange, object: nil, userInfo: [SettingsUserInfoKey.name: self.settingsKey, SettingsUserInfoKey.value: newValue])
        }
    }
}
