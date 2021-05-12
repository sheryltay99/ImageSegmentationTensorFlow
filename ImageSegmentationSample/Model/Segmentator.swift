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
    
    // running segmentation to get default mask and confidence mask
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

        // Generating default segmentation and overlay images.
        guard let segmentationImage = imageFromSRGBColorArray(pixels: parsedOutput.segmentationPixelColour, width: outputImageWidth, height: outputImageHeight),
              let overlayImage = image.overlayWithImage(image: segmentationImage, alpha: 0.5)
        else {
            completion(.failure(.invalidPixelData))
            print("Failed to convert pixel data to image")
            return
        }
        let colourLegend = classListToColorLegend(classList: parsedOutput.classList)

        // Generating second segmentation and overlay images.
        guard let confidenceSegmentationImage = imageFromSRGBColorArray(pixels: parsedOutput.confidenceSegmentationPixelColour, width: outputImageWidth, height: outputImageHeight)
        else {
            completion(.failure(.invalidPixelData))
            print("Failed to convert pixel data to image")
            return
        }
        let confidenceColourLegend = confidenceClassListToColorLegend(classList: parsedOutput.confidenceClassList)

        completion(.success(SegmentationResults(originalImage: image,
                                                segmentedImage: segmentationImage,
                                                overlayImage: overlayImage,
                                                colourLegend: colourLegend,
                                                confidenceSegmentedImage: confidenceSegmentationImage,
                                                confidenceColourLegend: confidenceColourLegend)))
    }
    
    
    /// Generating confidence maps
    private func parseOutput(outputTensor: Tensor) -> (segmentationMap: [[Int]],
                                                       segmentationPixelColour: [UInt32],
                                                       classList: Set<Int>,
                                                       confidenceSegmentationMap: [[Int]],
                                                       confidenceSegmentationPixelColour: [UInt32],
                                                       confidenceClassList: Set<Int>) {
        // initialising data structures
        var segmentationMap = [[Int]](repeating: [Int](repeating: 0, count: self.outputImageHeight),
                                    count: self.outputImageWidth)
        var segmentationImagePixels = [UInt32](
            repeating: 0, count: self.outputImageHeight * self.outputImageWidth)
        var classList = Set<Int>()
        var confidenceSegmentationMap = [[Int]](repeating: [Int](repeating: 0, count: self.outputImageHeight),
                                    count: self.outputImageWidth)
        var confidenceSegmentationImagePixels = [UInt32](
            repeating: 0, count: self.outputImageHeight * self.outputImageWidth)
        var confidenceClassList = Set<Int>()

        let outputArray = outputTensor.data.toArray(type: Float32.self)

        var maxVal: Float32 = 0.0
        var val: Float32 = 0.0
        var maxIndex: Int = 0

        for x in 0..<self.outputImageWidth {
            for y in 0..<self.outputImageHeight {
                maxIndex = 0
                maxVal = 0.0
                // find label with highest confidence level for that pixel
                for z in 0..<self.outputClassCount {
                    val = outputArray[coordinateToIndex(x: x, y: y, z: z)]
                    if val > maxVal {
                        maxVal = val
                        maxIndex = z
                    }
                }
                // creating default segmentation map
                segmentationMap[x][y] = maxIndex
                classList.insert(maxIndex)

                // Lookup the color legend for the class.
                // Using modulo to reuse colors on segmentation model with large number of classes.
                let legendColor = Constants.legendColorList[maxIndex % Constants.legendColorList.count]
                segmentationImagePixels[x * self.outputImageHeight + y] = legendColor

                // creating confidence segmentation map.
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

                confidenceSegmentationMap[x][y] = confidenceIndex
                confidenceClassList.insert(confidenceIndex)
                let confidenceColour = Constants.confidenceColorList[confidenceIndex % Constants.confidenceColorList.count]
                confidenceSegmentationImagePixels[x * self.outputImageHeight + y] = confidenceColour

            }
        }

        return (segmentationMap,
                segmentationImagePixels,
                classList,
                confidenceSegmentationMap,
                confidenceSegmentationImagePixels,
                confidenceClassList)
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
    
    /// Look up colours to visualise confidence mask.
    private func confidenceClassListToColorLegend(classList: Set<Int>) -> [String: UIColor] {
        var colorLegend: [String: UIColor] = [:]
        classList.forEach { classIndex in
            // Look up the color legend for the class.
            // Using modulo to reuse colors on segmentation model with large number of classes.
            let color = Constants.confidenceColorList[classIndex % Constants.confidenceColorList.count]
            
            // Convert the color from sRGB UInt32 representation to UIColor.
            let a = CGFloat((color & 0xFF00_0000) >> 24) / 255.0
            let r = CGFloat((color & 0x00FF_0000) >> 16) / 255.0
            let g = CGFloat((color & 0x0000_FF00) >> 8) / 255.0
            let b = CGFloat(color & 0x0000_00FF) / 255.0
            
            colorLegend[Constants.confidenceLabels[classIndex]] = UIColor(red: r, green: g, blue: b, alpha: a)
        }
        return colorLegend
    }
}

//// segmentation results for default mask and second highest confidence mask
//struct SegmentationResults {
//    var originalImage: UIImage
//    var segmentedImage: UIImage
//    var overlayImage: UIImage
//    var colourLegend: [String: UIColor]
//    var secondSegmentedImage: UIImage
//    var secondOverlayImage: UIImage
//    var secondColourLegend: [String: UIColor]
//}

 //segmentation results for default mask and confidence mask
struct SegmentationResults {
    var originalImage: UIImage
    var segmentedImage: UIImage
    var overlayImage: UIImage
    var colourLegend: [String: UIColor]
    var confidenceSegmentedImage: UIImage
    var confidenceColourLegend: [String: UIColor]
}

enum SegmentationError: Error {
    case invalidImage
    case invalidPixelData
    case internalError(Error)
}

// MARK: Constants
struct Constants {
    static let modelFileName = "mobileunet_model"
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
    
    static let confidenceColorList: [UInt32] = [
        0xFF24_6590, // 91% - 100%
        0xFF24_6590, // 81% - 90%
        0xFF24_6590, // 71% - 80%
        0xFF3D_ACF7, // 61% - 70%
        0xFF79_D6F9, // 51% - 60%
        0xFFE8_7AA4, // 41% - 50%
        0xFFF9_D98C, // 31% - 40%
        0xFFB8_E233, // 21% - 30%
        0xFFB8_E233, // 11% - 20%
        0xFFB8_E233 // 1% - 10%
    ]
    
    static let confidenceLabels: [String] = [
        "91%-100%",
        "81%-90%",
        "71%-80%",
        "61%-70%",
        "51%-60%",
        "41%-50%",
        "31%-40%",
        "21%-30%",
        "11%-20%",
        "1%-10%"
    ]
}
