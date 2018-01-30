//
//  ViewController.swift
//  EatCam
//
//  Created by Adam Browne on 1/27/18.
//  Copyright © 2018 Adam Browne. All rights reserved.
//


//done with guidance from https://github.com/hanleyweng/CoreML-in-ARKit/blob/master/CoreML%20in%20ARKit/ViewController.swift
//our api key for usda.gov: JoOQ5nAIyvSOlPTEdLo3S32KlrI9euXo8bMpym97
//Account Email: adamo.browne@gmail.com
//Account ID: bbac2184-4a84-408d-8794-f2de1fc4b652

import UIKit
import SceneKit
import ARKit
import Vision
import Foundation

extension String
{
    func trim() -> String
    {
        return self.trimmingCharacters(in: NSCharacterSet.whitespaces)
    }
}
enum JSONError: String, Error {
    case NoData = "ERROR: no data"
    case ConversionFailed = "ERROR: conversion from JSON failed"
}
class ViewController: UIViewController, ARSCNViewDelegate {
    
    // SCENE
    @IBOutlet weak var sceneView: ARSCNView!
    
    let textDepth : Float = 0.01 // the 'depth' of 3D text
    var prediction : String = ""
    
    // COREML
    var visionRequests = [VNRequest]()
    let dispatchQueueML = DispatchQueue(label: "com.hw.dispatchqueueml") // A Serial Queue
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create a new scene
        let scene = SCNScene()
        
        // Set the scene to the view
        sceneView.scene = scene
        
        // Tap Gesture Recognizer
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(gestureRecognize:)))
        view.addGestureRecognizer(tap)
        
        
        //guard block in case coreML model isn't found
        guard let selectedModel = try? VNCoreMLModel(for: Food101().model) else {
            fatalError("Model did not load")
        }
        
        // Set up Vision-CoreML Request
        let classificationRequest = VNCoreMLRequest(model: selectedModel, completionHandler: classificationCompleteHandler)
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop //crop and scale images
        visionRequests = [classificationRequest]
        
        // Begin Loop to Update CoreML
        coreMLUpdate()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        // Enable plane detection
        configuration.planeDetection = .horizontal
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    //        fetch the ndbno value from the usda api. This is using the branded foods database;
    func getFoodIdAndDrawDetails(food_search: String, orig_text_place: SCNVector3) {
        // looking through the Branded foods database;
        // the standard reference may be more `accurate`, but it is more limited.
        var request = URLRequest(url: URL(string: food_search)!)
        request.httpMethod = "GET"
        let session = URLSession.shared
        session.dataTask(with: request) { data, response, err in
            do {
                if let json = try JSONSerialization.jsonObject(with: data!, options: []) as? NSDictionary {
                    if json["list"] != nil {
                        let food_list = json["list"] as? NSDictionary
                        let item_list = food_list!["item"] as? NSArray
                        let fetchFoodIdentifier = item_list![0] as? NSDictionary
                        let foodId : String = fetchFoodIdentifier!["ndbno"] as! String
                        self.fetchNutritionInformation(foodIdentifier: foodId, orig_text_place: orig_text_place)
                    }
                }
            } catch let _ as NSError {}
        }.resume()
    }
    
//    duplicate code here. you would abstract away if you were competent
    func fetchNutritionInformation(foodIdentifier: String, orig_text_place: SCNVector3){
        let usda_nutrition_search = "https://api.nal.usda.gov/ndb/nutrients/?format=json&api_key=JoOQ5nAIyvSOlPTEdLo3S32KlrI9euXo8bMpym97&nutrients=203&nutrients=205&nutrients=204&nutrients=208&ndbno=" + foodIdentifier.trim()
        var request = URLRequest(url: URL(string: usda_nutrition_search)!)
        request.httpMethod = "GET"
        let session = URLSession.shared
        session.dataTask(with: request) { data, response, err in
            do {
                if let json = try JSONSerialization.jsonObject(with: data!, options: []) as? NSDictionary {
                    if json["report"] != nil {
                        let nutrient_report = json["report"] as? NSDictionary
                        let nutrient_list = nutrient_report!["foods"] as? NSArray
                        let actual_nuts = nutrient_list![0] as? NSDictionary
                        let finally_what_we_want = actual_nuts!["nutrients"] as? NSArray
                        self.drawNutrients(usda_info: finally_what_we_want!, orig_spot: orig_text_place)
                    }
                }
            } catch let _ as NSError {}
        }.resume()
    }
    
    // NOTE: the offset is at 0.02 because it's relative to the current pos?
    // I made the mistake of making it huge and couldn't see the attribute nodes. Woops!
    func drawNutrients(usda_info: NSArray, orig_spot: SCNVector3) {
        var y_offset : Float = -0.02
        for nutrient in usda_info {
            let currentNutrient = nutrient as! NSDictionary
            let newAttributeSpot = SCNVector3(x: orig_spot.x, y: orig_spot.y + y_offset, z: orig_spot.z)
            var nutrientLabel : String = self.simpleNamesAreBest(origNutrientName: currentNutrient["nutrient"]! as! String) + ": "
            let nutrient_val = currentNutrient["value"]! as! String
            let nutrient_unit = currentNutrient["unit"]! as! String
            nutrientLabel = nutrientLabel + nutrient_val + " " + nutrient_unit
            self.buildNutrientNode(nutrientAttrs: nutrientLabel, new_location: newAttributeSpot)
            y_offset -= 0.02
        }
    }
    
    func buildNutrientNode(nutrientAttrs: String, new_location: SCNVector3) {
        let node : SCNNode = self.createNewBubbleParentNode(nutrientAttrs, isAttribute: true)
        sceneView.scene.rootNode.addChildNode(node)
        node.position = new_location
    }
    
    func simpleNamesAreBest(origNutrientName: String) -> String {
        switch origNutrientName {
            case "Energy":
                return "Calories"
            case "Total lipid (fat)":
                return "Fats"
            case "Carbohydrate, by difference":
                return "Carbs"
            default:
                return origNutrientName
        }
    }
    
    @objc func handleTap(gestureRecognize: UITapGestureRecognizer) {

        let centre : CGPoint = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
        
        let test : [ARHitTestResult] = sceneView.hitTest(centre, types: [.featurePoint])
        
        if let closestResult = test.first {
            //            remove all nodes that exist before the others.
            sceneView.scene.rootNode.enumerateChildNodes { (node, stop) -> Void in
                node.removeFromParentNode()
            }
            // Get Coordinates of HitTest
            let transform : matrix_float4x4 = closestResult.worldTransform
            let worldCoord : SCNVector3 = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            
            // Create 3D Text
            let node : SCNNode = createNewBubbleParentNode(prediction, isAttribute: false)
            sceneView.scene.rootNode.addChildNode(node)
            node.position = worldCoord
            //TODO: take prediction, do a search on USDA website, parse nutritional info and display it above the thingy
            let usda_food_search = "https://api.nal.usda.gov/ndb/search/?format=json&q=" + prediction.trim() + "&sort=n&max=25&offset=0&api_key=JoOQ5nAIyvSOlPTEdLo3S32KlrI9euXo8bMpym97"
            getFoodIdAndDrawDetails(food_search: usda_food_search, orig_text_place: worldCoord)
        }
    }
    
    
    //create text bubbles
    func createNewBubbleParentNode(_ text : String, isAttribute: Bool) -> SCNNode {

        // TEXT BILLBOARD CONSTRAINT
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.Y
        
        // BUBBLE-TEXT
        let bubble = SCNText(string: text, extrusionDepth: CGFloat(textDepth))
        var font = UIFont(name: "Arial", size: 0.10)
        bubble.firstMaterial?.diffuse.contents = UIColor.red
        if (isAttribute == true) {
            font = UIFont(name: "Arial", size: 0.08)
            bubble.firstMaterial?.diffuse.contents = UIColor.green
        }
        font = font?.withTraits(traits: .traitBold)
        bubble.font = font
        bubble.alignmentMode = kCAAlignmentCenter
        bubble.firstMaterial?.specular.contents = UIColor.white
        bubble.firstMaterial?.isDoubleSided = true
        
        bubble.chamferRadius = CGFloat(textDepth)
        
        // BUBBLE NODE
        let (minBound, maxBound) = bubble.boundingBox
        let bubbleNode = SCNNode(geometry: bubble)
        // Centre Node - to Centre-Bottom point
        bubbleNode.pivot = SCNMatrix4MakeTranslation( (maxBound.x - minBound.x)/8, minBound.y, textDepth/8)
        // Reduce default text size
        bubbleNode.scale = SCNVector3Make(0.2, 0.2, 0.2)
        bubbleNode.position = SCNVector3(0, 0.1, 0)
        
        
        // BUBBLE PARENT NODE
        let bubbleNodeParent = SCNNode()
        bubbleNodeParent.addChildNode(bubbleNode)
        if (isAttribute == false) {
            // CENTRE POINT NODE
            let sphere = SCNSphere(radius: 0.003)
            sphere.firstMaterial?.diffuse.contents = UIColor.cyan
            let sphereNode = SCNNode(geometry: sphere)
            bubbleNodeParent.addChildNode(sphereNode)
        }
        bubbleNodeParent.constraints = [billboardConstraint]
        
        return bubbleNodeParent
    }
    
    func coreMLUpdate() {
        //keep running coreML regardless of what is in the frame
        dispatchQueueML.async {
            // 1. Run Update.
            self.updateCoreML()
            
            // 2. Loop this function.
            self.coreMLUpdate()
        }
        
    }
    
    func classificationCompleteHandler(request: VNRequest, error: Error?) {
        // Catch Errors
        if error != nil {
            print("Error: " + (error?.localizedDescription)!)
            return
        }
        guard let observations = request.results else {
            print("No results")
            return
        }
        
        // Get Classifications
        let classifications = observations[0...1] // top 2 results
            .flatMap({ $0 as? VNClassificationObservation })
            .map({ "\($0.identifier) \(String(format:"- %.2f", $0.confidence))" })
            .joined(separator: "\n")
        
        
        DispatchQueue.main.async {
            // Print Classifications
//            print(classifications)
//            print("--")
//
            // Store the latest prediction
            var objectName:String = "…"
            objectName = classifications.components(separatedBy: "-")[0]
            objectName = objectName.components(separatedBy: ",")[0]
            self.prediction = objectName
            
        }
    }
    
    func updateCoreML() {
        
        // Get Camera Image as RGB
        let buffer : CVPixelBuffer? = (sceneView.session.currentFrame?.capturedImage)
        if buffer == nil { return }
        let ciImage = CIImage(cvPixelBuffer: buffer!)
        
        // Prepare CoreML/Vision Request
        let requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])

        // Run Image Request
        do {
            try requestHandler.perform(self.visionRequests)
        } catch {
            print(error)
        }
        
    }
}

extension UIFont {
    // Based on: https://stackoverflow.com/questions/4713236/how-do-i-set-bold-and-italic-on-uilabel-of-iphone-ipad
    func withTraits(traits:UIFontDescriptorSymbolicTraits...) -> UIFont {
        let descriptor = self.fontDescriptor.withSymbolicTraits(UIFontDescriptorSymbolicTraits(traits))
        return UIFont(descriptor: descriptor!, size: 0)
    }
}

