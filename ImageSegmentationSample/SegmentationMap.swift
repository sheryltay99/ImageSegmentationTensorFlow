//  SegmentationMap.swift
//  TissueAI
//
//  Copyright © 2021 Tetsuyu Healthcare. All rights reserved.
//

import UIKit
import TensorFlowLite
import os.log

/// Container for parsed output from result of model inference.
struct SegmentationMap {
    private var segmentationPixelColor: [UInt32]
    private var classList: Set<Int>
    private var confidenceSegmentationPixelColor: [UInt32]
    private var confidenceClassList: Set<Int>
    
    private let outputImageWidth: Int
    private let outputImageHeight: Int
    private let outputClassCount: Int
    
    private let labelList = TissueLabelType.allCases
    private let confidenceLabelList = ConfidenceLabelType.allCases
    
    var segmentedImage: UIImage?
    var overlayImage: UIImage?
    var colorLegend: [String: UIColor]?
    var confidenceSegmentedImage: UIImage?
    var confidenceOverlayImage: UIImage?
    var confidenceColorLegend: [String: UIColor]?
    
    /// Initialisation function for SegmentationMap.
    /// - Parameters:
    ///   - outputImageWidth: Width of model output image.
    ///   - outputImageHeight: Height of model output image.
    ///   - outputClassCount: Number of labels in wound.
    ///   - modelOutput: Protocol to get value from model output.
    init(outputImageWidth: Int, outputImageHeight: Int, outputClassCount: Int, modelOutput: ModelOutput) {
        self.outputImageWidth = outputImageWidth
        self.outputImageHeight = outputImageHeight
        self.outputClassCount = outputClassCount
        
        // Initialise data structures.
        segmentationPixelColor = [UInt32](
            repeating: 0, count: outputImageHeight * outputImageWidth)
        classList = Set<Int>()
        confidenceSegmentationPixelColor = [UInt32](
            repeating: 0, count: outputImageHeight * outputImageWidth)
        confidenceClassList = Set<Int>()
        
        parseModelOutput(firstIter: modelOutput.firstIter, secondIter: modelOutput.secondIter, modelOutput: modelOutput)
    }
    
    /// Function that takes in a Float and returns an index based on value.
    /// - Parameter maxVal: Value of highest confidence for a pixel.
    /// - Returns: Confidence index.
    private func getConfidenceIndex(maxVal: Float32) -> Int {
        let confidenceIndex: Int
        switch maxVal {
        case 0.91...1.0:
            confidenceIndex = 0
        case 0.81...0.90:
            confidenceIndex = 1
        case 0.71...0.80:
            confidenceIndex = 2
        case 0.61...0.70:
            confidenceIndex = 3
        case 0.51...0.60:
            confidenceIndex = 4
        case 0.41...0.50:
            confidenceIndex = 5
        case 0.31...0.40:
            confidenceIndex = 6
        case 0.21...0.30:
            confidenceIndex = 7
        case 0.11...0.20:
            confidenceIndex = 8
        case 0.01...0.10:
            confidenceIndex = 9
        default:
            confidenceIndex = 0
        }
        return confidenceIndex
    }
    
    /// Parses through model inference output to create segmentation map.
    /// - Parameters:
    ///   - firstIter: Output image width or height value to be used in outer for loop.
    ///   - secondIter: Output image width or height value to be used in inner for loop.
    ///   - modelOutput: Protocol to get value from model output.
    private mutating func parseModelOutput(firstIter: Int, secondIter: Int, modelOutput: ModelOutput) {
        var maxVal: Float32 = 0.0
        var maxIndex: Int = 0
        
        for x in 0..<firstIter {
            for y in 0..<secondIter {
                maxIndex = 0
                maxVal = 0.0
                // find label with highest confidence level for that pixel
                for z in 0..<outputClassCount {
                    guard let val = modelOutput.getValue(firstIterIndex: x, secondIterIndex: y, classIndex: z) else {
                        os_log("Error parsing model output")
                        return
                    }
                    if val > maxVal {
                        maxVal = val
                        maxIndex = z
                    }
                }
                // Creating default segmentation map.
                classList.insert(maxIndex)
                
                // Lookup the color legend for the class.
                let legendColor = labelList[maxIndex].colorAsUint
                segmentationPixelColor[x * secondIter + y] = legendColor
                
                // Creating confidence segmentation map.
                let confidenceIndex = getConfidenceIndex(maxVal: maxVal)
                confidenceClassList.insert(confidenceIndex)
                
                // Lookup color legend for confidence.
                let confidenceColor = confidenceLabelList[confidenceIndex].colorAsUint
                confidenceSegmentationPixelColor[x * secondIter + y] = confidenceColor
            }
        }
    }
    
    /// Construct a UIImage from a list of sRGB pixels.
    /// - Parameters:
    ///   - pixels: Array containing color for each pixel.
    /// - Returns: Segmented image of wound.
    private func imageFromSRGBColorArray(pixels: [UInt32]) -> UIImage?
    {
        guard outputImageWidth > 0 && outputImageHeight > 0 else { return nil }
        guard pixels.count == outputImageWidth * outputImageHeight else { return nil }
        
        // Make a mutable copy
        var data = pixels
        
        // Convert array of pixels to a CGImage instance.
        let cgImage = data.withUnsafeMutableBytes { (ptr) -> CGImage in
            let ctx = CGContext(
                data: ptr.baseAddress,
                width: outputImageWidth,
                height: outputImageHeight,
                bitsPerComponent: 8,
                bytesPerRow: MemoryLayout<UInt32>.size * outputImageWidth,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    + CGImageAlphaInfo.premultipliedFirst.rawValue
            )!
            return ctx.makeImage()!
        }
        
        // Convert the CGImage instance to an UIImage instance.
        return UIImage(cgImage: cgImage)
    }
    
    /// Maps classes found in the image to its respective color.
    /// - Parameters:
    ///   - classList: Set containing index of wound labels that occur in image.
    /// - Returns: Dictionary mapping a label to a color.
    private func classListToColorLegend(classList: Set<Int>) -> [String: UIColor] {
        let sortedClassIndexList = classList.sorted()
        let colors = sortedClassIndexList.map{labelList[$0].color}
        let labels = sortedClassIndexList.map{labelList[$0].rawValue}
        let colorLegend = Dictionary(uniqueKeysWithValues: zip(labels, colors))
        return colorLegend
    }
    
    /// Maps confidence values to its respective color.
    /// - Parameters:
    ///   - classList: Set containing index of confidence values.
    /// - Returns: Dictionary mapping a confidence value to a color.
    private func classListToConfidenceColorLegend(classList: Set<Int>) -> [String: UIColor] {
        let sortedClassIndexList = classList.sorted()
        let colors = sortedClassIndexList.map{confidenceLabelList[$0].color}
        let labels = sortedClassIndexList.map{confidenceLabelList[$0].rawValue}
        let colorLegend = Dictionary(uniqueKeysWithValues: zip(labels, colors))
        return colorLegend
    }
    
    /// Generates segmented and overlay images and color legend.
    /// - Parameter originalImage: Image for model to perform inference on.
    mutating func generateOutput(originalImage: UIImage) {
        generateSegmentedAndOverlay(originalImage: originalImage)
        generateColorLegend()
    }
    
    /// Generates segmented and overlay image.
    /// - Parameter originalImage: Image for model to perform inference on.
    mutating private func generateSegmentedAndOverlay(originalImage: UIImage) {
        let segmentationImage = imageFromSRGBColorArray(pixels: segmentationPixelColor)
        let confidenceSegmentationImage = imageFromSRGBColorArray(pixels: confidenceSegmentationPixelColor)
        var overlayImage: UIImage? = nil
        var confidenceOverlayImage: UIImage? = nil
        if let image = segmentationImage,
           let confidenceImage = confidenceSegmentationImage {
            overlayImage = originalImage.overlayWithImage(image: image, alpha: 0.5)
            confidenceOverlayImage = originalImage.overlayWithImage(image: confidenceImage, alpha: 0.5)
        }
        self.segmentedImage = segmentationImage
        self.confidenceSegmentedImage = confidenceSegmentationImage
        self.overlayImage = overlayImage
        self.confidenceOverlayImage = confidenceOverlayImage
    }
    
    /// Generates color legend.
    mutating private func generateColorLegend() {
        let colorLegend = classListToColorLegend(classList: classList)
        let confidenceColorLegend = classListToConfidenceColorLegend(classList: confidenceClassList)
        self.colorLegend = colorLegend
        self.confidenceColorLegend = confidenceColorLegend
    }
}
