## Build Instructions
- Build and run after changes with: `xcodebuild -project kindling.xcodeproj -scheme kindling -destination 'platform=macOS' build`.
- Always escalate permissions when running `xcodebuild` (requires access to Xcode caches/DerivedData).
- Run `make run` after every change.
- When working on code that interacts with the LazyLibrarian API, test with `./llapi` (example: `./llapi cmd=getAllBooks`).
- Commit early and often.
- Do not ask before committing; use good judgment on commit messages.
