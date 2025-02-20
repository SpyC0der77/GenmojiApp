import Messages
import UIKit

/// Represents a single generated image.
struct GeneratedImage: Equatable {
    let id: UUID
    let image: UIImage

    static func == (lhs: GeneratedImage, rhs: GeneratedImage) -> Bool {
        lhs.id == rhs.id
    }
}

/// Decodable structure matching the JSON returned by the Hugging Face Inference API.
private struct HFInferenceResponse: Decodable {
    let image: String?
}

/// A simple storage manager that handles saving and loading sticker images.
class StickerStorageManager {
    static let shared = StickerStorageManager()
    let stickersDirectory: URL

    private init() {
        let fileManager = FileManager.default
        // Get the Documents directory.
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        stickersDirectory = documentsURL.appendingPathComponent("Stickers")
        // Create the folder if it doesn't exist.
        if !fileManager.fileExists(atPath: stickersDirectory.path) {
            do {
                try fileManager.createDirectory(at: stickersDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Error creating stickers directory: \(error)")
            }
        }
    }

    /// Saves the given image with the specified UUID.
    func saveSticker(image: UIImage, id: UUID) {
        let fileURL = stickersDirectory.appendingPathComponent("\(id.uuidString).png")
        if let data = image.pngData() {
            do {
                try data.write(to: fileURL)
            } catch {
                print("Error saving sticker image: \(error)")
            }
        }
    }

    /// Loads all saved stickers from the stickers directory.
    func loadStickers() -> [GeneratedImage] {
        var images = [GeneratedImage]()
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: stickersDirectory, includingPropertiesForKeys: nil)
            // Sort files by creation date (newest first).
            let sortedURLs = fileURLs.sorted {
                let attr0 = try? FileManager.default.attributesOfItem(atPath: $0.path)
                let attr1 = try? FileManager.default.attributesOfItem(atPath: $1.path)
                let date0 = attr0?[.creationDate] as? Date ?? Date.distantPast
                let date1 = attr1?[.creationDate] as? Date ?? Date.distantPast
                return date0 > date1
            }

            for fileURL in sortedURLs {
                if let data = try? Data(contentsOf: fileURL),
                   let image = UIImage(data: data) {
                    let fileName = fileURL.deletingPathExtension().lastPathComponent
                    if let uuid = UUID(uuidString: fileName) {
                        images.append(GeneratedImage(id: uuid, image: image))
                    }
                }
            }
        } catch {
            print("Error loading stickers: \(error)")
        }
        return images
    }
}

class MessagesViewController: MSMessagesAppViewController {

    // MARK: - UI Components

    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Enter your prompt..."
        searchBar.searchBarStyle = .minimal
        return searchBar
    }()

    private let submitButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Submit", for: .normal)
        return button
    }()

    private lazy var searchContainer: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [searchBar, submitButton])
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .fill
        stackView.distribution = .fill
        return stackView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Recents"
        label.font = UIFont.boldSystemFont(ofSize: 18)
        label.textAlignment = .center
        return label
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.backgroundColor = .systemBackground
        collectionView.register(ImageCell.self, forCellWithReuseIdentifier: "ImageCell")
        return collectionView
    }()

    // MARK: - Generating Screen UI

    private let generatingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0, alpha: 0.7)
        view.isHidden = true
        return view
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        return indicator
    }()

    private let generatingLabel: UILabel = {
        let label = UILabel()
        label.text = "Generating..."
        label.textColor = .white
        label.font = UIFont.boldSystemFont(ofSize: 20)
        return label
    }()

    // MARK: - Hugging Face & remove.bg Configuration

    /// Replace with your actual Hugging Face token if needed.
    private let hfAccessToken = "API KEY"
    /// The model name for text-to-image generation.
    private let modelName = "stabilityai/stable-diffusion-2"
    /// Replace with your remove.bg API key.
    private let removeBgAPIKey = "API KEY"

    // MARK: - Data

    /// Currently displayed images (results or recents).
    private var images: [GeneratedImage] = []
    /// Stores recently generated images.
    private var recentImages: [GeneratedImage] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        searchBar.delegate = self
        submitButton.addTarget(self, action: #selector(submitButtonTapped), for: .touchUpInside)

        // Load recents from local storage.
        recentImages = StickerStorageManager.shared.loadStickers()
        images = recentImages
        titleLabel.text = "Recents"
        collectionView.reloadData()
    }

    // When iMessage changes from compact to expanded (or vice versa),
    // force the collection view to re-layout so it can show more columns if there's space.
    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.willTransition(to: presentationStyle)
        collectionView.collectionViewLayout.invalidateLayout()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        view.addSubview(searchContainer)
        searchContainer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        // Add the generating overlay view.
        view.addSubview(generatingView)
        generatingView.translatesAutoresizingMaskIntoConstraints = false
        generatingView.addSubview(activityIndicator)
        generatingView.addSubview(generatingLabel)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        generatingLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Search container at the top.
            searchContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            searchContainer.heightAnchor.constraint(equalToConstant: 44),

            // Title label below the search container.
            titleLabel.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            titleLabel.heightAnchor.constraint(equalToConstant: 30),

            // Collection view below the title label.
            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Generating view covers the entire view.
            generatingView.topAnchor.constraint(equalTo: view.topAnchor),
            generatingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            generatingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            generatingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Center the activity indicator.
            activityIndicator.centerXAnchor.constraint(equalTo: generatingView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: generatingView.centerYAnchor, constant: -20),

            // Place the generating label below the activity indicator.
            generatingLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            generatingLabel.centerXAnchor.constraint(equalTo: generatingView.centerXAnchor)
        ])
    }

    // MARK: - Generating Screen Helpers

    private func showGeneratingScreen() {
        DispatchQueue.main.async {
            self.generatingView.isHidden = false
            self.generatingLabel.text = "Generating..."
            self.activityIndicator.startAnimating()
        }
    }

    private func hideGeneratingScreen() {
        DispatchQueue.main.async {
            self.generatingView.isHidden = true
            self.activityIndicator.stopAnimating()
        }
    }

    // MARK: - Generate Image (HTTP Request)

    /// Makes an HTTP POST request to the Hugging Face Inference API for text-to-image generation.
    private func generateImage(prompt: String) {
        showGeneratingScreen()
        Task {
            do {
                guard let url = URL(string: "https://router.huggingface.co/hf-inference/models/fofr/sdxl-emoji") else {
                    print("Invalid URL.")
                    hideGeneratingScreen()
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if !hfAccessToken.isEmpty {
                    request.setValue("Bearer \(hfAccessToken)", forHTTPHeaderField: "Authorization")
                }
                
                let body: [String: Any] = [
                    "inputs": prompt + " emoji",
                    "options": [
                        "wait_for_model": true
                    ]
                ]
                let jsonData = try JSONSerialization.data(withJSONObject: body)
                request.httpBody = jsonData
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Invalid response")
                    hideGeneratingScreen()
                    return
                }
                
                // Check for non-200 status code.
                if httpResponse.statusCode != 200 {
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("Inference API error (status \(httpResponse.statusCode)): \(message)")
                    hideGeneratingScreen()
                    return
                }
                
                // Inspect the content type.
                if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
                   contentType.contains("image/"),
                   let uiImage = UIImage(data: data) {

                    // --- Update the label to "Removing Background" before calling remove.bg
                    DispatchQueue.main.async {
                        self.generatingLabel.text = "Removing Background"
                    }

                    // Call remove.bg API to remove the background.
                    // If background removal fails, fall back to the original image.
                    let processedImage = await removeBackgroundUsingRemoveBg(for: uiImage) ?? uiImage
                    
                    let generated = GeneratedImage(id: UUID(), image: processedImage)
                    
                    // Save the newly generated sticker to local storage.
                    StickerStorageManager.shared.saveSticker(image: processedImage, id: generated.id)
                    
                    DispatchQueue.main.async {
                        // Add the new image to the beginning of recents.
                        self.recentImages.insert(generated, at: 0)
                        // Update the images array to show recents.
                        self.images = self.recentImages
                        self.titleLabel.text = "Recents"
                        self.collectionView.reloadData()
                        self.hideGeneratingScreen()
                    }
                } else if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
                          contentType.contains("application/json") {
                    let errorJSON = try JSONSerialization.jsonObject(with: data)
                    print("Received JSON response instead of image: \(errorJSON)")
                    hideGeneratingScreen()
                } else {
                    print("Unexpected Content-Type.")
                    hideGeneratingScreen()
                }
            } catch {
                print("Error generating image: \(error)")
                hideGeneratingScreen()
            }
        }
    }
    
    // MARK: - remove.bg API Integration

    /// Uses the remove.bg API to remove the background from the given image.
    private func removeBackgroundUsingRemoveBg(for image: UIImage) async -> UIImage? {
        guard let imageData = image.pngData() else {
            print("Failed to convert image to PNG data.")
            return nil
        }
        
        guard let url = URL(string: "https://api.remove.bg/v1.0/removebg") else {
            print("Invalid remove.bg URL.")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(removeBgAPIKey, forHTTPHeaderField: "X-API-Key")
        
        // Create a unique boundary string.
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build multipart form-data body.
        var body = Data()
        
        // Append image file.
        let fieldName = "image_file"
        let fileName = "image.png"
        let mimeType = "image/png"
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(imageData)
        body.appendString("\r\n")
        
        // Append "size" parameter.
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"size\"\r\n\r\n")
        body.appendString("auto\r\n")
        
        // End boundary.
        body.appendString("--\(boundary)--\r\n")
        
        request.httpBody = body
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("remove.bg API returned a non-200 response")
                return nil
            }
            return UIImage(data: data)
        } catch {
            print("Error calling remove.bg API: \(error)")
            return nil
        }
    }

    // MARK: - Actions

    @objc private func submitButtonTapped() {
        guard let prompt = searchBar.text else { return }
        if prompt.isEmpty {
            images = recentImages
            titleLabel.text = "Recents"
            collectionView.reloadData()
        } else {
            generateImage(prompt: prompt)
        }
        searchBar.resignFirstResponder()
    }
}

// MARK: - UISearchBarDelegate
extension MessagesViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let prompt = searchBar.text else { return }
        if prompt.isEmpty {
            images = recentImages
            titleLabel.text = "Recents"
            collectionView.reloadData()
        } else {
            generateImage(prompt: prompt)
        }
        searchBar.resignFirstResponder()
    }
}

// MARK: - UICollectionViewDelegate & DataSource
extension MessagesViewController: UICollectionViewDelegate, UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return images.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ImageCell", for: indexPath) as! ImageCell
        let generatedImage = images[indexPath.item]
        cell.configure(with: generatedImage.image)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // Check if there's an active conversation.
        guard let conversation = activeConversation else {
            print("activeConversation is nil. Sticker cannot be inserted.")
            return
        }
        
        let selected = images[indexPath.item]
        
        // Add to recent images if not already there.
        if !recentImages.contains(selected) {
            recentImages.append(selected)
            // Optionally, re-save to local storage if needed.
            StickerStorageManager.shared.saveSticker(image: selected.image, id: selected.id)
        }
        
        // Resize the image to help ensure it meets sticker file size requirements.
        let maxDimension: CGFloat = 300
        let image = selected.image
        let scaleFactor = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scaleFactor, height: image.size.height * scaleFactor)
        
        guard let resizedImage = image.resized(to: newSize) else {
            print("Failed to resize image")
            return
        }
        
        // Convert the resized UIImage to PNG data.
        guard let pngData = resizedImage.pngData() else {
            print("Failed to convert image to PNG data.")
            return
        }
        
        // Create a temporary file URL.
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        
        do {
            // Write the PNG data to the temporary file.
            try pngData.write(to: tempFileURL)
            print("PNG data successfully written to \(tempFileURL)")
            
            // Create an MSSticker from the temporary file.
            let sticker = try MSSticker(contentsOfFileURL: tempFileURL, localizedDescription: "Sticker")
            
            // Insert the sticker into the active conversation.
            conversation.insert(sticker) { error in
                if let error = error {
                    print("Error inserting sticker: \(error.localizedDescription)")
                } else {
                    print("Sticker inserted successfully!")
                }
                
                // Clean up the temporary file.
                do {
                    try FileManager.default.removeItem(at: tempFileURL)
                    print("Temporary file removed.")
                } catch {
                    print("Error removing temporary file: \(error)")
                }
            }
        } catch {
            print("Error handling generated image: \(error)")
        }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout
extension MessagesViewController: UICollectionViewDelegateFlowLayout {
    
    // Smaller insets for a tighter layout
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        // 2-point inset around the edges
        return UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
    }

    // Spacing between rows
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 2
    }

    // Spacing between items in a row
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 2
    }

    // Dynamically choose 2 or 3 columns based on width
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {

        let currentWidth = collectionView.bounds.width
        let numberOfItemsPerRow: CGFloat = (currentWidth > 250) ? 3 : 2
        let spacing: CGFloat = 2
        let sectionInsets = self.collectionView(collectionView, layout: collectionViewLayout, insetForSectionAt: indexPath.section)
        
        let totalSpacing = (numberOfItemsPerRow - 1) * spacing + sectionInsets.left + sectionInsets.right
        let cellWidth = (currentWidth - totalSpacing) / numberOfItemsPerRow
        return CGSize(width: cellWidth, height: cellWidth)
    }
}

// MARK: - UIImage Resizing Helper
extension UIImage {
    func resized(to targetSize: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = self.scale
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resizedImage
    }
}

// MARK: - Data Extension for Multipart Form Building
extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.append(data)
        }
    }
}
