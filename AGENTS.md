# Repository Guidelines

## Project Structure & Module Organization

This is an iOS Drop7-style game written in Common Lisp. `src/model.lisp` contains the platform-independent rules and scoring; `src/view.lisp` implements the SpriteKit scene and interaction; `src/package.lisp` defines the package; and `src/test.lisp` contains headless rule checks. Assets live under `res/` (sounds, button images, and the app icon). Asset-generation scripts and the TestFlight workflow are in `tools/`. The ASDF system is `drop7-clone-app.asd`; dependencies are recorded in `ocicl.csv`.

## Build, Test, and Development Commands

- `sbcl --script src/test.lisp` runs the headless model checks on the host.
- `(asdf:make "drop7-clone-app")` builds the simulator app after the ASDF iOS toolchain and dependencies are installed.
- `(asdf-ios-app:run-in-simulator "drop7-clone-app")` launches the simulator build.
- `ocicl install` installs the locked dependencies from this project directory.
- `tools/testflight.sh --validate` builds and validates an App Store package without uploading it. Signing credentials are required; see the script header and README.

For simulator development, `DROP7_AUTOPLAY=1` enables autoplay, `DROP7_SEED=n` fixes the random seed, and `DROP7_SETTINGS=1` opens settings at launch.

## Coding Style & Naming Conventions

Use idiomatic Common Lisp: lowercase, hyphen-separated function and variable names (`play-column`, `game-score`), and descriptive package-qualified APIs. Keep model rules free of Objective-C dependencies; put SpriteKit and UIKit interaction in `view.lisp`. Follow the existing four-space indentation and document non-obvious rule behavior near its implementation. Python tools use descriptive lowercase filenames. No formatter or linter is configured.

## Testing Guidelines

Add model behavior checks to `src/test.lisp`, using clear labels with the existing `check` helper. Cover scoring, cascades, gray-disc hits, rises, and game-over conditions when changing related rules. Run `sbcl --script src/test.lisp`; simulator-only UI changes should also be inspected in the simulator. No coverage threshold is configured.

## Commit & Pull Request Guidelines

The repository currently has only its initial commit, so no commit-message convention is established. Use a short imperative summary, such as `Fix rise timing after cascades`. Pull requests should describe the behavior change, list relevant validation commands and results, and include simulator screenshots for visible UI changes. Note any signing or dependency setup needed to reproduce a build.

## Configuration & Assets

Keep personal signing values in untracked `local.env`; do not commit credentials or provisioning profiles. Regenerate artwork or sounds with the corresponding script in `tools/`, and review the generated files under `res/` before committing them.
