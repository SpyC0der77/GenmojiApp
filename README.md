# GenmojiApp 🎨

GenmojiApp is an iOS Messages extension that allows users to generate and share custom emoji stickers directly in their conversations.

## Features ✨

- Generate custom emoji stickers using text prompts
- Automatic background removal for clean sticker appearance
- Local storage of generated stickers for quick reuse
- Seamless integration with iOS Messages
- Responsive grid layout for sticker display

## Setup & Installation 📱

1. Create a new Xcode project:
   - Open Xcode
   - Choose "Create a new Xcode project"
   - Select "Messages Extension" as the template
   - Fill in your project details and create

2. Implement the ImageCell:
   - Create a new file called `ImageCell.swift` and paste the content of `ImageCell.swift` from this repo into the one in your project.

3. Update MessagesViewController:
   - Copy the contents of the file `MessagesViewController.swift` into your `MessagesViewController.swift` in your project.

5. Build and run the Messages extension target



## Usage 💬

1. Open Messages app
2. Select Genmoji from the Messages apps drawer
3. Enter a text prompt describing your desired emoji
4. Tap generate to create your custom sticker
5. Select the generated sticker to send in your conversation

## Technical Details 🛠️

- Built for iOS Messages platform
- Uses UIKit and Messages framework
- Implements custom image generation and processing
- Features local storage management for generated stickers
- Responsive collection view layout for optimal display

## Requirements 📋

- iOS 14.0+
- Xcode 13.0+
- Active Apple Developer account

## License 📄

MIT
