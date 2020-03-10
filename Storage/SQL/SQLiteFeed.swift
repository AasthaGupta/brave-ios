/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import XCGLogger
import Deferred

private let log = Logger.syncLogger

class FeedStorageError: MaybeErrorType {
    var message: String
    init(_ message: String) {
        self.message = message
    }
    var description: String {
        return message
    }
}

open class SQLiteFeed {
    let db: BrowserDB

    let allColumns = ["id", "publish_time", "feed_source", "url", "domain", "img", "title", "description", "content_type", "publisher_id", "publisher_name", "publisher_logo", "session_displayed", "removed", "liked", "unread"].joined(separator: ",")

    required public init(db: BrowserDB) {
        self.db = db
    }
}

extension SQLiteFeed: Feed {
    public func getAvailableRecords() -> Deferred<Maybe<[FeedItem]>> {
        let sql = "SELECT \(allColumns) FROM items ORDER BY publish_time DESC"
        return db.runQuery(sql, args: nil, factory: SQLiteFeed.FeedItemFactory) >>== { cursor in
            return deferMaybe(cursor.asArray())
        }
    }

    public func deleteRecord(_ record: FeedItem) -> Success {
        let sql = "DELETE FROM items WHERE id = ?"
        let args: Args = [record.id]
        return db.run(sql, withArgs: args)
    }

    public func deleteAllRecords() -> Success {
        let sql = "DELETE FROM items"
        return db.run(sql)
    }

    public func createRecord(publishTime: Timestamp, feedSource: String, url: String, domain: String, img: String, title: String, description: String, contentType: String, publisherId: String, publisherName: String, publisherLogo: String) -> Deferred<Maybe<FeedItem>> {
        return db.transaction { connection -> FeedItem in
            let insertSQL = "INSERT INTO items (publish_time, feed_source, url, domain, img, title, description, content_type, publisher_id, publisher_name, publisher_logo, session_displayed) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            let insertArgs: Args = [publishTime, feedSource, url, domain, img, title, description, contentType, publisherId, publisherName, publisherLogo, ""]
            let lastInsertedRowID = connection.lastInsertedRowID

            try connection.executeChange(insertSQL, withArgs: insertArgs)

            if connection.lastInsertedRowID == lastInsertedRowID {
                throw FeedStorageError("Unable to insert FeedItem")
            }

            let querySQL = "SELECT \(self.allColumns) FROM items WHERE id = ? LIMIT 1"
            let queryArgs: Args = [connection.lastInsertedRowID]

            let cursor = connection.executeQuery(querySQL, factory: SQLiteFeed.FeedItemFactory, withArgs: queryArgs)

            let items = cursor.asArray()
            if let item = items.first {
                return item
            } else {
                throw FeedStorageError("Unable to get inserted FeedItem")
            }
        }
    }
    
    public func getRecords(session: String, limit: Int, requiresImage: Bool, contentType: FeedContentType) -> Deferred<Maybe<[FeedItem]>> {
        var sql = "SELECT \(allColumns) FROM items WHERE session_displayed != ? AND removed = 0"
        
        if requiresImage {
            sql = sql + " AND img != ''"
        }
        
        if contentType != .any {
            sql = sql + " AND content_type = '\(contentType.rawValue)'"
        }
        
        sql = sql + " ORDER BY publish_time DESC LIMIT ?"
        
        let args: Args = [session, limit]
        return db.runQuery(sql, args: args, factory: SQLiteFeed.FeedItemFactory) >>== { cursor in
            return deferMaybe(cursor.asArray())
        }
    }
    
    public func getRecords(session: String, publisher: String, limit: Int, requiresImage: Bool, contentType: FeedContentType) -> Deferred<Maybe<[FeedItem]>> {
        var sql = "SELECT \(allColumns) FROM items WHERE session_displayed != ? AND publisher_id = ? AND removed = 0"
        
        if requiresImage {
            sql = sql + " AND img != ''"
        }
        
        if contentType != .any {
            sql = sql + " AND content_type = '\(contentType.rawValue)'"
        }
        
        sql = sql + " ORDER BY publish_time DESC LIMIT ?"
        
        let args: Args = [session, publisher, limit]
        return db.runQuery(sql, args: args, factory: SQLiteFeed.FeedItemFactory) >>== { cursor in
            return deferMaybe(cursor.asArray())
        }
    }

    public func getRecordWithURL(_ url: String) -> Deferred<Maybe<FeedItem>> {
        let sql = "SELECT \(allColumns) FROM items WHERE url = ? AND removed = 0 LIMIT 1"
        let args: Args = [url]
        return db.runQuery(sql, args: args, factory: SQLiteFeed.FeedItemFactory) >>== { cursor in
            let items = cursor.asArray()
            if let item = items.first {
                return deferMaybe(item)
            } else {
                return deferMaybe(FeedStorageError("Can't create FCR from row"))
            }
        }
    }

    public func updateRecord(_ id: Int, session: String) -> Deferred<Maybe<FeedItem>> {
        return db.transaction { connection -> FeedItem in
            let updateSQL = "UPDATE items SET session_displayed = ? WHERE id = ?"
            let updateArgs: Args = [session, id]

            try connection.executeChange(updateSQL, withArgs: updateArgs)

            let querySQL = "SELECT \(self.allColumns) FROM items WHERE id = ? LIMIT 1"
            let queryArgs: Args = [id]

            let cursor = connection.executeQuery(querySQL, factory: SQLiteFeed.FeedItemFactory, withArgs: queryArgs)

            let items = cursor.asArray()
            if let item = items.first {
                return item
            } else {
                throw FeedStorageError("Unable to get updated FeedItem")
            }
        }
    }
    
    public func updateRecords(_ ids: [Int], session: String) -> Deferred<Maybe<FeedItem>> {
        return db.transaction { connection -> FeedItem in
            let idsString = ids.map { String($0) }.joined(separator: ",")
            let updateSQL = "UPDATE items SET session_displayed = ? WHERE id IN (\(idsString))"
            let updateArgs: Args = [session]
            
            try connection.executeChange(updateSQL, withArgs: updateArgs)

            let querySQL = "SELECT \(self.allColumns) FROM items WHERE id IN (\(idsString))"
            let cursor = connection.executeQuery(querySQL, factory: SQLiteFeed.FeedItemFactory, withArgs: nil)

            let items = cursor.asArray()
            if let item = items.first {
                return item
            } else {
                throw FeedStorageError("Unable to get updated FeedItem")
            }
        }
    }
    
    public func markAsRead(_ id: Int, read: Bool) -> Deferred<Maybe<FeedItem>> {
       return db.transaction { connection -> FeedItem in
           let updateSQL = "UPDATE items SET unread = ? WHERE id = ?"
           let updateArgs: Args = [!read, id]

           try connection.executeChange(updateSQL, withArgs: updateArgs)

           let querySQL = "SELECT \(self.allColumns) FROM items WHERE id = ? LIMIT 1"
           let queryArgs: Args = [id]

           let cursor = connection.executeQuery(querySQL, factory: SQLiteFeed.FeedItemFactory, withArgs: queryArgs)

           let items = cursor.asArray()
           if let item = items.first {
               return item
           } else {
               throw FeedStorageError("Unable to get updated FeedItem")
           }
        }
    }
    
    public func remove(_ id: Int) -> Success {
        let sql = "UPDATE items SET removed = 1 WHERE id = ?"
        let args: Args = [id]
        return db.run(sql, withArgs: args)
    }
    
    public func remove(_ publisherId: String) -> Success {
        let sql = "UPDATE items SET removed = 1 WHERE publisher_id = ?"
        let args: Args = [publisherId]
        return db.run(sql, withArgs: args)
    }

    fileprivate class func FeedItemFactory(_ row: SDRow) -> FeedItem {
        let id = row["id"] as! Int
        let publishTime = row.getTimestamp("publish_time")!
        let feedSource = row["feed_source"] as! String
        let url = row["url"] as! String
        let domain = row["domain"] as! String
        let img = row["img"] as! String
        let title = row["title"] as! String
        let description = row["description"] as! String
        let contentType = row["content_type"] as! String
        let publisherId = row["publisher_id"] as! String
        let publisherName = row["publisher_name"] as! String
        let publisherLogo = row["publisher_logo"] as! String
        let sessionDisplayed = row["session_displayed"] as! String
        let removed = row.getBoolean("removed")
        let liked = row.getBoolean("liked")
        let unread = row.getBoolean("unread")
        return FeedItem(id: id, publishTime: publishTime, feedSource: feedSource, url: url, domain: domain, img: img, title: title, description: description, contentType: contentType, publisherId: publisherId, publisherName: publisherName, publisherLogo: publisherLogo, sessionDisplayed: sessionDisplayed, removed: removed, liked: liked, unread: unread)
    }
}