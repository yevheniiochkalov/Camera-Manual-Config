//
//  CameraViewController.swift
//  Fotoburn
//
//  Created by Admin on 6/22/21.
//

import UIKit
import AVFoundation
import Photos

class CameraViewController: UIViewController {
    @objc dynamic var captureSession: AVCaptureSession!
    @objc dynamic var cameraOutput: AVCapturePhotoOutput!
    @objc dynamic var previewLayer: AVCaptureVideoPreviewLayer!
    @objc dynamic var cameraDevice: AVCaptureDevice!

    @IBOutlet weak var cameraView: UIView!
    private var isUsingFrontCamera = false
    
    private var isMirroring = false
    @IBOutlet weak var mirroringButton: UIButton!
    
    @IBOutlet weak var flashModeControl: UISegmentedControl!
    private var exposureModes: [AVCaptureDevice.ExposureMode] = []
    @IBOutlet weak var exposureModeControl: UISegmentedControl!
    @IBOutlet weak var exposureDurationSlider: UISlider!
    @IBOutlet weak var exposureDurationValueLabel: UILabel!
    @IBOutlet weak var ISOSlider: UISlider!
    @IBOutlet weak var ISOValueLabel: UILabel!
    
    private let kExposureDurationPower = 5.0 // Higher numbers will give the slider more sensitivity at shorter durations
    private let kExposureMinimumDuration = 1.0/1000 // Limit exposure duration to a useful range
    
    private var ExposureModeContext = 0
    private var ExposureDurationContext = 0
    private var ISOContext = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        self.isUsingFrontCamera = false;

        self.isMirroring = false;
        mirroringButton.setTitle("Mirroring Off",for: .normal)
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        self.startCamera()
        self.addObservers()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        if UIDevice.current.orientation.isLandscape {
            print("Landscape")
        } else {
            print("Portrait")
        }
        
        coordinator.animate(alongsideTransition: nil) { _ in
            self.startCamera()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        self.stopCamera()
        self.removeObservers()
    }
    
    func startCamera() {
        captureSession = AVCaptureSession()
        
        captureSession.sessionPreset = AVCaptureSession.Preset.photo
        cameraOutput = AVCapturePhotoOutput()
        
        let cameraPosition: AVCaptureDevice.Position = self.isUsingFrontCamera ? .front : .back
        cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: cameraPosition)
        
        if cameraDevice != nil, let input = try? AVCaptureDeviceInput(device: cameraDevice!) {
            
            if(cameraDevice!.isFocusModeSupported(.continuousAutoFocus)) {
                try! cameraDevice!.lockForConfiguration()
                cameraDevice!.focusMode = .continuousAutoFocus
                cameraDevice!.unlockForConfiguration()
            }
            
            if (captureSession.canAddInput(input)) {
                captureSession.addInput(input)
                if (captureSession.canAddOutput(cameraOutput)) {
                    captureSession.addOutput(cameraOutput)
                    previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
                    previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
                    previewLayer.frame = cameraView.layer.bounds
                    
                    var currentDevice: UIDevice;
                    currentDevice = .current
                    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                    var deviceOrientation: UIDeviceOrientation
                    deviceOrientation = currentDevice.orientation
                    
                    if deviceOrientation == UIDeviceOrientation.landscapeLeft {
                        previewLayer.connection?.videoOrientation = AVCaptureVideoOrientation.landscapeRight
                    } else if deviceOrientation == UIDeviceOrientation.landscapeRight {
                        previewLayer.connection?.videoOrientation = AVCaptureVideoOrientation.landscapeLeft
                    } else if deviceOrientation == UIDeviceOrientation.portrait {
                        previewLayer.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
                    } else if deviceOrientation == UIDeviceOrientation.portraitUpsideDown {
                        previewLayer.connection?.videoOrientation = AVCaptureVideoOrientation.portraitUpsideDown
                    }
                    
                    if (previewLayer.connection?.isVideoMirroringSupported ?? false) {
                        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
                        
                        if (self.isMirroring) {
                            previewLayer.connection?.isVideoMirrored = true
                        } else {
                            previewLayer.connection?.isVideoMirrored = false
                        }
                    }
                    
                    cameraView.layer.addSublayer(previewLayer)
                    captureSession.startRunning()
                    
                    customExposureSettings()
                }
            } else {
                print("issue here : captureSesssion.canAddInput")
            }
        } else {
            print("some problem here")
        }
    }
    
    private func stopCamera() {
        DispatchQueue.main.async {
            self.captureSession.stopRunning()
        }
    }
    
    private func customExposureSettings() {
        // Manual exposure controls
        self.exposureModes = [.continuousAutoExposure, .locked, .custom]
        
        self.exposureModeControl.isEnabled = (self.cameraDevice != nil)
        if let cameraDevice = self.cameraDevice {
            self.exposureModeControl.selectedSegmentIndex = self.exposureModes.firstIndex(of: cameraDevice.exposureMode)!
          for mode in self.exposureModes {
              self.exposureModeControl.setEnabled(cameraDevice.isExposureModeSupported(mode), forSegmentAt: self.exposureModes.firstIndex(of: mode)!)
          }
        }

        // Use 0-1 as the slider range and do a non-linear mapping from the slider value to the actual device exposure duration
        self.exposureDurationSlider.minimumValue = 0
        self.exposureDurationSlider.maximumValue = 1
        let exposureDurationSeconds = CMTimeGetSeconds(self.cameraDevice?.exposureDuration ?? CMTime())
        let minExposureDurationSeconds = max(CMTimeGetSeconds(self.cameraDevice?.activeFormat.minExposureDuration ?? CMTime()), kExposureMinimumDuration)
        let maxExposureDurationSeconds = CMTimeGetSeconds(self.cameraDevice?.activeFormat.maxExposureDuration ?? CMTime())
        // Map from duration to non-linear UI range 0-1
        let p = (exposureDurationSeconds - minExposureDurationSeconds) / (maxExposureDurationSeconds - minExposureDurationSeconds) // Scale to 0-1
        self.exposureDurationSlider.value = Float(pow(p, 1 / kExposureDurationPower)) // Apply inverse power
        self.exposureDurationSlider.isEnabled = (self.cameraDevice != nil && self.cameraDevice!.exposureMode == .custom)

        self.ISOSlider.minimumValue = self.cameraDevice?.activeFormat.minISO ?? 0.0
        self.ISOSlider.maximumValue = self.cameraDevice?.activeFormat.maxISO ?? 0.0
        self.ISOSlider.value = self.cameraDevice?.iso ?? 0.0
        self.ISOSlider.isEnabled = (self.cameraDevice?.exposureMode == .custom)
    }
    
    
    private func takePicture() {
        let settings = AVCapturePhotoSettings()
        let previewPixelType = settings.availablePreviewPhotoPixelFormatTypes.first!
        let previewFormat = [
            kCVPixelBufferPixelFormatTypeKey as String: previewPixelType,
            kCVPixelBufferWidthKey as String: 160,
            kCVPixelBufferHeightKey as String: 160
        ]
        settings.previewPhotoFormat = previewFormat
        
        NSLog("Current Flash Mode = \(self.flashModeControl.selectedSegmentIndex)")
        
        if (self.flashModeControl.selectedSegmentIndex == 0) {
            settings.flashMode = .auto
        } else if (self.flashModeControl.selectedSegmentIndex == 1) {
            settings.flashMode = .on
        } else {
            settings.flashMode = .off
        }
        
        
        if let photoOutputConnection = self.cameraOutput.connection(with: .video) {
            photoOutputConnection.videoOrientation = previewLayer.connection!.videoOrientation
        }
        
        self.cameraOutput.capturePhoto(with: settings, delegate: self)
        
    }
    
    @IBAction func clickRecordBtn(_ sender: Any) {
        self.takePicture()
    }
    
    
    @IBAction func clickMirroringBtn(_ sender: Any) {
        if (self.isMirroring) {
            mirroringButton.setTitle("Mirroring Off",for: .normal)
            self.isMirroring = false
            self.startCamera()
        } else {
            mirroringButton.setTitle("Mirroring On",for: .normal)
            self.isMirroring = true
            self.startCamera()
        }
    }
    
    @IBAction func clickRevertCamera(_ sender: Any) {
        if self.isUsingFrontCamera {
            self.isUsingFrontCamera = false
            self.startCamera()
        } else {
            self.isUsingFrontCamera = true
            self.startCamera()
        }
    }
    
    func UIColorFromRGB(rgbValue: UInt) -> UIColor {
        return UIColor(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: CGFloat(1.0)
        )
    }
    
    private func set(_ slider: UISlider, highlight color: UIColor) {
        slider.tintColor = color
        
        if slider === self.exposureDurationSlider {
            self.exposureDurationValueLabel.textColor = slider.tintColor
        } else if slider === self.ISOSlider {
            self.ISOValueLabel.textColor = slider.tintColor
        }
    }
    
    @IBAction func sliderTouchBegan(_ slider: UISlider) {
        self.set(slider, highlight: UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0))
    }

    @IBAction func sliderTouchEnded(_ slider: UISlider) {
        self.set(slider, highlight: UIColor.yellow)
    }

    
    private func changeExposure(_ exposureMode: AVCaptureDevice.ExposureMode, atDevicePoint point: CGPoint, monitorSubjectAreaChange: Bool) {
      guard let device = self.cameraDevice else {
          print("videoDevice unavailable")
          return
      }
        
        do {
            try device.lockForConfiguration()
            
            if exposureMode != .custom && device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                device.exposurePointOfInterest = point
                device.exposureMode = exposureMode
            }
            
            device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
            device.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @objc func subjectAreaDidChange(_ notificaiton: Notification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        self.changeExposure( .continuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: false)
    }
    
    @objc func sessionRuntimeError(_ notification: Notification) {
           let error = notification.userInfo![AVCaptureSessionErrorKey]! as! NSError
           NSLog("Capture session runtime error: %@", error)
           
           if error.code == AVError.Code.mediaServicesWereReset.rawValue {
               
           } else {
               
           }
       }
       
    @objc @available(iOS 9.0, *)
    func sessionWasInterrupted(_ notification: Notification) {
       let reason = AVCaptureSession.InterruptionReason(rawValue: notification.userInfo![AVCaptureSessionInterruptionReasonKey]! as! Int)!
       NSLog("Capture session was interrupted with reason %ld", reason.rawValue)
       
       if reason == .audioDeviceInUseByAnotherClient ||
           reason == .videoDeviceInUseByAnotherClient {

       } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {

       }
    }
       
    @objc func sessionInterruptionEnded(_ notification: Notification) {
       NSLog("Capture session interruption ended")
    }
    
    private func addObservers() {
        self.addObserver(self, forKeyPath: "cameraDevice.exposureMode", options: [.old, .new], context: &ExposureModeContext)
        self.addObserver(self, forKeyPath: "cameraDevice.exposureDuration", options: .new, context: &ExposureDurationContext)
        self.addObserver(self, forKeyPath: "cameraDevice.ISO", options: .new, context: &ISOContext)
     
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: self.cameraDevice!)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: self.captureSession)
        
        if #available(iOS 9.0, *) {
           NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted(_:)), name: .AVCaptureSessionWasInterrupted, object: self.captureSession)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded(_:)), name: .AVCaptureSessionInterruptionEnded, object: self.captureSession)
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        self.removeObserver(self, forKeyPath: "cameraDevice.exposureMode", context: &ExposureModeContext)
        self.removeObserver(self, forKeyPath: "cameraDevice.exposureDuration", context: &ExposureDurationContext)
        self.removeObserver(self, forKeyPath: "cameraDevice.ISO", context: &ISOContext)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        let oldValue = change![.oldKey]
        let newValue = change![.newKey]

        guard let context = context else {
          super.observeValue(forKeyPath: keyPath, of: object, change: change, context: nil)
          return
        }
        switch context {
            case &ExposureModeContext:
            NSLog("ExposureModeContext: \(newValue)")
            
              if let value = newValue as? Int {
                  let newMode = AVCaptureDevice.ExposureMode(rawValue: value)!
                  if let old = oldValue as? Int {
                      let oldMode = AVCaptureDevice.ExposureMode(rawValue: old)!
                    
                      if oldMode != newMode && oldMode == .custom {
                          do {
                              try self.cameraDevice!.lockForConfiguration()
                              defer {self.cameraDevice!.unlockForConfiguration()}
                              self.cameraDevice!.activeVideoMaxFrameDuration = CMTime.invalid
                              self.cameraDevice!.activeVideoMinFrameDuration = CMTime.invalid
                          } catch let error {
                              NSLog("Could not lock device for configuration: \(error)")
                          }
                      }
                  }
                  DispatchQueue.main.async {
                      
                      self.exposureModeControl.selectedSegmentIndex = self.exposureModes.firstIndex(of: newMode)!
                      self.exposureDurationSlider.isEnabled = (newMode == .custom)
                      self.ISOSlider.isEnabled = (newMode == .custom)
                      
                      if let old = oldValue as? Int {
                          let oldMode = AVCaptureDevice.ExposureMode(rawValue: old)!
                          NSLog("exposure mode: \(oldMode.rawValue) -> \(newMode.rawValue)")
                      } else {
                          NSLog("exposure mode: \(newMode.rawValue)")
                      }
                  }
              }
            case &ExposureDurationContext:
              // Map from duration to non-linear UI range 0-1
              
              if let value = newValue as? CMTime {
                  let newDurationSeconds = CMTimeGetSeconds(value)
                  let exposureMode = self.cameraDevice!.exposureMode
                  
                  let minDurationSeconds = max(CMTimeGetSeconds(self.cameraDevice!.activeFormat.minExposureDuration), kExposureMinimumDuration)
                  let maxDurationSeconds = CMTimeGetSeconds(self.cameraDevice!.activeFormat.maxExposureDuration)
                  // Map from duration to non-linear UI range 0-1
                  let p = (newDurationSeconds - minDurationSeconds) / (maxDurationSeconds - minDurationSeconds) // Scale to 0-1
                  DispatchQueue.main.async {
                      if exposureMode != .custom {
                          self.exposureDurationSlider.value = Float(pow(p, 1 / self.kExposureDurationPower)) // Apply inverse power
                      }
                      if newDurationSeconds < 1 {
                          let digits = max(0, 2 + Int(floor(log10(newDurationSeconds))))
                          self.exposureDurationValueLabel.text = String(format: "1/%.*f", digits, 1/newDurationSeconds)
                      } else {
                          self.exposureDurationValueLabel.text = String(format: "%.2f", newDurationSeconds)
                      }
                  }
              }
            case &ISOContext:
              if let value = newValue as? Float {
                  let newISO = value
                  let exposureMode = self.cameraDevice!.exposureMode
                  
                  DispatchQueue.main.async {
                      if exposureMode != .custom {
                          self.ISOSlider.value = newISO
                      }
                      self.ISOValueLabel.text = String(Int(newISO))
                  }
              }
            default:
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @IBAction func changeFlashMode(_ control: UISegmentedControl) {
       
    }
    
    @IBAction func changeExposureMode(_ control: UISegmentedControl) {
        let mode = self.exposureModes[control.selectedSegmentIndex]
        
        do {
            try self.cameraDevice!.lockForConfiguration()
            if self.cameraDevice!.isExposureModeSupported(mode) {
                self.cameraDevice!.exposureMode = mode
            } else {
                self.exposureModeControl.selectedSegmentIndex = self.exposureModes.firstIndex(of: self.cameraDevice!.exposureMode)!
            }
            self.cameraDevice!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }

    @IBAction func changeExposureDuration(_ control: UISlider) {
        
        let p = pow(Double(control.value), kExposureDurationPower) // Apply power function to expand slider's low-end range
        let minDurationSeconds = max(CMTimeGetSeconds(self.cameraDevice!.activeFormat.minExposureDuration), kExposureMinimumDuration)
        let maxDurationSeconds = CMTimeGetSeconds(self.cameraDevice!.activeFormat.maxExposureDuration)
        let newDurationSeconds = p * ( maxDurationSeconds - minDurationSeconds ) + minDurationSeconds; // Scale from 0-1 slider range to actual duration
        
        do {
            try self.cameraDevice!.lockForConfiguration()
            self.cameraDevice!.setExposureModeCustom(duration: CMTimeMakeWithSeconds(newDurationSeconds, preferredTimescale:1000*1000*1000), iso: AVCaptureDevice.currentISO, completionHandler: nil)
            self.cameraDevice!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }

    @IBAction func changeISO(_ control: UISlider) {
        
        do {
            try self.cameraDevice!.lockForConfiguration()
            self.cameraDevice!.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: control.value, completionHandler: nil)
            self.cameraDevice!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
}


extension CameraViewController : AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("error occured : \(error.localizedDescription)")
        }
        
        if let dataImage = photo.fileDataRepresentation() {
            print(UIImage(data: dataImage)?.size as Any)
            
            var image = UIImage(data: dataImage, scale: 1.0)
            
            if (self.isMirroring) {
                image = UIImage(cgImage: image!.cgImage!, scale: 1.0, orientation:.leftMirrored)
            }
         
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image!)
            }, completionHandler: { success, error in
                if success {
                    // Saved successfully!
                    print("image saved in photo successfully.")
                } else if let error = error {
                    // Save photo failed with error
                } else {
                    // Save photo failed with no error
                }
            })
            

        } else {
            print("some error here")
        }
    }
}
