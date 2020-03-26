//
//  EntryController.swift
//  Journal
//
//  Created by Mark Gerrior on 3/23/20.
//  Copyright © 2020 Mark Gerrior. All rights reserved.
//

import Foundation
import CoreData

enum HTTPMethod: String {
    case post   = "POST"   // Create
    case get    = "GET"    // Read
    case put    = "PUT"    // Update/Replace
    case patch  = "PATCH"  // Update/Replace
    case delete = "DELETE" // Delete
}

class EntryController {
    
    // MARK: - Properities
    typealias CompletionHandler = (Error?) -> Void
    let baseURL = URL(string: "https://journal-lambda-gerrior.firebaseio.com/")!

    // TODO: ? Why can't I use a private(set).
    //    var entries: [Entry] {
    //        // Gets loaded each time. This is a get.
    //        // TODO: ? Is this a performance issue.
    //        loadFromPersistentStore()
    //    }
    
    init() {
        fetchEntriesFromServer()
    }
    
    // MARK: CRUD
    
    // Create
    func create(identifier: String,
                title: String,
                bodyText: String? = nil,
                timestamp: Date? = nil,
                mood: Mood = .neutral) {
        
        var datetime = Date()
        if timestamp != nil {
            datetime = timestamp!
        }
        
        let entry = Entry(identifier: identifier,
                          title: title,
                          bodyText: bodyText,
                          timestamp: datetime,
                          mood: mood,
                          context: CoreDataStack.shared.mainContext)
        
        put(entry: entry)

        do {
            try CoreDataStack.shared.save()
        } catch {
            NSLog("Error saving managed object context (after create) to CoreData: \(error)")
        }
    }

    func put(entry: Entry, completion: @escaping CompletionHandler = { _ in }) {
        let uuid = entry.identifier ?? UUID().uuidString
        let requestURL = baseURL.appendingPathComponent(uuid).appendingPathExtension("json")
        var request = URLRequest(url: requestURL)
        request.httpMethod = HTTPMethod.put.rawValue
        
        do {
            guard var representation = entry.entryRepresentation else {
                completion(NSError())
                return
            }
            representation.identifier = uuid
            entry.identifier = uuid // TODO: ? What if it didn't change?
            request.httpBody = try JSONEncoder().encode(representation)
            
        } catch {
            NSLog("Error encoding/saving entry: \(error)")
            completion(error)
        }
        
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                NSLog("Error PUTing entry to server \(error)")
                completion(error)
                return
            }

            completion(nil)
        }.resume()
    }

    // Read

    // Update
    func update(entry: Entry,
                title: String,
                bodyText: String? = nil,
                mood: Mood = .neutral) {

        entry.title = title
        entry.bodyText = bodyText
        entry.timestamp = Date()
        entry.mood = mood.rawValue
        
        put(entry: entry)

        do {
            try CoreDataStack.shared.save()
        } catch {
            NSLog("Error saving managed object context (after update) to CoreData: \(error)")
        }
    }

    private func update(entry: Entry, with representation: EntryRepresentation) {
        //entry.identifier = representation.identifier
        entry.title = representation.title
        entry.bodyText = representation.bodyText
        entry.timestamp = representation.timestamp
        entry.mood = representation.mood
    }

    /// <#Description#>
    /// - Parameter representations: EntryRepresentation objects that are fetched from Firebase
    private func updateEntries(with representations: [EntryRepresentation]) throws {
        
        /// Create a fetch request from Entry object.
        let fetchRequest: NSFetchRequest<Entry> = Entry.fetchRequest()

        /// Create a dictionary with the identifiers of the representations as the keys, and the values as the representations. To accomplish making this dictionary you will need to create a separate array of just the entry representations identifiers. You can use the zip method to combine two arrays of items together into a dictionary.
        let entriesByID = representations.filter { !$0.identifier.isEmpty }
        let identifiersToFetch = entriesByID.compactMap { $0.identifier }
        let representationsByID = Dictionary(uniqueKeysWithValues: zip(identifiersToFetch, entriesByID))
        var entriesToCreate = representationsByID

        /// Give the fetch request an NSPredicate. This predicate should see if the identifier attribute in the Entry is in identifiers array that you made from the previous step. Refer to the hint below if you need help with the predicate.
        fetchRequest.predicate = NSPredicate(format: "identifier IN %@", identifiersToFetch)

        /// Perform the fetch request on your core data stack's mainContext.
        let context = CoreDataStack.shared.mainContext
        
        do {
            /// This will return an array of Entry objects whose identifier was in the array you passed in to the predicate.
            let existingEntries = try context.fetch(fetchRequest)
            
            /// Loop through the fetched entries and call update. Then remove the entry from the dictionary. Afterwards we'll create entries from the remaining objects in the dictionary. The only ones that would remain after this loop are ones that didn't exist in Core Data already.
            for entry in existingEntries {
                guard let id = entry.identifier,
                    let representation = representationsByID[id] else { continue }
                self.update(entry: entry, with: representation)
                entriesToCreate.removeValue(forKey: id)
            }
            
            /// Create an entry for each of the values in entriesToCreate using the Entry initializer that takes in an EntryRepresentation and an NSManagedObjectContext
            for representation in entriesToCreate.values {
                Entry(entryRepresentation: representation, context: context)
            }
        } catch {
            /// Make sure you handle a potential error from the fetch method on your managed object context, as it is a throwing method.
            NSLog("Error fetching entries for UUIDs: \(error)")
        }
        
        // TODO: ? This isn't under both loops. Concerned about saving too much
        /// Under both loops, call saveToPersistentStore() to persist the changes and effectively synchronize the data in the device's persistent store with the data on the server. Since you are using an NSFetchedResultsController, as soon as you save the managed object context, the fetched results controller will observe those changes and automatically update the table view with the updated entries.
        try context.save() // Caller will handle
    }
    
    private func fetchEntriesFromServer(completion: @escaping CompletionHandler = { _ in }) {
        let requestURL = baseURL.appendingPathExtension("json")
        
        // TODO: ? Where is the GET specified? Default?
        URLSession.shared.dataTask(with: requestURL) { data, _, error in
            /// Did the call complete without error?
            if let error = error {
                NSLog("Error fetching entries: \(error)")
                completion(error)
                return
            }
            
            /// Did we get anything?
            guard let data = data else {
                NSLog("No data returned by data task")
                completion(NSError()) // Convert to ResultType
                return
            }
            
            /// Unwrap the data returned in the closure.
            do {
                var entryRepresentation: [EntryRepresentation] = []
                entryRepresentation = Array(try JSONDecoder().decode([String: EntryRepresentation].self,
                                                                      from: data).values)
                try self.updateEntries(with: entryRepresentation)
                completion(nil)

            } catch {
                NSLog("Error decoding or saving data from Firebase: \(error)")
                completion(error)
            }
        }.resume()
    }
    
    // Delete
    func delete(entry: Entry) {

        CoreDataStack.shared.mainContext.delete(entry)

        // Delete from Firebase (copy of record)
        delete(entry: entry) { _ in print("Deleted") }

        // Delete from CoreData
        do {
            try CoreDataStack.shared.save()
        } catch {
            NSLog("Error saving managed object context (after delete) to CoreData: \(error)")
        }
    }

    func delete(entry: Entry, completion: @escaping CompletionHandler = { _ in }) {
        let requestURL = baseURL.appendingPathComponent(entry.identifier!).appendingPathExtension("json")
        var request = URLRequest(url: requestURL)
        request.httpMethod = HTTPMethod.delete.rawValue
        
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                NSLog("Error DELETEing entry from server \(error)")
                completion(error)
                return
            }

            completion(nil)
        }.resume()
    }}
