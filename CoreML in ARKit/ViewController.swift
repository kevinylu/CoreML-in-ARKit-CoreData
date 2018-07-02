//
//  ViewController.swift
//  CoreML in ARKit
//
//  Created by Hanley Weng on 14/7/17.
//  Copyright © 2017 CompanyName. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import CoreData

import Vision

class ViewController: UIViewController, ARSCNViewDelegate {

    // SCENE
    @IBOutlet var sceneView: ARSCNView!
    let bubbleDepth : Float = 0.01 // the 'depth' of 3D text
    let context = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
    var latestPrediction : String = "…" // a variable containing the latest CoreML prediction
    var dict: Dictionary = Dictionary<String,Dictionary<String,String>>()
    
    // COREML
    var visionRequests = [VNRequest]()
    let dispatchQueueML = DispatchQueue(label: "com.hw.dispatchqueueml") // A Serial Queue
    @IBOutlet weak var debugTextView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //let text = "word,phonetic,definition,translation,pos,collins,oxford,tag,bnc,frq,exchange,detail,audio\ncomputer keyboard,kəmˈpju:tə ˈki:bɔ:d,, 计算机键盘,,,,,0,0,,,"
        
        if let search = searchForWord(searchStr: "cup") {
            print(search)
            startTracking()
        }
        else{
            if let filepath = Bundle.main.path(forResource: "ecdict", ofType: "csv") {
                do {
                    let contents = try String(contentsOfFile: filepath)
                    csvToCoreData(data: contents)
                    //startTracking()
                } catch {
                    // contents could not be loaded
                }
            } else {
                // example.txt not found!
            }
        }
    }
    
    func startTracking(){
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        // Create a new scene
        let scene = SCNScene()
        
        // Set the scene to the view
        sceneView.scene = scene
        
        // Enable Default Lighting - makes the 3D text a bit poppier.
        sceneView.autoenablesDefaultLighting = true
        
        //////////////////////////////////////////////////
        // Tap Gesture Recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(gestureRecognize:)))
        view.addGestureRecognizer(tapGesture)
        
        //////////////////////////////////////////////////
        
        // Set up Vision Model
        guard let selectedModel = try? VNCoreMLModel(for: Inceptionv3().model) else { // (Optional) This can be replaced with other models on https://developer.apple.com/machine-learning/
            fatalError("Could not load model. Ensure model has been drag and dropped (copied) to XCode Project from https://developer.apple.com/machine-learning/ . Also ensure the model is part of a target (see: https://stackoverflow.com/questions/45884085/model-is-not-part-of-any-target-add-the-model-to-a-target-to-enable-generation ")
        }
        
        // Set up Vision-CoreML Request
        let classificationRequest = VNCoreMLRequest(model: selectedModel, completionHandler: classificationCompleteHandler)
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop // Crop from centre of images and scale to appropriate size.
        visionRequests = [classificationRequest]
        
        // Begin Loop to Update CoreML
        loopCoreMLUpdate()
    }
    
    func csv(data: String) -> Dictionary<String,Dictionary<String,String>> {
        
        let rows = data.components(separatedBy: "\n")
        var dictT = Dictionary<String,Dictionary<String,String>>()
        var i = 0
        for row in rows {
            if (i > 0){
                let columns = row.components(separatedBy: ",")
                let wordDict =  ["word": columns[0], "phonetic": columns[1], "definition":columns[2], "translation": columns[3], "pos": columns[4], "collins": columns[5], "oxford":columns[6], "tag": columns[7], "bnc": columns[8], "frq": columns[9], "exchange": columns[10], "detail": columns[11], "audio": columns[12]]
                dictT[columns[0]] = wordDict
            }
            i = i+1
        }
        
        return dictT;
    }
    
    func searchForWord(searchStr: String) -> String?
    {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Word")
        request.predicate = NSPredicate(format: "word = %@", searchStr)
        request.returnsObjectsAsFaults = false
        do {
            let result = try context.fetch(request)
            for data in result as! [NSManagedObject] {
                let temporaryString = data.value(forKey: "translation") as! String
                return temporaryString
            }
            
        } catch {
            
            return ""
        }
        
        return ""
    }
    
    func searchAsynchronous(searchStr: String){
        // Creates a fetch request to get all the dogs saved
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Word")
        fetchRequest.predicate = NSPredicate(format: "word = %@", searchStr)
        fetchRequest.fetchLimit = 1;
        // Creates `asynchronousFetchRequest` with the fetch request and the completion closure
        let asynchronousFetchRequest = NSAsynchronousFetchRequest(fetchRequest: fetchRequest) { asynchronousFetchResult in
            
            // Retrieves an array of dogs from the fetch result `finalResult`
            guard let result = asynchronousFetchResult.finalResult as? [Word] else { return }
            
            // Dispatches to use the data in the main queue
            DispatchQueue.main.async {
                // Do something
                for data in result {
                    let temporaryString = data.value(forKey: "translation") as! String
                    print(temporaryString)
                    let screenCentre : CGPoint = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
                    
                    let arHitTestResults : [ARHitTestResult] = self.sceneView.hitTest(screenCentre, types: [.featurePoint]) // Alternatively, we could use '.existingPlaneUsingExtent' for more grounded hit-test-points.
                    
                    if let closestResult = arHitTestResults.first {
                        // Get Coordinates of HitTest
                        let transform : matrix_float4x4 = closestResult.worldTransform
                        let worldCoord : SCNVector3 = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                        
                        let node : SCNNode = self.createNewBubbleParentNode(temporaryString)
                        self.sceneView.scene.rootNode.addChildNode(node)
                        node.position = worldCoord
                    }
                    
                    asynchronousFetchResult.progress?.cancel()
                    if let asynchronousFetchProgress = asynchronousFetchResult.progress {
                        asynchronousFetchProgress.addObserver(self, forKeyPath: #keyPath(Progress.completedUnitCount), options: NSKeyValueObservingOptions.new, context: nil)
                    }
                    break
                }
            }
        }
        
//        // Creates a new `Progress` object
//        let progress = Progress(totalUnitCount: 1)
//        
//        // Sets the new progess as default one in the current thread
//        progress.becomeCurrent(withPendingUnitCount: 1)
//        
//        // Resigns the current progress
//        progress.resignCurrent()
        
        do {
            // Executes `asynchronousFetchRequest`
            //try context.execute(asynchronousFetchRequest)
            let fetchResult = try context.execute(asynchronousFetchRequest) as? NSPersistentStoreAsynchronousResult
            fetchResult?.progress?.addObserver(self, forKeyPath: #keyPath(Progress.completedUnitCount), options: .new, context: nil)
            
        } catch let error {
            print("NSAsynchronousFetchRequest error: \(error)")
        }
    }
    
    func csvToCoreData(data: String){
        
        let entity = NSEntityDescription.entity(forEntityName: "Word", in: context)
        
        let rows = data.components(separatedBy: "\n")
        //var dictT = Dictionary<String,Dictionary<String,String>>()
        var i = 0
        for row in rows {
            if (i > 0){
                
                let newWord = NSManagedObject(entity: entity!, insertInto: context)
                
                let columns = row.components(separatedBy: ",")
                newWord.setValue(columns[0], forKey: "word")
                if (columns.count > 1)
                {
                    let definition: String? = columns[2]
                    if definition != nil{
                        newWord.setValue(definition, forKey: "definition")
                    }
                }
                
                if (columns.count > 2)
                {
                    let translation: String? = columns[3]
                    if translation != nil{
                        newWord.setValue(translation, forKey: "translation")
                    }
                }
                
                if (columns.count > 5)
                {
                    let oxford: String? = columns[6]
                    if oxford != nil{
                        newWord.setValue(oxford, forKey: "oxford")
                    }
                }
            }
            i = i+1
        }
        
        do {
            try context.save()
        } catch {
            print("Failed saving")
        }
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
        // Release any cached data, images, etc that aren't in use.
    }

    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            // Do any desired updates to SceneKit here.
        }
    }
    
    // MARK: - Status Bar: Hide
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    // MARK: - Interaction
    
    @objc func handleTap(gestureRecognize: UITapGestureRecognizer) {
        searchAsynchronous(searchStr:latestPrediction)
    }
    
    func createNewBubbleParentNode(_ text : String) -> SCNNode {
        // Warning: Creating 3D Text is susceptible to crashing. To reduce chances of crashing; reduce number of polygons, letters, smoothness, etc.
        
        // TEXT BILLBOARD CONSTRAINT
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.Y

        
        // BUBBLE-TEXT
        let bubble = SCNText(string:text, extrusionDepth: CGFloat(bubbleDepth))
        var font = UIFont(name: "Futura", size: 0.15)
        font = font?.withTraits(traits: .traitBold)
        bubble.font = font
        bubble.alignmentMode = kCAAlignmentCenter
        bubble.firstMaterial?.diffuse.contents = UIColor.orange
        bubble.firstMaterial?.specular.contents = UIColor.white
        bubble.firstMaterial?.isDoubleSided = true
        // bubble.flatness // setting this too low can cause crashes.
        bubble.chamferRadius = CGFloat(bubbleDepth)
        
        // BUBBLE NODE
        let (minBound, maxBound) = bubble.boundingBox
        let bubbleNode = SCNNode(geometry: bubble)
        // Centre Node - to Centre-Bottom point
        bubbleNode.pivot = SCNMatrix4MakeTranslation( (maxBound.x - minBound.x)/2, minBound.y, bubbleDepth/2)
        // Reduce default text size
        bubbleNode.scale = SCNVector3Make(0.2, 0.2, 0.2)
        
        // CENTRE POINT NODE
        let sphere = SCNSphere(radius: 0.005)
        sphere.firstMaterial?.diffuse.contents = UIColor.cyan
        let sphereNode = SCNNode(geometry: sphere)
        
        // BUBBLE PARENT NODE
        let bubbleNodeParent = SCNNode()
        bubbleNodeParent.addChildNode(bubbleNode)
        bubbleNodeParent.addChildNode(sphereNode)
        bubbleNodeParent.constraints = [billboardConstraint]
        
        return bubbleNodeParent
    }
    
    // MARK: - CoreML Vision Handling
    
    func loopCoreMLUpdate() {
        // Continuously run CoreML whenever it's ready. (Preventing 'hiccups' in Frame Rate)
        
        dispatchQueueML.async {
            // 1. Run Update.
            self.updateCoreML()
            
            // 2. Loop this function.
            self.loopCoreMLUpdate()
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
            print(classifications)
            print("--")
            
            // Display Debug Text on screen
            var debugText:String = ""
            debugText += classifications
            self.debugTextView.text = debugText
            
            // Store the latest prediction
            var objectName:String = "…"
            objectName = classifications.components(separatedBy: "-")[0]
            objectName = objectName.components(separatedBy: ",")[0]
            self.latestPrediction = objectName
            
        }
    }
    
    func updateCoreML() {
        ///////////////////////////
        // Get Camera Image as RGB
        let pixbuff : CVPixelBuffer? = (sceneView.session.currentFrame?.capturedImage)
        if pixbuff == nil { return }
        let ciImage = CIImage(cvPixelBuffer: pixbuff!)
        // Note: Not entirely sure if the ciImage is being interpreted as RGB, but for now it works with the Inception model.
        // Note2: Also uncertain if the pixelBuffer should be rotated before handing off to Vision (VNImageRequestHandler) - regardless, for now, it still works well with the Inception model.
        
        ///////////////////////////
        // Prepare CoreML/Vision Request
        let imageRequestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        // let imageRequestHandler = VNImageRequestHandler(cgImage: cgImage!, orientation: myOrientation, options: [:]) // Alternatively; we can convert the above to an RGB CGImage and use that. Also UIInterfaceOrientation can inform orientation values.
        
        ///////////////////////////
        // Run Image Request
        do {
            try imageRequestHandler.perform(self.visionRequests)
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
