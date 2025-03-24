//
//  FeedController.swift
//  Instagram
//
//  Created by Diana Crihan on 08.06.2024.
//

import UIKit
import Firebase

private let reuseIdentifier = "Cell"

protocol FeedControllerDelegate: AnyObject {
    func didLikePost(cell: FeedCell)
}

class FeedController: UICollectionViewController {
    
    //MARK: - Properties
    
    weak var delegate: FeedCellDelegate?
    
    //MARK: - Lifecycle
    
    private var posts = [Post]() {
        didSet { collectionView.reloadData() }
    }
    
    var post: Post?
    //    {
    //        didSet { collectionView.reloadData() }
    //    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        fetchPosts()
        
//        if post != nil {
//            checkIfUserLikedPosts()
//        }
    }
    
    //MARK: - Actions
    
    @objc func handleRefresh () {
        posts.removeAll()
        fetchPosts()
    }
    
    @objc func handleLogout() {
        do {
            try Auth.auth().signOut()
            let controller = LoginController()
            controller.delegate = self.tabBarController as? MainTabController
            let nav = UINavigationController(rootViewController: controller)
            nav.modalPresentationStyle = .fullScreen
            self.present(nav, animated: true)
        } catch {
            print("DEBUG: Failed to sign out")
        }
    }
    
    //MARK: - API
    
    func fetchPosts() {
        if post != nil {
            checkIfUserLikedPosts()
        } else {
            PostService.fetchFeedPosts { posts in
                DispatchQueue.main.async {
                    var posts = posts
                    posts.sort { $0.timestamp.seconds > $1.timestamp.seconds }
                    
                    self.posts = posts
                    self.checkIfUserLikedPosts()
//                    self.collectionView.refreshControl?.endRefreshing()
                    self.collectionView.reloadData()
                }
            }
        }
    }

    func checkIfUserLikedPosts() {
        if let post = post {
            PostService.checkIfUserLikedPost(post: post) { didLike in
                PostService.fetchPost(withPostId: post.postId) { post in
                    DispatchQueue.main.async {
                        self.post = post
                        self.post?.didLike = didLike
                        self.collectionView.reloadData()
//                        self.collectionView.refreshControl?.endRefreshing()
                    }
                }
            }
        } else {
            let group = DispatchGroup()
            
            self.posts.enumerated().forEach { (index, post) in
                group.enter()
                
                PostService.checkIfUserLikedPost(post: post) { didLike in
                    self.posts[index].didLike = didLike
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                self.collectionView.reloadData()
                self.collectionView.refreshControl?.endRefreshing()
            }
        }
    }


    
    //MARK: - Helpers
    
    func configureUI() {
        collectionView.backgroundColor = .white
        
        collectionView.register(FeedCell.self, forCellWithReuseIdentifier: reuseIdentifier)
        
        if post == nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Logout", style: .plain, target: self, action: #selector(handleLogout))
        }
        
        navigationItem.title = "Feed"
        
        let refresher = UIRefreshControl()
        refresher.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        collectionView.refreshControl = refresher
    }
}

//MARK: - UICollectionViewDataSource

extension FeedController {
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // If post is nil, show the whole array of posts. Otherwise, show only one post
        return post == nil ? posts.count : 1
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! FeedCell
        cell.delegate = self
        
        // Show one or multiple posts
        if let post = post {
            cell.viewModel = PostViewModel(post: post)
        } else {
            cell.viewModel = PostViewModel(post: posts[indexPath.row])
        }
        
        return cell
    }
}

//MARK: - UICollectionViewDelegateFlowLayout

// Edit the size of the cells
extension FeedController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var height: CGFloat = 8 + 40 // Top spacing and profile image height
                let width = collectionView.frame.width
                
                // Calculate captionLabel height
                if let post = post {
                    let viewModel = PostViewModel(post: post)
                    let captionHeight = viewModel.caption.height(withConstrainedWidth: width - 16, font: UIFont.systemFont(ofSize: 14))
                    height += captionHeight
                } else {
                    let post = posts[indexPath.row]
                    let viewModel = PostViewModel(post: post)
                    let captionHeight = viewModel.caption.height(withConstrainedWidth: width - 16, font: UIFont.systemFont(ofSize: 14))
                    height += captionHeight
                }
                
                // Add height for post image view
                height += width
                
                // Add height for action buttons
                height += 50
                
                // Add height for likes label and timestamp
                height += 60
                
                return CGSize(width: width, height: height)
    }
}

//MARK: - FeedCellDelegate

extension FeedController: FeedCellDelegate {
    
    func cell(_ cell: FeedCell, wantsToShowCommentsFor post: Post) {
        let controller = CommentController(post: post)
        navigationController?.pushViewController(controller, animated: true)
    }
    
    func cell(_ cell: FeedCell, didLike post: Post) {
        guard let tab = self.tabBarController as? MainTabController else { return }
        guard let user = tab.user else { return }
        
//        cell.likeButton.isEnabled = false
        
        if post.didLike {
            // Unlike post
            PostService.unlikePost(post: post) { error in
                if let error = error {
                    print("Error unlinking post: \(error.localizedDescription)")
//                    cell.likeButton.isEnabled = true
                    return
                }
                
                DispatchQueue.main.async {
                    if var viewModel = cell.viewModel {
                        viewModel.post.didLike = false
                        viewModel.post.likes -= 1
                        cell.viewModel = viewModel
                        cell.configure()
                    }
//                    cell.likeButton.isEnabled = true
                }
            }
        } else {
            // Like post
            PostService.likePost(post: post) { error in
                if let error = error {
                    print("Error liking post: \(error.localizedDescription)")
                    cell.likeButton.isEnabled = true
                    return
                }
                
                NotificationService.uploadNotification(toUid: post.ownerUid, fromUser: user, type: .like, post: post)
                
                DispatchQueue.main.async {
                    if var viewModel = cell.viewModel {
                        viewModel.post.didLike = true
                        viewModel.post.likes += 1
                        cell.viewModel = viewModel
                        cell.configure()
                    }
                    cell.likeButton.isEnabled = true
                }
            }
        }
    }
    
    func cell(_ cell: FeedCell, didTapUsernameFor user: User) {
        let controller = ProfileController(user: user)
        navigationController?.pushViewController(controller, animated: true)
    }
    
    func cell(_ cell: FeedCell, didTapLikesLabelFor post: Post) {
        let controller = SearchController()
        controller.showLikes = true
        controller.post = post
        navigationController?.pushViewController(controller, animated: true)
    }
}
