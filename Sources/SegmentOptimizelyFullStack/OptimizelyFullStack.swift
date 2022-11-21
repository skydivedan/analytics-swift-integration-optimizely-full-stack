//
//  OptimizelyFullStackDestination.swift
//  OptimizelyFullStackDestination
//
//  Created by Komal Dhingra on 11/15/22.
//

// NOTE: You can see this plugin in use in the DestinationsExample application.
//
// This plugin is NOT SUPPORTED by Segment.  It is here merely as an example,
// and for your convenience should you find it useful.
//

// MIT License
//
// Copyright (c) 2021 Segment
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import Segment
import Optimizely

public class OptimizelyFullStack: DestinationPlugin {
    public let timeline = Timeline()
    public let type = PluginType.destination
    public let key = "OptimizelyFullStack"
    public var analytics: Analytics? = nil

    private var optimizelySettings: OptimizelySettings?
    
    var optimizelyClient: OptimizelyClient!
    var userId: String!
    var userTraits: [String: Any]!
    let defaultLogLevel: OptimizelyLogLevel? = .debug
        
    public init() { }
    
    public func update(settings: Settings, type: UpdateType) {
        // Skip if you have a singleton and don't want to keep updating via settings.
        guard type == .initial else { return }
   
        guard let tempSettings: OptimizelySettings = settings.integrationSettings(forPlugin: self) else { return }
        optimizelySettings = tempSettings
    
        initializeOptimizelySDKAsynchronous()
                
    }
    
    private func initializeOptimizelySDKAsynchronous() {
        optimizelyClient = OptimizelyClient(sdkKey: optimizelySettings?.apiKey ?? "", defaultLogLevel: defaultLogLevel)
        debugPrint("optimizelySettings", optimizelySettings?.apiKey ?? "")
        
        addNotificationListeners()
        
        optimizelyClient.start { result in
            switch result {
            case .failure(let error):
                print("Optimizely SDK initiliazation failed: \(error)")
            case .success:
                print("Optimizely SDK initialized successfully!")
            }
        }
    }
    
    func addNotificationListeners() {
        // notification listeners
        let notificationCenter = optimizelyClient.notificationCenter!
        
        _ = notificationCenter.addDecisionNotificationListener(decisionListener: { (type, userId, attributes, decisionInfo) in
            print("Received decision notification: \(type) \(userId) \(String(describing: attributes)) \(decisionInfo)")
        })
        
        _ = notificationCenter.addTrackNotificationListener(trackListener: { (eventKey, userId, attributes, eventTags, event) in
            print("Received track notification: \(eventKey) \(userId) \(String(describing: attributes)) \(String(describing: eventTags)) \(event)")
        })
        
        _ = notificationCenter.addDatafileChangeNotificationListener(datafileListener: { _ in
            print("Datafile changed")

            if let optConfig = try? self.optimizelyClient.getOptimizelyConfig() {
                print("[OptimizelyConfig] revision = \(optConfig.revision)")
            }
        })
        
        
        _ = optimizelyClient.notificationCenter?.addActivateNotificationListener(activateListener: { experiment, userId, attributes, variation, event in
            print("experiment", experiment)
            print("variation", variation)
            let properties: [String: Any] = ["experimentId": experiment["experimentId"] ?? "",
                        "experimentName": experiment["experimentKey"] ?? "",
                        "variationId": variation["variationId"] ?? "",
                        "variationName": variation["variationKey"] ?? ""
                        
            ]
            self.analytics?.track(name: "Experiment Viewed", properties: properties)
        })

    }
    
    public func identify(event: IdentifyEvent) -> IdentifyEvent? {
        
        if let userProp = event.traits?.dictionaryValue {
            userTraits = userProp
        }
        
        if let currentUserId = event.userId {
            userId = currentUserId
        }
        return event
    }
    
    public func track(event: TrackEvent) -> TrackEvent? {
        
        let returnEvent = event
        let trackKnownUsers = optimizelySettings?.trackKnownUsers
        if userId == nil && (trackKnownUsers != nil && trackKnownUsers == true) {
            print("Segment will only track users associated with a userId when the trackKnownUsers setting is enabled.")
        }
        
        if trackKnownUsers == true {
            if userTraits != nil {
                do {
                    try optimizelyClient.track(eventKey: returnEvent.event,
                                                userId: userId,
                                                attributes: userTraits,
                                               eventTags: event.properties?.dictionaryValue)
                    print("[track]")
                } catch {
                    print(error)
                }
                
            }
            else {
                try? optimizelyClient.track(eventKey: returnEvent.event,
                                       userId: userId,
                                       eventTags: event.properties?.dictionaryValue)
            }
        }
        
        if let anonymousId = returnEvent.anonymousId, anonymousId.count > 0 {
            if (trackKnownUsers == false && userTraits != nil) {
                do {
                    try optimizelyClient.track(eventKey: returnEvent.event,
                                                userId: anonymousId,
                                                attributes: userTraits,
                                               eventTags: event.properties?.dictionaryValue)
                    print("track anonymousUser")
                } catch {
                    print(error)
                }
            } else {
                try? optimizelyClient.track(eventKey: returnEvent.event,
                                       userId: userId,
                                       eventTags: event.properties?.dictionaryValue)
            }
        }
        
        return returnEvent
    }
    
    public func reset() {
        if optimizelyClient == nil {
            return
        }
        else {
            optimizelyClient.notificationCenter?.clearAllNotificationListeners()
        }
    }
    
    @objc private func experimentDidGetViewed(notification: NSNotification){
        
    }
}

extension OptimizelyFullStack: VersionedPlugin {
    public static func version() -> String {
        return __destination_version
    }
}

private struct OptimizelySettings: Codable {
    let apiKey: String
    let periodicDownloadInterval: Int?
    let trackKnownUsers: Bool
}
