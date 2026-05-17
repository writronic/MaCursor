# Contributing to MaCursor

Thanks for your interest in contributing to MaCursor! Here's how you can help.

Before starting any work, please check the [issue tracker](https://github.com/writronic/MaCursor/issues) to avoid duplicates and to see if someone is already working on it. For significant changes, open an issue first to discuss the approach.

## Bug Reports & Feature Requests

Use the Bug Report or Feature Request template when opening a new issue. Search existing issues first — including closed ones — to avoid duplicates.

## Contribution Workflow

1. Fork and clone the repository.
2. Open `MaCursor.xcodeproj` in Xcode 16+.
3. Create a feature branch from `main`.
4. Commit your changes, test them, and push to your fork.
5. Open a Pull Request against `main` using the [PR template](PULL_REQUEST_TEMPLATE.md).

Tips for your pull request:

- Submit separate PRs for separate features — avoid bundling unrelated changes.
- Don't include unintended file changes (e.g. `project.pbxproj` signing identity changes, storyboard diffs you didn't touch).
- If `main` has been updated before your change was merged, rebase your branch:
  ```sh
  git rebase upstream/main
  ```

## Translations

MaCursor supports 10 languages. To add or improve a translation:

1. Navigate to `MaCursor/Resources/l10n/`.
2. Find the `.lproj` folder for your language (or create one).
3. Edit the `Localizable.strings` file.
4. Only modify `en.lproj` and your target language — do not include changes for other languages.
5. Open a Pull Request with your changes.

## Submitting a Theme to the Gallery

We'd love to grow the built-in theme gallery with community contributions! If you've created a cursor theme you'd like to share:

1. **Create your theme** in MaCursor using the theme editor.
2. **Locate the file** — right-click the theme in the library → **Show in Finder** to find the `.cursor` file.
3. **Fork this repository** and place your `.cursor` file inside the `themes/` directory.
4. **Open a Pull Request** with:
   - A short description of the theme (style, inspiration, etc.)
   - A screenshot or preview of the cursor set
5. Once reviewed and merged, your theme will ship with the next release of MaCursor.

> [!NOTE]
> By submitting a theme you confirm that all artwork is original or properly licensed, and you agree to distribute it under the project's [GPL-3.0 license](../LICENSE).

## Guidelines

- Stay consistent with the [macOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/macos/).
- Use SwiftUI for new UI work.
- Keep changes focused and well-tested.
- Add comments when necessary.

Thank you for helping make MaCursor better!
