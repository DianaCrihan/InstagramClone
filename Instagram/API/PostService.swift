//
//  PostService.swift
//  Instagram
//
//  Created by Diana Crihan on 27.06.2024.
//

import UIKit
import Firebase

struct PostService {
    
    static func uploadPost(caption: String, image: UIImage, user: User, completion: @escaping(FirestoreCompletion)) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        ImageUploader.uploadImage(image: image) { imageUrl in
            let data = ["caption": caption, "timestamp": Timestamp(date: Date()), "likes": 0, "imageUrl": imageUrl, "ownerUid": uid, "ownerImageUrl": user.profileImageUrl, "ownerUsername": user.username] as [String: Any]
                        
            let docRef = COLLECTION_POSTS.addDocument(data: data, completion: completion)
            
            self.updateUserFeedAfterPost(postId: docRef.documentID)
        }
    }
    
    static func fetchPosts(completion: @escaping([Post]) -> Void) {
        COLLECTION_POSTS.order(by: "timestamp", descending: true).getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else { return }
            
            var posts = documents.map({ Post(postId: $0.documentID, dictionary: $0.data())})
//            posts.sort(by: { $0.timestamp.seconds > $1.timestamp.seconds })

            completion(posts)
        }
    }
    
    // Gives back all the posts of a certain user
    static func fetchPosts(forUser uid: String, completion: @escaping([Post]) -> Void) {
        let query = COLLECTION_POSTS.whereField("ownerUid", isEqualTo: uid)
        
        query.getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else { return }
            
            var posts = documents.map( { Post(postId: $0.documentID, dictionary: $0.data()) } )
            posts.sort { post1, post2  -> Bool in
                return post1.timestamp.seconds > post2.timestamp.seconds
            }
            
            completion(posts)
        }
    }
    
    static func fetchPost(withPostId postId: String, completion: @escaping(Post) -> Void) {
        COLLECTION_POSTS.document(postId).getDocument { snapshot, _ in
            guard let snapshot = snapshot else { return }
            guard let data = snapshot.data() else { return }
            let post = Post(postId: snapshot.documentID, dictionary: data)
            completion(post)
        }
    }
    
    static func likePost(post: Post, completion: @escaping(FirestoreCompletion)) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        COLLECTION_POSTS.document(post.postId).updateData(["likes": post.likes + 1])
        
        COLLECTION_POSTS.document(post.postId).collection("post-likes").document(uid).setData([:]) { _ in
            COLLECTION_USERS.document(uid).collection("user-likes").document(post.postId).setData([:], completion: completion)
        }
    }
    
    static func unlikePost(post: Post, completion: @escaping(FirestoreCompletion)) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Only unlike a post if the number of likes is greater than 0
        guard post.likes > 0 else { return }
        COLLECTION_POSTS.document(post.postId).updateData(["likes": post.likes - 1])
        
        // Delete the uid of the user who unlike the post from the posts document
        COLLECTION_POSTS.document(post.postId).collection("post-likes").document(uid).delete { _ in
            // Delete the postID of the post that has been unliked from the user document
            COLLECTION_USERS.document(uid).collection("user-likes").document(post.postId).delete(completion: completion)
        }
    }
    
    static func checkIfUserLikedPost(post: Post, completion: @escaping(Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        COLLECTION_USERS.document(uid).collection("user-likes").document(post.postId).getDocument { snapshot, _ in
            guard let didLike = snapshot?.exists else { return }
            print(didLike)
            completion(didLike)
        }
    }
    
    static func fetchUsers(postLiked: Post, completion: @escaping([User]) -> Void) {
        var users = [User]()
        let dispatchGroup = DispatchGroup()

        COLLECTION_POSTS.document(postLiked.postId).collection("post-likes").getDocuments { snapshot, error in
            guard let snapshot = snapshot else { return }
            
            for document in snapshot.documents {
                let uid = document.documentID
                dispatchGroup.enter() // Enter the dispatch group before starting the async task
                UserService.fetchUser(withUid: uid) { user in
                    DispatchQueue.main.async {
                        users.append(user)
                        dispatchGroup.leave() // Leave the dispatch group after the async task is completed
                    }
                }
            }

            dispatchGroup.notify(queue: .main) {
                // This block will be called once all fetchUser tasks have completed
                completion(users)
            }
        }
    }
    
    static func fetchFeedPosts(completion: @escaping([Post]) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var posts = [Post]()
        
        COLLECTION_USERS.document(uid).collection("user-feed").getDocuments { snapshot, error in
            snapshot?.documents.forEach({ document in
                fetchPost(withPostId: document.documentID) { post in
                    posts.append(post)
                    
                    posts.sort(by: { $0.timestamp.seconds > $1.timestamp.seconds })
                    
                    completion(posts)
                }
            })
        }
    }
    
    static func updateUserFeedAfterFollowing(user: User, didFollow: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        let query = COLLECTION_POSTS.whereField("ownerUid", isEqualTo: user.uid)
        query.getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else { return }
            // Store all the post IDs that we need to add to our user's feed
            let docIDs = documents.map({ $0.documentID })
            
            
            docIDs.forEach { id in
                if didFollow {
                    COLLECTION_USERS.document(uid).collection("user-feed").document(id).setData([:])
                } else {
                    COLLECTION_USERS.document(uid).collection("user-feed").document(id).delete()
                }
            }
        }
    }
    
    private static func updateUserFeedAfterPost(postId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        COLLECTION_FOLLOWERS.document(uid).collection("user-followers").getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else { return }
            
            documents.forEach { document in
                COLLECTION_USERS.document(document.documentID).collection("user-feed").document(postId).setData([:])
            }
            
            COLLECTION_USERS.document(uid).collection("user-feed").document(postId).setData([:])
        }
    }

}

