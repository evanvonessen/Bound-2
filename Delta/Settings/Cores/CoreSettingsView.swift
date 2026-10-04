//
//  CoreSettingsView.swift
//  Delta
//
//  Created by Caroline Moore on 8/15/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import SwiftUI
import DeltaCore

protocol CoreSettingsView: View
{
    var system: System { get }
    
    associatedtype AdditionalSections: View
    var additionalSections: AdditionalSections { get }
    
    var openURL: OpenURLAction { get }
    
    init()
}

extension CoreSettingsView
{
    var body: some View {
        Form {
            Section {
                if let metadata = system.deltaCore.metadata
                {
                    ForEach(DeltaCoreMetadata.Key.allCases, id: \.self) { key in
                        if let item = metadata[key]
                        {
                            HStack {
                                Text(key.localizedName)
                                Spacer()
                                if let url = item.url
                                {
                                    Button(action: { openURL(url) }) {
                                        NavigationLink(destination: EmptyView()) {
                                            Text(item.value)
                                                .multilineTextAlignment(.trailing)
                                                .frame(maxWidth: .infinity, alignment: .trailing)
                                                .foregroundStyle(Color(.secondaryLabel))
                                        }
                                    }
                                }
                                else
                                {
                                    Text(item.value)
                                        .foregroundStyle(Color(.secondaryLabel))
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Core Info")
            }
            additionalSections
        }
        .navigationTitle(system.localizedName)
    }
    
    var additionalSections: some View { EmptyView() }
}

extension CoreSettingsView
{
    static func makeViewController() -> UIHostingController<some View>
    {
        let settingsView = Self()
        
        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.navigationItem.largeTitleDisplayMode = .never
        hostingController.navigationItem.title = settingsView.system.localizedName
        
        return hostingController
    }
}

