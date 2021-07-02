////
////  Segmentator.swift
////  ImageSegmentationSample
////
////  Created by Sheryl Tay on 15/3/21.
////
import UIKit
import TensorFlowLite
import os.log

/// Initialises AI SG TFLite model and performs inference on model to get segmentation image.
class Segmentator {
    
    private let interpreter: Interpreter
    
    private let batchSize: Int
    private let inputImageWidth: Int
    private let inputImageHeight: Int
    private let inputPixelSize: Int
    
    private var outputImageWidth: Int = 0
    private var outputImageHeight: Int = 0
    private var outputClassCount: Int = 0
    private var outputArray: [Float32]?
    
    static let modelFileName = "mobileunet_model"
    static let modelFileExtension = "tflite"
    
    /// Create instance of TFLiteSegmenter class.
    /// - Parameter modelPath: Path of TFLite model in project.
    /// - Returns: Instance of TFLiteSegmenter.
    static func getInstance() -> Segmentator? {
        
        guard let modelPath = Bundle.main.path(forResource: modelFileName, ofType: modelFileExtension) else {
            print("Failed to load model path")
            return nil
        }
        
        let options = Interpreter.Options()
        do {
            //initialise interpreter with model file path and options
            let interpreter = try Interpreter(modelPath: modelPath, options: options)
            
            try interpreter.allocateTensors()
            
            let inputTensorShape = try interpreter.input(at: 0).shape
            
            return Segmentator(interpreter: interpreter,
                                   inputTensorShape: inputTensorShape)
        } catch let error {
            os_log("Failed to initialise interpreter with error: %@", log: .aisgtl, type:.error, error.localizedDescription)
            return nil
        }
    }
    
    /// Initialise TFLiteSegmenter with TFLite Interpreter and input image details.
    /// - Parameters:
    ///   - interpreter: TFLite Interpreter class to run inference.
    ///   - inputTensorShape: Shape of input image.
    private init(interpreter: Interpreter,
                 inputTensorShape: Tensor.Shape) {
        self.interpreter = interpreter
        
        batchSize = inputTensorShape.dimensions[0]
        inputImageWidth = inputTensorShape.dimensions[1]
        inputImageHeight = inputTensorShape.dimensions[2]
        inputPixelSize = inputTensorShape.dimensions[3]
    }
    
    // MARK: Segmentation
    /// Creates segmented image from TFLite model inference output.
    /// - Parameters:
    ///   - image: Image for model to perform inference on.
    ///   - completion: Result returned from performing segmentation.
    func runSegmentation(image: UIImage, completion: @escaping (Result<SegmentationResults, SegmentationError>) -> Void) {
        guard let imageData = image.scaledData(with: CGSize(width: inputImageWidth, height: inputImageHeight),
                                               byteCount: batchSize * inputImageWidth * inputImageHeight * inputPixelSize,
                                               isQuantized: false) else {
            completion(.failure(.invalidImage))
            os_log("Failed to convert image to data", log: .aisgtl, type:.error)
            return
        }

        let outputTensor: Tensor
        //copy image data to interpreter input, run inference and get output tensor.
        do {
            try interpreter.copy(imageData, toInputAt: 0)
            try interpreter.invoke()
            outputTensor = try interpreter.output(at: 0)
        } catch let error {
            completion(.failure(.internalError(error)))
            os_log("Failed to run inference with interpreter with error: %@", log: .aisgtl, type:.error, error.localizedDescription)
            return
        }
        
        outputImageWidth = outputTensor.shape.dimensions[1]
        outputImageHeight = outputTensor.shape.dimensions[2]
        outputClassCount = outputTensor.shape.dimensions[3]
        outputArray = outputTensor.data.toArray(type: Float32.self)
        
        var parsedOutput = SegmentationMap(outputImageWidth: outputImageWidth,
                                           outputImageHeight: outputImageHeight,
                                           outputClassCount: outputClassCount,
                                           modelOutput: self)

        // Generating segmentation and overlay images.
        parsedOutput.generateOutput(originalImage: image)
        guard let segmentedImage = parsedOutput.segmentedImage,
              let overlayImage = parsedOutput.overlayImage,
              let colorLegend = parsedOutput.colorLegend,
              let confidenceSegmentedImage = parsedOutput.confidenceSegmentedImage,
              let confidenceOverlayImage = parsedOutput.confidenceOverlayImage,
              let confidenceColorLegend = parsedOutput.confidenceColorLegend
        else {
            completion(.failure(.invalidPixelData))
            os_log("Failed to convert pixel data to image", log: .aisgtl, type:.error)
            return
        }
        
        completion(.success(SegmentationResults(originalImage: image,
                                                segmentedImage: segmentedImage,
                                                overlayImage: overlayImage,
                                                colorLegend: colorLegend,
                                                confidenceSegmentedImage: confidenceSegmentedImage,
                                                confidenceOverlayImage: confidenceOverlayImage,
                                                confidenceColorLegend: confidenceColorLegend)))
    }
}

extension Segmentator: ModelOutput {
    var firstIter: Int {
        return outputImageWidth
    }
    
    var secondIter: Int {
        return outputImageHeight
    }
    
    func getValue(firstIterIndex: Int, secondIterIndex: Int, classIndex: Int) -> Float32? {
        guard let outputArray = self.outputArray else {
            os_log("Unable to get output data from model")
            return nil
        }
        let index = firstIterIndex * outputImageHeight * outputClassCount + secondIterIndex * outputClassCount + classIndex
        return outputArray[index]
    }
}
