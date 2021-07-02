//
//  TissueLabelType.swift
//  TissueAI
//
//  Copyright © 2021 Tetsuyu Healthcare. All rights reserved.
//

import Foundation
import UIKit

/// Tissue Label
enum TissueLabelType: String, CaseIterable {
    
    /// Unhealthy Skin in wound
    case unhealthySkin = "Unhealthy Skin"
    
    /// Healthy Skin in wound
    case healthySkin = "Healthy Skin"
    
    /// Epithelising tissue in the wound
    case epithelising = "Epithelising"
    
    /// Healthy Granulation in wound
    case healthyGranulation = "Healthy Granulation"
    
    /// Unhealthy Granulation in wound
    case unhealthyGranulation = "Unhealthy Granulation"
    
    /// Slough tissue in wound
    case slough = "Slough"
    
    /// Necrosis tissue in wound
    case necrosis = "Necrosis"
    
    /// Muscle in wound
    case muscle = "Muscle"
    
    /// Tendon in wound
    case tendon = "Tendon"
    
    /// Fascia in wound
    case fascia = "Fascia"
    
    /// Bone in wound
    case bone = "Bone"
    
    /// Other (undefined tissues) in the wound bed
    case others = "Others"
    
    /// Annotation or Reference Color
    var color: UIColor {
        switch self {
        case .unhealthySkin:
            return #colorLiteral(red: 0.1176470588, green: 0.2862745098, blue: 0.1568627451, alpha: 1)
            
        case .healthySkin:
            return #colorLiteral(red: 0.9137254902, green: 0.5098039216, blue: 0.6980392157, alpha: 1)
        
        case .epithelising:
            return #colorLiteral(red: 1, green: 0.07843137255, blue: 0.5764705882, alpha: 1)
            
        case .healthyGranulation:
            return #colorLiteral(red: 0, green: 0.968627451, blue: 0.4470588235, alpha: 1)
            
        case .unhealthyGranulation:
            return #colorLiteral(red: 0.05098039216, green: 0.8784313725, blue: 0.8980392157, alpha: 1)
            
        case .slough:
            return #colorLiteral(red: 1, green: 1, blue: 0, alpha: 1)
        
        case .necrosis:
            return #colorLiteral(red: 0.6666666667, green: 0.431372549, blue: 0.1568627451, alpha: 1)
            
        case .muscle:
            return #colorLiteral(red: 0.7019607843, green: 0.1529411765, blue: 0.2431372549, alpha: 1)
            
        case .tendon:
            return #colorLiteral(red: 0.8392156863, green: 0.737254902, blue: 0.4039215686, alpha: 1)
            
        case .fascia:
            return #colorLiteral(red: 0.5647058824, green: 0.4980392157, blue: 0.9137254902, alpha: 1)
            
        case .bone:
            return #colorLiteral(red: 0.8862745098, green: 0.8862745098, blue: 0.7254901961, alpha: 1)
            
        case .others:
            return #colorLiteral(red: 0.1176470588, green: 0.5647058824, blue: 1, alpha: 1)
        }
    }
    
    /// Annotation or Reference Color in Uint32 format
    var colorAsUint: UInt32 {
        return self.color.asUInt32
    }
    
    /// Localised String of Tissue Labels
    var localisedText: String {
        return NSLocalizedString(self.rawValue, comment: "")
    }
}
