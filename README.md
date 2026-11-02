# drop7-clone-app

A Drop7-style puzzle for iOS, written in Common Lisp and built with
[asdf-ios-app](https://github.com/lispnik/asdf-ios-app) and
[objc](https://github.com/lispnik/objc) (pulled in with
[ocicl](https://github.com/ocicl/ocicl)). There is no Xcode project: ECL
cross-compiles the Lisp, and SpriteKit draws.

Drop numbered discs (1–7) onto a 7×7 board. A disc clears when the contiguous
run of occupied cells through it — along its row or its column — has length
exactly equal to its number. Gray discs count as occupied and hide a number;
an adjacent clear cracks them, and a second hit reveals the number. Clears
chain through gravity, and later waves score more
(`floor(7 × depth^2.5)` points per disc). Every fifth drop the board rises
and a new gray row appears (+17 000). Clear the whole board for +70 000. The
game ends when a rise is blocked or no column can take a disc.

The board is laid out at 390×800 points and scaled to fit the screen's safe
area. High score, sound and vibration preferences persist across launches.

## Building

With `asdf-ios-app`'s toolchain bootstrapped, this directory on your ASDF
source registry, and dependencies installed (`ocicl install` from here, which
vendors `objc`):

```lisp
(asdf:make "drop7-clone-app")                          ; => build/iphonesimulator/Drop7.app
(asdf-ios-app:run-in-simulator "drop7-clone-app")
```

A device build too, when the environment says how to sign it:

```sh
export IOS_SIGNING_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)"
export IOS_DEVELOPMENT_TEAM=TEAMID1234
export IOS_PROVISIONING_PROFILE=/path/to/a/development.mobileprovision
ecl --eval '(asdf:make "drop7-clone-app")' --eval '(quit)'   # => build/iphoneos/Drop7.app too
```

## TestFlight

`tools/testflight.sh` makes a clean App Store build, checks its signature,
validates it and uploads it. Its signing settings come from `local.env`, which
is not committed; the script's header lists what goes in it.

```sh
tools/testflight.sh              # build number from the clock
tools/testflight.sh --validate   # build and validate, upload nothing
```

## Files

| | |
|---|---|
| `src/package.lisp` | the package |
| `src/model.lisp` | the rules, in plain Lisp: board, drops, waves, rise, scoring |
| `src/view.lisp` | the SpriteKit scene, taps, and an autoplay mode for development |
| `src/test.lisp` | headless rule checks: `sbcl --script src/test.lisp` |
| `tools/make-icon.py` | draws `res/Drop7.xcassets` |
| `tools/make-buttons.py` | draws `res/buttons/*.png` |
| `tools/make-sounds.py` | synthesises `res/sounds/*.wav` |
| `tools/testflight.sh` | App Store build, check, validate, upload |
| `ocicl.csv` | locked dependency digests (`ocicl install`) |

## Development switches

Set in the simulator's environment at launch:

```sh
SIMCTL_CHILD_DROP7_AUTOPLAY=1 xcrun simctl launch booted com.burnsidemk.drop-game
```

`DROP7_AUTOPLAY=1` plays by itself, `DROP7_SEED=n` starts with a fixed RNG
seed, and `DROP7_SETTINGS=1` opens the settings panel.
