//
//  Segmentator.swift
//  ImageSegmentationSample
//
//  Created by Sheryl Tay on 15/3/21.
//

import UIKit
import TensorFlowLite

class Segmentator {
    
    private let interpreter: Interpreter
    
    private let labelList: [String]
    
    private let batchSize: Int
    private let inputImageWidth: Int
    private let inputImageHeight: Int
    private let inputPixelSize: Int
    private let outputImageWidth: Int
    private let outputImageHeight: Int
    private let outputClassCount: Int
    
    static public func getInstance() -> Segmentator? {
        // Get model path from bundle
        guard let modelPath = Bundle.main.path(forResource: Constants.modelFileName, ofType: Constants.modelFileExtension) else {
            print("Failed to load model path")
            return nil
        }
        
        guard let labelList = loadLabelList() else {
            print("Failed to load label list")
            return nil
        }
        
        let options = Interpreter.Options()
        do {
            //initialise interpreter with model file path and options
            let interpreter = try Interpreter(modelPath: modelPath, options: options)
            
            try interpreter.allocateTensors()
            
            let inputTensorShape = try interpreter.input(at: 0).shape
            try interpreter.invoke()
            let outputTensorShape = try interpreter.output(at: 0).shape
            
            return Segmentator(interpreter: interpreter, inputTensorShape: inputTensorShape, outputTensorShape: outputTensorShape, labelList: labelList)
        } catch let error {
            print("Failed to initialise interpreter.")
            print(error.localizedDescription)
            return nil
        }
    }
    
    private init(interpreter: Interpreter, inputTensorShape: Tensor.Shape, outputTensorShape: Tensor.Shape, labelList: [String]) {
        self.interpreter = interpreter
        
        self.batchSize = inputTensorShape.dimensions[0]
        self.inputImageWidth = inputTensorShape.dimensions[1]
        self.inputImageHeight = inputTensorShape.dimensions[2]
        self.inputPixelSize = inputTensorShape.dimensions[3]
        
        self.outputImageWidth = outputTensorShape.dimensions[1]
        self.outputImageHeight = outputTensorShape.dimensions[2]
        self.outputClassCount = outputTensorShape.dimensions[3]
        
        self.labelList = labelList
    }
    
    /// Load label list from file.
    private static func loadLabelList() -> [String]? {
        guard
            let labelListPath = Bundle.main.path(
                forResource: Constants.labelsFileName,
                ofType: Constants.labelsFileExtension
            )
        else {
            return nil
        }
        
        // Parse label list file as JSON.
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: labelListPath), options: .mappedIfSafe)
            let jsonResult = try JSONSerialization.jsonObject(with: data, options: .mutableLeaves)
            if let labelList = jsonResult as? [String] { return labelList } else { return nil }
        } catch {
            print("Error parsing label list file as JSON.")
            return nil
        }
    }
    
    // MARK: Segmentation
    public func runSegmentation(image: UIImage, completion: @escaping (Result<SegmentationResults, SegmentationError>) -> Void) {
        guard let imageData = image.scaledData(with: CGSize(width: inputImageWidth, height: inputImageHeight),
                                               byteCount: self.batchSize * self.inputImageWidth * self.inputImageHeight * self.inputPixelSize,
                                               isQuantized: false) else {
            completion(.failure(.invalidImage))
            print("Failed to convert image to data")
            return
        }
        
        let outputTensor: Tensor
        //copy image data to interpreter input, run inference and get output tensor.
        do {
            try self.interpreter.copy(imageData, toInputAt: 0)
            try self.interpreter.invoke()
            outputTensor = try self.interpreter.output(at: 0)
        } catch let error {
            completion(.failure(.internalError(error)))
            print("Failed to run inference with interpreter with error \(error.localizedDescription)")
            return
        }
        let parsedOutput = parseOutput(outputTensor: outputTensor)
        
        guard let segmentationImage = imageFromSRGBColorArray(pixels: parsedOutput.segmentationPixelColour, width: outputImageWidth, height: outputImageHeight),
              let overlayImage = image.overlayWithImage(image: segmentationImage, alpha: 0.5)
        else {
            completion(.failure(.invalidPixelData))
            print("Failed to convert pixel data to image")
            return
        }
        
        let colourLegend = classListToColorLegend(classList: parsedOutput.classList)
        completion(.success(SegmentationResults(originalImage: image, segmentedImage: segmentationImage, overlayImage: overlayImage, colourLegend: colourLegend)))
    }
    
    /// Converting output tensor to segmentation map and get colour for each pixel.
    private func parseOutput(outputTensor: Tensor) -> (segmentationMap: [[Int]], segmentationPixelColour: [UInt32], classList: Set<Int>) {
        // initialising data structures
        var segmentationMap = [[Int]](repeating: [Int](repeating: 0, count: self.outputImageHeight),
                                    count: self.outputImageWidth)
        var segmentationImagePixels = [UInt32](
            repeating: 0, count: self.outputImageHeight * self.outputImageWidth)
        var classList = Set<Int>()
        
        let outputArray = outputTensor.data.toArray(type: Float32.self)
        
        var maxVal: Float32 = 0.0
        var secondMaxVal: Float32 = 0.0
        var val: Float32 = 0.0
        var maxIndex: Int = 0
        var secondMaxIndex: Int = 0
        
        for x in 0..<self.outputImageWidth {
            for y in 0..<self.outputImageHeight {
                maxIndex = 0
                secondMaxIndex = 0
                maxVal = 0.0
                secondMaxVal = 0.0
                // find label with highest confidence level for that pixel
                for z in 0..<self.outputClassCount {
                    val = outputArray[coordinateToIndex(x: x, y: y, z: z)]
                    if val > maxVal {
                        maxVal = val
                        maxIndex = z
                    } else if val > secondMaxVal {
                        secondMaxVal = val
                        secondMaxIndex = z
                    }
                }
                segmentationMap[x][y] = maxIndex
                classList.insert(maxIndex)
                
                // Lookup the color legend for the class.
                // Using modulo to reuse colors on segmentation model with large number of classes.
                let legendColor = Constants.legendColorList[maxIndex % Constants.legendColorList.count]
                segmentationImagePixels[x * self.outputImageHeight + y] = legendColor
            }
        }
        
        return (segmentationMap, segmentationImagePixels, classList)
    }
    
    /// Convert 3-dimension index (image_width x image_height x class_count) to 1-dimension index
    private func coordinateToIndex(x: Int, y: Int, z: Int) -> Int {
        return x * outputImageHeight * outputClassCount + y * outputClassCount + z
    }
    
    /// Construct an UIImage from a list of sRGB pixels.
    private func imageFromSRGBColorArray(pixels: [UInt32], width: Int, height: Int) -> UIImage?
    {
        guard width > 0 && height > 0 else { return nil }
        guard pixels.count == width * height else { return nil }
        
        // Make a mutable copy
        var data = pixels
        
        // Convert array of pixels to a CGImage instance.
        let cgImage = data.withUnsafeMutableBytes { (ptr) -> CGImage in
            let ctx = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: MemoryLayout<UInt32>.size * width,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    + CGImageAlphaInfo.premultipliedFirst.rawValue
            )!
            return ctx.makeImage()!
        }
        
        // Convert the CGImage instance to an UIImage instance.
        return UIImage(cgImage: cgImage)
    }
    
    /// Look up the colors used to visualize the classes found in the image.
    private func classListToColorLegend(classList: Set<Int>) -> [String: UIColor] {
        var colorLegend: [String: UIColor] = [:]
        let sortedClassIndexList = classList.sorted()
        sortedClassIndexList.forEach { classIndex in
            // Look up the color legend for the class.
            // Using modulo to reuse colors on segmentation model with large number of classes.
            let color = Constants.legendColorList[classIndex % Constants.legendColorList.count]
            
            // Convert the color from sRGB UInt32 representation to UIColor.
            let a = CGFloat((color & 0xFF00_0000) >> 24) / 255.0
            let r = CGFloat((color & 0x00FF_0000) >> 16) / 255.0
            let g = CGFloat((color & 0x0000_FF00) >> 8) / 255.0
            let b = CGFloat(color & 0x0000_00FF) / 255.0
            colorLegend[labelList[classIndex]] = UIColor(red: r, green: g, blue: b, alpha: a)
        }
        return colorLegend
    }
}

struct SegmentationResults {
    var originalImage: UIImage
    var segmentedImage: UIImage
    var overlayImage: UIImage
    var colourLegend: [String: UIColor]
}

enum SegmentationError: Error {
    case invalidImage
    case invalidPixelData
    case internalError(Error)
}

// MARK: Constants
struct Constants {
    static let modelFileName = "model"
    static let modelFileExtension = "tflite"
    
    static let labelsFileName = "deeplab"
    static let labelsFileExtension = "json"
    
    static let legendColorList: [UInt32] = [
        0xFF80_8080, // Gray
        0xFFFF_0000, // Red
        0xFFFF_1493, // Pink
        0xFFFF_7F50, // Orange
        0xFF1E_90FF, // Blue
        0xFFAA_6E28, // Brown
        0xFFFF_FF00 // Yellow
    ]
}
