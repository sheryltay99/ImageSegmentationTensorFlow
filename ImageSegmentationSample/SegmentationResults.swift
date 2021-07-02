//  SegmentationResults.swift
//  TissueAI
//
//  Copyright © 2021 Tetsuyu Healthcare. All rights reserved.
//

import UIKit

/// Segmentation results for default mask and confidence mask.
struct SegmentationResults {
    
    var originalImage: UIImage
    var segmentedImage: UIImage
    var overlayImage: UIImage
    var colorLegend: [String: UIColor]
    var confidenceSegmentedImage: UIImage
    var confidenceOverlayImage: UIImage
    var confidenceColorLegend: [String: UIColor]
}
