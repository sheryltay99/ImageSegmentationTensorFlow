//
//  ViewController.swift
//  ImageSegmentationSample
//
//  Created by Sheryl Tay on 15/3/21.
//

import UIKit

class ViewController: UIViewController {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    @IBOutlet weak var segmentationStatusLabel: UILabel!
    @IBOutlet weak var photoCameraButton: UIBarButtonItem!
    @IBOutlet weak var legendLabel: UILabel!
    @IBOutlet weak var segmentationSwitch: UISwitch!
    
    let imagePicker = UIImagePickerController()
    var isCameraAvailable = false
    
    var segmentator: Segmentator?
    var segmentationResult: SegmentationResults?
    var segmentationInput: UIImage?
    
    var count: Int = 0
    var startTime: Date = Date()
    var now: Date = Date()
    var totalTime: Double = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        imagePicker.delegate = self
        imagePicker.allowsEditing = true
        // set default source type as photo library
        imagePicker.sourceType = .photoLibrary
        // Enable camera option only if current device has camera.
        self.isCameraAvailable = UIImagePickerController.isCameraDeviceAvailable(.front)
            || UIImagePickerController.isCameraDeviceAvailable(.rear)
        if self.isCameraAvailable {
            photoCameraButton.isEnabled = true
        }
        
        // Do any additional setup after loading the view.
        segmentationSwitch.isOn = false
        
        guard let segmentator = Segmentator.getInstance() else {
            self.segmentationStatusLabel.text = "Unable to load segmentator."
            return
        }
        self.segmentator = segmentator
        
        //run default segmentation.
        self.segmentationStatusLabel.text = "Running inference..."
        showDemoSegmentation()
    }
    
    @IBAction func onSwitchSegmentation(_ sender: UISwitch) {
        guard let segmentedResult = segmentationResult else { return }
        showClassLegend(segmentedResult)
        self.segmentedControl.selectedSegmentIndex = 1
        onSegmentChanged(self.segmentedControl)
    }
    
    @IBAction func onTapPhotoLibrary(_ sender: UIBarButtonItem) {
        present(imagePicker, animated: true, completion: nil)
    }
    
    @IBAction func onTapCameraButton(_ sender: UIBarButtonItem) {
        if self.isCameraAvailable {
            imagePicker.sourceType = .camera
            present(imagePicker, animated: true, completion: nil)
        }
    }
    
    @IBAction func onSegmentChanged(_ sender: UISegmentedControl) {
        let isConfidenceSegmentation = self.segmentationSwitch.isOn
        
        switch sender.selectedSegmentIndex {
        case 0: //show input image
            self.imageView.image = segmentationInput
        case 1: //show segmented image
            self.imageView.image = isConfidenceSegmentation ? segmentationResult?.confidenceSegmentedImage : segmentationResult?.segmentedImage
        case 2: //show overlay image
            self.imageView.image = segmentationResult?.overlayImage
        default:
            self.imageView.image = segmentationInput
        }
    }
    
    /// Demo image segmentation with a bundled image.
    private func showDemoSegmentation() {
//        if let filePath = Bundle.main.path(forResource: "10020", ofType: "png"),
//           let image = UIImage(contentsOfFile: filePath)
//        {
//            self.startTime = Date()
//            self.now = self.startTime
//            print("start time: \(self.startTime)")
//            runSegmentation(image: image)
//        }
//        if let firstFilePath = Bundle.main.path(forResource: "10020", ofType: "png"),
//           let firstImage = UIImage(contentsOfFile: firstFilePath),
//           let secondFilePath = Bundle.main.path(forResource: "10005", ofType: "png"),
//           let secondImage = UIImage(contentsOfFile: secondFilePath)
//        {
//            for i in 0..<100 {
//                print("executing for index \(i) at \(Date())")
//                if i % 2 == 0 {
//                    runSegmentation(image: firstImage, index: i)
//                } else {
//                    runSegmentation(image: secondImage, index: i)
//                }
//                print("did execution for index \(i) at \(Date())")
//            }
//        }
        if let firstFilePath = Bundle.main.path(forResource: "10020", ofType: "png"),
           let firstImage = UIImage(contentsOfFile: firstFilePath),
           let secondFilePath = Bundle.main.path(forResource: "10005", ofType: "png"),
           let secondImage = UIImage(contentsOfFile: secondFilePath)
        {
            self.startTime = Date()
            self.now = self.startTime
            print("start time: \(self.startTime)")
            for i in 0..<50 {
                self.count = i
                if i % 2 == 0 {
                    runSegmentation(image: firstImage)
                } else {
                    runSegmentation(image: secondImage)
                }
            }
            print("Average time taken for 1 iteration: \(totalTime / 50)")
        }
    }
    
    func runSegmentation(image: UIImage) {
        // Ensuring image orientation is upright.
        guard let transformedImage = image.transformOrientationToUp() else {
            print("Unable to fix image orientation.")
            return
        }
        
        let croppedImage = transformedImage.cropCenter()
        self.segmentationInput = croppedImage
        self.imageView.image = segmentationInput
        
        // Checks if there is an available image before running segmentation.
        guard self.segmentationInput != nil else {
            self.segmentationStatusLabel.text = "Cannot find image to run reference."
            return
        }
        
        // Checks if image segmentator is available.
        guard segmentator != nil else {
            self.segmentationStatusLabel.text = "Segmentator not ready to run inference."
            return
        }
        
        segmentator!.runSegmentation(image: self.segmentationInput!, completion: { result in
            switch result {
            case let .success(segmentationResult):
                self.segmentationResult = segmentationResult
                
                // Switch segmentedControl to display overlay image
                self.segmentedControl.selectedSegmentIndex = 2
                self.onSegmentChanged(self.segmentedControl)
                self.segmentationStatusLabel.text = "Inference obtained successfully."
                
                // add to legend
                self.showClassLegend(segmentationResult)
            case let .failure(error):
                self.segmentationStatusLabel.text = error.localizedDescription
            }
        })
        
        let tempNow = Date()
        let timeInterval = tempNow.timeIntervalSince(self.now)
        print("Time taken for index \(self.count): \(timeInterval)")
        totalTime += timeInterval
        self.now = tempNow
//        print("Current time for index \(self.count): \(self.now)")
//        runNextSegmentation()
    }
    
//    func runNextSegmentation() {
//        guard self.count < 100 else {
//            let timeTaken = self.now.timeIntervalSince(self.startTime)
//            print("Total time to run 500 iterations: \(timeTaken)")
//            return
//        }
//        if let firstFilePath = Bundle.main.path(forResource: "10020", ofType: "png"),
//           let firstImage = UIImage(contentsOfFile: firstFilePath),
//           let secondFilePath = Bundle.main.path(forResource: "10005", ofType: "png"),
//           let secondImage = UIImage(contentsOfFile: secondFilePath)
//        {
//            print("executing for index \(count) at \(Date())")
//            if count % 2 == 0 {
//                count += 1
//                runSegmentation(image: firstImage)
//            } else {
//                count += 1
//                runSegmentation(image: secondImage)
//            }
//            print("did execution for index \(count) at \(Date())")
//        }
//    }
    
    /// Show color legend of each class found in the image.
    private func showClassLegend(_ segmentationResult: SegmentationResults) {
        let legendText = NSMutableAttributedString(string: "Legend: ")
        let segmentationColourLegend: [String: UIColor]
        
        if self.segmentationSwitch.isOn {
            segmentationColourLegend = segmentationResult.confidenceColorLegend
        } else {
            segmentationColourLegend = segmentationResult.colorLegend
        }
        
        // Loop through the classes founded in the image.
        segmentationColourLegend.forEach { (className, color) in
            // If the color legend is light, use black text font. If not, use white text font.
            let textColor = color.isLight() ?? true ? UIColor.black : UIColor.white
            
            // Construct the legend text for current class.
            let attributes = [
                NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .headline),
                NSAttributedString.Key.backgroundColor: color,
                NSAttributedString.Key.foregroundColor: textColor,
            ]
            let string = NSAttributedString(string: " \(className) ", attributes: attributes)
            
            // Add class legend to string to show on the screen.
            legendText.append(string)
            legendText.append(NSAttributedString(string: "  "))
        }
        
        // Show the class legends on the screen.
        self.legendLabel.attributedText = legendText
    }
    
    
}

// MARK: UIImagePicker delegate methods
extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let image = info[.originalImage] as? UIImage else {
            self.segmentationStatusLabel.text = "Unable to select photo from camera or photo library."
            return
        }
//        self.runSegmentation(image: image)
        dismiss(animated: true, completion: nil)
    }
}
