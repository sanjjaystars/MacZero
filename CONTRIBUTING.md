# Contributing to MacZero

Thank you for your interest in contributing to MacZero! We welcome contributions to improve compatibility profiles, add new runtime translations, and refine the Apple Silicon macOS experience.

## Development Workflow

1. Clone or open the repository in Xcode or your preferred editor.
2. Ensure you have the Swift 6 toolchain and Apple Silicon command-line tools installed.
3. Build the project using `swift build`.
4. Run all unit tests with `swift run maczero-tests`.
5. Verify changes with both the graphical application (`swift run MacZeroApp`) and CLI (`swift run maczero list`).

## Guidelines

- **Technical Honesty**: Never fake compatibility or claim a game is fully compatible without empirical testing on Apple Silicon.
- **Security & Integrity**: Do not introduce DRM bypasses or modify macOS system security settings.
- **Clean Architecture**: Keep UI views separated from runtime logic. All process operations belong in `MacZeroCore`.
