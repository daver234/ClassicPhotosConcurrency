//
//  ListViewController.swift
//  ClassicPhotos
//
//  Created by Richard Turton on 03/07/2014.
//  Copyright (c) 2014 raywenderlich. All rights reserved.
//
//  Modified by Dave Rothschild May 30, 2016
//

import UIKit
import CoreImage

let dataSourceURL = NSURL(string:"http://www.raywenderlich.com/downloads/ClassicPhotosDictionary.plist")

class ListViewController: UITableViewController {
  
  // lazy var photos = NSDictionary(contentsOfURL:dataSourceURL!)!
    
    var photos = [PhotoRecord]()
    let pendingOperations = PendingOperations()
  
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.title = "Classic Photos"
    
    fetchPhotoDetails()
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  // #pragma mark - Table view data source
  
  override func tableView(tableView: UITableView?, numberOfRowsInSection section: Int) -> Int {
    return photos.count
  }
  
    // new call for row function
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("CellIdentifier", forIndexPath: indexPath) 
        
        //1 provide indication to user that cell is loading
        if cell.accessoryView == nil {
            let indicator = UIActivityIndicatorView(activityIndicatorStyle: .Gray)
            cell.accessoryView = indicator
        }
        let indicator = cell.accessoryView as! UIActivityIndicatorView
        
        //2  fetch the right data for the current row's indexpath
        let photoDetails = photos[indexPath.row]
        
        //3  set up labels
        cell.textLabel?.text = photoDetails.name
        cell.imageView?.image = photoDetails.image
        
        //4 set up activity indicator and text
        switch (photoDetails.state){
        case .Filtered:
            indicator.stopAnimating()
        case .Failed:
            indicator.stopAnimating()
            cell.textLabel?.text = "Failed to load"
        case .New, .Downloaded:
            indicator.startAnimating()
            // start operations only if the tableview is not scrolling
            if (!tableView.dragging && !tableView.decelerating) {
                self.startOperationsForPhotoRecord(photoDetails, indexPath: indexPath)
            }
        }
        
        return cell
    }
    
    // suspend operations with user starts scrolling
    override func scrollViewWillBeginDragging(scrollView: UIScrollView) {
        //1
        suspendAllOperations()
    }
    
    override func scrollViewDidEndDragging(scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // 2
        if !decelerate {
            loadImagesForOnscreenCells()
            resumeAllOperations()
        }
    }
    
    override func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        // 3
        loadImagesForOnscreenCells()
        resumeAllOperations()
    }
  
    // to start operations
    func startOperationsForPhotoRecord(photoDetails: PhotoRecord, indexPath: NSIndexPath){
        switch (photoDetails.state) {
        case .New:
            startDownloadForRecord(photoDetails, indexPath: indexPath)
        case .Downloaded:
            startFiltrationForRecord(photoDetails, indexPath: indexPath)
        default:
            NSLog("do nothing")
        }
    }
  
    
    func fetchPhotoDetails() {
        let request = NSURLRequest(URL:dataSourceURL!)
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        
        let session = NSURLSession.sharedSession()
        
        // NSURLConnection.sendAsynchronousRequest(request, queue: NSOperationQueue.mainQueue()) {response,data,error in
            
        let task = session.dataTaskWithRequest(request, completionHandler: {(data, response, error)  in
            if data != nil {
                
                do {
                    let datasourceDictionary = try NSPropertyListSerialization.propertyListWithData(data!, options: NSPropertyListReadOptions.Immutable, format: nil) as! NSDictionary
                    
                    for (key, value) in datasourceDictionary {
                        let name = key as? String
                        let url = NSURL(string: value as? String ?? "")
                        
                        if name != nil && url != nil {
                            let photoRecord = PhotoRecord(name: name!, url: url!)
                            self.photos.append(photoRecord)
                        }
                    }
                    
                    self.tableView.reloadData()
                } catch _ as NSError {
                    print("error here")
                }
                

            }
            
            
            
            if error != nil {
                let alert = UIAlertView(title:"Oops!",message:error!.localizedDescription, delegate:nil, cancelButtonTitle:"OK")
                alert.show()
            }
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
        })
        task.resume()
       
    }
    
    func startDownloadForRecord(photoDetails: PhotoRecord, indexPath: NSIndexPath){
        
        //1 see if an operation is in progress
        if pendingOperations.downloadsInProgress[indexPath] != nil {
            return
        }
        
        //2 create instance of ImageDownloader
        let downloader = ImageDownloader(photoRecord: photoDetails)
        
        //3 completion block
        downloader.completionBlock = {
            if downloader.cancelled {
                return
            }
            // need GCD to trigger reload data since we don't know what thread the completion
            // block is called on
            dispatch_async(dispatch_get_main_queue(), {
                self.pendingOperations.downloadsInProgress.removeValueForKey(indexPath)
                self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
            })
        }
        
        //4 keep track of things
        pendingOperations.downloadsInProgress[indexPath] = downloader
        
        //5  add to download queue; gets operation to start running
        pendingOperations.downloadQueue.addOperation(downloader)
    }
    
    func startFiltrationForRecord(photoDetails: PhotoRecord, indexPath: NSIndexPath){
        if pendingOperations.filtrationsInProgress[indexPath] != nil{
            return
        }
        
        let filterer = ImageFiltration(photoRecord: photoDetails)
        filterer.completionBlock = {
            if filterer.cancelled {
                return
            }
            dispatch_async(dispatch_get_main_queue(), {
                self.pendingOperations.filtrationsInProgress.removeValueForKey(indexPath)
                self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
            })
        }
        pendingOperations.filtrationsInProgress[indexPath] = filterer
        pendingOperations.filtrationQueue.addOperation(filterer)
    }
    
    func suspendAllOperations () {
        pendingOperations.downloadQueue.suspended = true
        pendingOperations.filtrationQueue.suspended = true
    }
    
    func resumeAllOperations () {
        pendingOperations.downloadQueue.suspended = false
        pendingOperations.filtrationQueue.suspended = false
    }
    
    func loadImagesForOnscreenCells () {
        //1
        if let pathsArray = tableView.indexPathsForVisibleRows {
            //2
            var allPendingOperations = Set(Array(pendingOperations.downloadsInProgress.keys))
            allPendingOperations.unionInPlace(Array(pendingOperations.filtrationsInProgress.keys))
            
            //3
            var toBeCancelled = allPendingOperations
            let visiblePaths = Set(pathsArray )
            toBeCancelled.subtractInPlace(visiblePaths)
            
            //4
            var toBeStarted = visiblePaths
            toBeStarted.subtractInPlace(allPendingOperations)
            
            // 5
            for indexPath in toBeCancelled {
                if let pendingDownload = pendingOperations.downloadsInProgress[indexPath] {
                    pendingDownload.cancel()
                }
                pendingOperations.downloadsInProgress.removeValueForKey(indexPath)
                if let pendingFiltration = pendingOperations.filtrationsInProgress[indexPath] {
                    pendingFiltration.cancel()
                }
                pendingOperations.filtrationsInProgress.removeValueForKey(indexPath)
            }
            
            // 6
            for indexPath in toBeStarted {
                let indexPath = indexPath as NSIndexPath
                let recordToProcess = self.photos[indexPath.row]
                startOperationsForPhotoRecord(recordToProcess, indexPath: indexPath)
            }
        }
    }
    
    
}
