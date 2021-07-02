//  SegmentationError.swift
//  TissueAI
//
//  Copyright © 2021 Tetsuyu Healthcare. All rights reserved.
//

import UIKit

/// Container for errors that occur when parsing output from inference result of model.
enum SegmentationError: Error {
    
    case invalidImage
    case invalidPixelData
    case internalError(Error)
    case coreMLError
}
