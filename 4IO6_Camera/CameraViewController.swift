//
//  CameraViewController.swift
//  4IO6_Camera
//
//  Created by John Lui on 2021-03-23.
//

import Foundation
import UIKit
import AVFoundation
import Vision
import CoreBluetooth


let heartRateServiceCBUUID = CBUUID(string: "0xFFE0")
let gimbalServiceCBUUID = CBUUID.init(string: "0xFEE9")

let up_slow_1:[UInt8] = [0x24, 0x3c, 0x08, 0x00, 0x18, 0x12, 0x10, 0x01, 0x01, 0x10, 0xd4, 0x0e, 0xd9, 0xc9]
let down_slow_1:[UInt8] = [0x24, 0x3c, 0x08, 0x00, 0x18, 0x12, 0x10, 0x01, 0x01, 0x10, 0x2c, 0x01, 0x5e, 0xa2]
let right_slow_1:[UInt8] = [0x24, 0x3c, 0x08, 0x00, 0x18, 0x12, 0x10, 0x01, 0x02, 0x10, 0x00, 0x08, 0x20, 0xeb]
let right_slow_2:[UInt8] = [0x24, 0x3c, 0x08, 0x00, 0x18, 0x12, 0x11, 0x01, 0x03, 0x10, 0xcd, 0x09, 0x1d, 0xa8]
let left_slow_1:[UInt8] = [0x24, 0x3c, 0x08, 0x00, 0x18, 0x12, 0x10, 0x01, 0x02, 0x10, 0x00, 0x08, 0x20, 0xeb]
let left_slow_2:[UInt8] = [0x24, 0x3c, 0x08, 0x00, 0x18, 0x12, 0x11, 0x01, 0x03, 0x10, 0x0d, 0x06, 0xa6, 0x4f]

let right_fast_1:[UInt8] = [0x24, 0x3c, 0x08, 0x00, 0x18, 0x12, 0x73, 0x01, 0x02, 0x10, 0x00, 0x08, 0xd8, 0x7a]
let right_fast_2:[UInt8] = [0x24, 0x3c, 0x08, 0x00, 0x18, 0x12, 0x74, 0x01, 0x03, 0x10, 0xd4, 0x0e, 0x08, 0x7d]
let left_fast_1:[UInt8] = [0x24, 0x3c, 0x08, 0x00, 0x18, 0x12, 0x5b, 0x01, 0x02, 0x10, 0x00, 0x08, 0x92, 0x42]
let left_fast_2:[UInt8] = [0x24, 0x3c, 0x08, 0x00, 0x18, 0x12, 0x5c, 0x01, 0x03, 0x10, 0x2c, 0x01, 0xc5, 0x2e]

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let widthView = UIScreen.main.bounds.width
    let heightView = UIScreen.main.bounds.height
    
    var centralManager: CBCentralManager!
    var heartRatePeripheral: CBPeripheral!
    var heartRateCharacteristic: CBCharacteristic!
    var gimbalPeripheral: CBPeripheral!
    var gimbalPeripheralCharacteristics: CBCharacteristic!
    private let visionSequenceHandler = VNSequenceRequestHandler()
    private var lastObservation: VNDetectedObjectObservation?
    
    var frameCounter:Int = 0
    
    var originReference:(CGFloat, CGFloat) = (448.0,207.0)
    var newFrameCenter:(CGFloat, CGFloat) = (0,0)
    
    lazy var tapObject = UITapGestureRecognizer(target: self, action: #selector(userTap(_:)))
    
    @objc func userTap(_ sender: UITapGestureRecognizer) {
        self.highlightView.frame.size = CGSize(width: 50, height: 50)
        self.highlightView.center = sender.location(in: self.view)
        
        let originalRect = self.highlightView.frame
        var convertedRect = self.cameraLayer.metadataOutputRectConverted(fromLayerRect: originalRect)
        convertedRect.origin.y = 1 - convertedRect.origin.y
                
        let newObservation = VNDetectedObjectObservation(boundingBox: convertedRect)
        self.lastObservation = newObservation
        
        self.view.addSubview(self.highlightView)
    }
    
    lazy var highlightView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.borderWidth = 4
        view.layer.borderColor = UIColor.red.cgColor
        view.backgroundColor = .clear
        view.layer.masksToBounds = true
        view.layer.cornerRadius = 12
        return view
    }()
    
    lazy var cameraLayer: AVCaptureVideoPreviewLayer = {
        let previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer.frame = view.bounds
        previewLayer.connection?.videoOrientation = .landscapeRight
        return previewLayer
    }()
    
    lazy var captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = AVCaptureSession.Preset.photo
        
        
        guard let backCamera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: backCamera) else { return session }
        
        session.addInput(input)
        return session
    }()
    
    lazy var heartRateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont(name: "Futura", size: 21)
        label.numberOfLines = 0
        label.text = "Heart Rate: 60 BPM"
        label.textColor = .systemRed
        return label
    }()
    
    private func constraintHeartRateLabel() {
        heartRateLabel.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12).isActive = true
        heartRateLabel.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -12).isActive = true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
    
        self.view.addGestureRecognizer(tapObject)
        view.layer.addSublayer(self.cameraLayer)
        
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(dataOutput)
        
        self.view.addSubview(heartRateLabel)
        constraintHeartRateLabel()
    
        self.captureSession.startRunning()
        
    }

    private func handleVisionRequestUpdate(_ request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            guard let newObservation = request.results?.first as? VNDetectedObjectObservation else { return }
            // prepare for next loop
            self.lastObservation = newObservation
            
            guard newObservation.confidence >= 0.3 else {
                // hide the rectangle when we lose accuracy so the user knows something is wrong
                self.highlightView.frame = .zero
                return
            }
            
            // calculate view rect
            var transformedRect = newObservation.boundingBox
            transformedRect.origin.y = 1 - transformedRect.origin.y
            let convertedRect = self.cameraLayer.layerRectConverted(fromMetadataOutputRect: transformedRect)
            
            self.newFrameCenter = (convertedRect.midX, convertedRect.midY)

            if self.frameCounter == 1 {
                let coordDifference = self.computeFrameDifference(newFrame: (convertedRect.midX, convertedRect.midY))
                
                if coordDifference.0 > 60 {
                    self.sendSignalToGimbal(input: 1)
                } else if coordDifference.0 < -60 {
                    self.sendSignalToGimbal(input: 3)
                }
                
                if coordDifference.1 > 80 {
                    self.sendSignalToGimbal(input: 2)
                } else if coordDifference.1 < -80 {
                    self.sendSignalToGimbal(input: 0)
                }
                
                self.frameCounter = 0
            } else {
                self.frameCounter += 1
            }

            // move the highlight view
            self.highlightView.frame = convertedRect
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let lastObservation = self.lastObservation else { return }
        
        let request = VNTrackObjectRequest(detectedObjectObservation: lastObservation, completionHandler: self.handleVisionRequestUpdate(_:error:))
        request.trackingLevel = .accurate
                
        do {
            try self.visionSequenceHandler.perform([request], on: pixelBuffer, orientation:.up)
        } catch {
            print("CameraViewController - captureOutput(didOutput): Could Not Process Buffer: \(error.localizedDescription)")
        }
        
    }
    
}

extension CameraViewController: CBCentralManagerDelegate {
    
    private func computeFrameDifference(newFrame:(CGFloat, CGFloat)) -> (CGFloat, CGFloat) {
        let x_difference = newFrame.0 - originReference.0
        let y_difference = newFrame.1 - originReference.1
        return (x_difference, y_difference)
    }
    
    private func sendSignalToGimbal(input:Int) {
        
        switch input {
        case 0:
            var payload = Data(bytes: up_slow_1)
            self.gimbalPeripheral.writeValue(payload, for: self.gimbalPeripheralCharacteristics, type: .withoutResponse)
        case 1:
            var payload = Data(bytes: right_slow_1)
            self.gimbalPeripheral.writeValue(payload, for: self.gimbalPeripheralCharacteristics, type: .withoutResponse)
            payload = Data(bytes: right_slow_2)
            self.gimbalPeripheral.writeValue(payload, for: self.gimbalPeripheralCharacteristics, type: .withoutResponse)
        case 2:
            var payload = Data(bytes: down_slow_1)
            self.gimbalPeripheral.writeValue(payload, for: self.gimbalPeripheralCharacteristics, type: .withoutResponse)
        case 3:
            var payload = Data(bytes: left_slow_1)
            self.gimbalPeripheral.writeValue(payload, for: self.gimbalPeripheralCharacteristics, type: .withoutResponse)
            payload = Data(bytes: left_slow_2)
            self.gimbalPeripheral.writeValue(payload, for: self.gimbalPeripheralCharacteristics, type: .withoutResponse)
        default:
            print("Default NULL Command")
            return
        }
        
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
          case .unknown:
            print("central.state is .unknown")
          case .resetting:
            print("central.state is .resetting")
          case .unsupported:
            print("central.state is .unsupported")
          case .unauthorized:
            print("central.state is .unauthorized")
          case .poweredOff:
            print("central.state is .poweredOff")
          case .poweredOn:
            centralManager.scanForPeripherals(withServices: [heartRateServiceCBUUID, gimbalServiceCBUUID])
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.name == "Smooth40136" {
            gimbalPeripheral = peripheral
            gimbalPeripheral.delegate = self
            centralManager.connect(gimbalPeripheral)
        } else {
            heartRatePeripheral = peripheral
            heartRatePeripheral.delegate = self
            centralManager.connect(heartRatePeripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected!")
        if peripheral.name == "Smooth40136" {
            gimbalPeripheral.discoverServices([gimbalServiceCBUUID])
        } else {
            heartRatePeripheral.discoverServices([heartRateServiceCBUUID])
        }
    
    }
    
}

extension CameraViewController: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        peripheral.discoverCharacteristics(nil, for: services.first!)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        if peripheral.name == "Smooth40136" {
            self.gimbalPeripheralCharacteristics = characteristics.first
            if self.gimbalPeripheralCharacteristics.properties.contains(.write) {
                print("\(self.gimbalPeripheralCharacteristics.uuid): Properties contains .write")
            }
        } else {
            self.heartRateCharacteristic = characteristics.first
            if self.heartRateCharacteristic.properties.contains(.read) {
                print("\(self.heartRateCharacteristic.uuid): Properties contains .read")
                peripheral.readValue(for: self.heartRateCharacteristic)
                peripheral.setNotifyValue(true, for: self.heartRateCharacteristic)
            }
        }
        
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let rxData = characteristic.value
        if let rxData = rxData {
            let numberOfBytes = rxData.count
            var rxByteArray = [UInt8](repeating: 0, count: numberOfBytes)
            (rxData as NSData).getBytes(&rxByteArray, length: numberOfBytes)
            let bpm = rxByteArray[0]
            DispatchQueue.main.async {
                self.heartRateLabel.text = "Heart Rate " + String(bpm) + " BPM"
            }
        }
    }
    
}
