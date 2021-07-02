//  ModelOutput.swift
//  TissueAI
//
//  Copyright © 2021 Tetsuyu Healthcare. All rights reserved.
//

import UIKit

/// Protocol to get output value from model
protocol ModelOutput {
    var firstIter: Int { get }
    var secondIter: Int { get }
    func getValue(firstIterIndex: Int, secondIterIndex: Int, classIndex: Int) -> Float32?
}
