;;;; drop7-clone-app.asd -- a Drop7-style puzzle on a 7×7 board.
;;;;
;;;; The simulator by default; the device too when IOS_SIGNING_IDENTITY says
;;;; how to sign.  DROP7_DISTRIBUTION=1 is an App Store build, for the device
;;;; alone and without get-task-allow -- tools/testflight.sh makes one, and
;;;; DROP7_BUILD is its build number, which every upload must raise.

(defsystem "drop7-clone-app"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "drop7:start"
  :description "A Drop7-style puzzle: drop numbered discs on a 7×7 board so their number matches a row or column run, crack the gray discs, and survive each rising row."
  :version #.(or (uiop:getenv "DROP7_BUILD") "1")
  :bundle-short-version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :pathname "src"
  :components ((:file "package")
               (:file "model")
               (:file "view"))

  :bundle-identifier "com.burnsidemk.drop-game"
  :bundle-name "Drop7"
  :bundle-display-name "Drop Game"   ; the name under the home-screen icon
  :bundle-executable "drop7"
  :bundle-platforms #.(cond ((uiop:getenv "DROP7_DISTRIBUTION") '(:device))
                            ((uiop:getenv "IOS_SIGNING_IDENTITY") '(:simulator :device))
                            (t '(:simulator)))
  :get-task-allow #.(not (uiop:getenv "DROP7_DISTRIBUTION"))
  ;; iPhone only: an iPad app must allow every orientation for multitasking,
  ;; and the board is laid out for portrait.  An iPad runs it as an iPhone app.
  :bundle-device-family (:iphone)
  :bundle-orientations (:portrait)
  :bundle-status-bar-hidden t
  ;; UIStatusBarHidden is honoured only when the view controller is not the
  ;; one deciding, and the root controller here is the shim's, not ours.
  :bundle-info-plist (("UIViewControllerBasedStatusBarAppearance" . :false)
                      ;; Export compliance, answered: the game encrypts nothing.
                      ("ITSAppUsesNonExemptEncryption" . :false)
                      ;; A puzzle game, and iOS's Game Mode on while it plays.
                      ("LSApplicationCategoryType" . "public.app-category.puzzle-games")
                      ("GCSupportsGameMode" . :true))
  ;; 1024x1024 with no alpha; tools/make-icon.py draws it.
  :bundle-icon "res/Drop7.xcassets"
  ;; tools/make-sounds.py synthesises these.  In the bundle's root, where
  ;; SpriteKit's playSoundFileNamed: looks.
  :bundle-resources ("res/sounds/tap.wav" "res/sounds/plop.wav"
                     "res/sounds/won.wav" "res/sounds/lost.wav"
                     ;; tools/make-buttons.py draws these.
                     "res/buttons/button-settings.png"
                     "res/buttons/button-restart.png")
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "SpriteKit" "AVFoundation")

  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))
