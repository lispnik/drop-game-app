;;;; view.lisp -- the game drawn by SpriteKit.
;;;;
;;;; The scene is a Lisp subclass of SKScene.  A tap chooses a column; the
;;;; model resolves the move into a list of steps, and the view plays them
;;;; with SKActions -- drops, clears, hits, gravity, rises -- locking input
;;;; until the sequence finishes.  Progress lives in NSUserDefaults.

(in-package #:drop7)

(defvar *view* nil "The SKView.")
(defvar *scene* nil "The scene, a DROP-SCENE.")
(defvar *world* nil "The node holding the board and chrome.")
(defvar *game* nil)
(defvar *disc-nodes* nil "7×7 array of SKNodes, mirroring the board.")
(defvar *next-node* nil "The preview disc above the board.")
(defvar *score-label* nil)
(defvar *best-label* nil)
(defvar *rise-pips* nil "Nodes for the five rise-clock pips.")
(defvar *overlay* nil)
(defvar *settings* nil)
(defvar *busy* nil "True while a move's animations are playing.")
(defvar *last-time* nil)
(defvar *fitted* nil)
(defvar *failed* nil)

(defparameter *settings-x* 36d0)
(defparameter *restart-x* 354d0)
(defparameter *chrome-y* 760d0)

;;; ------------------------------------------------------------------
;;; progress, kept in NSUserDefaults across launches

(defun defaults ()
  (objc:invoke "NSUserDefaults" "standardUserDefaults"))

(defun saved (key)
  (objc:invoke (defaults) "integerForKey:" key))

(defun save (key value)
  (objc:invoke (defaults) "setInteger:forKey:" value key))

(defun saved-high-score ()
  (saved "high score"))

(defun record-high-score (score)
  (when (> score (saved-high-score))
    (save "high score" score)))

;;; ------------------------------------------------------------------
;;; nodes

(defun point (x y)
  (vector (float x 1d0) (float y 1d0)))

(defun rgb (r g b &optional (a 1))
  (ui:color r g b a))

(defun add (parent child)
  (objc:invoke parent "addChild:" child)
  child)

(defun at (node x y)
  (objc:invoke node "setPosition:" (point x y))
  node)

(defun z (node z)
  (objc:invoke node "setZPosition:" (float z 1d0))
  node)

(defun rect-sprite (colour width height)
  (objc:invoke "SKSpriteNode" "spriteNodeWithColor:size:" colour (point width height)))

(defun rounded (width height radius fill &optional stroke (line-width 2))
  (let ((node (objc:invoke "SKShapeNode" "shapeNodeWithRect:cornerRadius:"
                           (vector (- (/ width 2d0)) (- (/ height 2d0))
                                   (float width 1d0) (float height 1d0))
                           (float radius 1d0))))
    (objc:invoke node "setFillColor:" fill)
    (objc:invoke node "setStrokeColor:" (or stroke (rgb 0 0 0 0)))
    (objc:invoke node "setLineWidth:" (float line-width 1d0))
    node))

(defun ellipse (width height fill &optional stroke (line-width 2))
  (let ((node (objc:invoke "SKShapeNode" "shapeNodeWithEllipseOfSize:" (point width height))))
    (objc:invoke node "setFillColor:" fill)
    (objc:invoke node "setStrokeColor:" (or stroke (rgb 0 0 0 0)))
    (objc:invoke node "setLineWidth:" (float line-width 1d0))
    node))

(defun button-sprite (name)
  (let ((node (objc:invoke "SKSpriteNode" "spriteNodeWithImageNamed:"
                           (format nil "button-~a.png" name))))
    (objc:invoke node "setSize:" (point 50 50))
    node))

(defun text (string size colour &key (font "AvenirNext-Bold"))
  (let ((node (objc:invoke "SKLabelNode" "labelNodeWithFontNamed:" font)))
    (objc:invoke node "setText:" string)
    (objc:invoke node "setFontSize:" (float size 1d0))
    (objc:invoke node "setFontColor:" colour)
    (objc:invoke node "setVerticalAlignmentMode:" 1) ; centre
    node))

(defun action (name &rest arguments)
  (apply #'objc:invoke "SKAction" name arguments))

(defun run (node &rest actions)
  (objc:invoke node "runAction:"
               (if (rest actions)
                   (action "sequence:" (coerce actions 'vector))
                   (first actions))))

(defun move-to (x y &optional (seconds 0.18d0))
  (action "moveTo:duration:" (point x y) (float seconds 1d0)))

(defun scale-to (scale &optional (seconds 0.15d0))
  (action "scaleTo:duration:" (float scale 1d0) (float seconds 1d0)))

(defun vanish (node &optional (seconds 0.16d0))
  (run node (scale-to 0 seconds) (action "removeFromParent")))

(defun shake (node)
  (run node
       (action "moveByX:y:duration:" 6d0 0d0 0.04d0)
       (action "moveByX:y:duration:" -12d0 0d0 0.08d0)
       (action "moveByX:y:duration:" 6d0 0d0 0.04d0)))

;;; ------------------------------------------------------------------
;;; haptics and sound

(defvar *impacts* (make-hash-table))
(defvar *notifier* nil)
(defvar *sounds* (make-hash-table :test 'equal))

(defun vibration-p ()
  (zerop (saved "no vibration")))

(defun haptic (&optional (style 0) intensity)
  (when (vibration-p)
    (let ((generator (or (gethash style *impacts*)
                         (setf (gethash style *impacts*)
                               (ui:keep (objc:invoke (objc:invoke "UIImpactFeedbackGenerator" "alloc")
                                                     "initWithStyle:" style))))))
      (if intensity
          (objc:invoke generator "impactOccurredWithIntensity:" (float intensity 1d0))
          (objc:invoke generator "impactOccurred")))))

(defun notify (kind)
  (when (vibration-p)
    (objc:invoke (or *notifier*
                     (setf *notifier* (ui:keep (objc:invoke (objc:invoke "UINotificationFeedbackGenerator" "alloc")
                                                            "init"))))
                 "notificationOccurred:" (ecase kind (:success 0) (:error 2)))))

(defun sound (name)
  (when (zerop (saved "no sound"))
    (let ((play (or (gethash name *sounds*)
                    (setf (gethash name *sounds*)
                          (ui:keep (action "playSoundFileNamed:waitForCompletion:"
                                           (format nil "~a.wav" name) nil))))))
      (objc:invoke *scene* "runAction:" play))))

;;; ------------------------------------------------------------------
;;; disc sprites

(defun disc-fill (disc)
  (cond ((number-disc-p disc)
         (apply #'rgb (number-rgb (disc-value disc))))
        ((solid-disc-p disc)
         (apply #'rgb *gray-rgb*))
        ((cracked-disc-p disc)
         (apply #'rgb *cracked-rgb*))
        (t (rgb 1 1 1))))

(defun disc-stroke (disc)
  (cond ((number-disc-p disc)
         (destructuring-bind (r g b) (number-rgb (disc-value disc))
           (rgb (* r 0.55) (* g 0.55) (* b 0.55))))
        (t (rgb 0.35 0.38 0.42))))

(defun text-colour-for (disc)
  (if (and (number-disc-p disc) (light-number-p (disc-value disc)))
      (rgb 0.15 0.12 0.12)
      (rgb 1 1 1)))

(defun make-disc-node (disc)
  "A round disc with its number, or a blank / cracked face for gray."
  (let* ((d (* 2 *disc-radius*))
         (node (ellipse d d (disc-fill disc) (disc-stroke disc) 2.5d0)))
    (cond ((number-disc-p disc)
           (add node (text (princ-to-string (disc-value disc)) 22 (text-colour-for disc))))
          ((solid-disc-p disc)
           ;; A darker inner circle, so solid gray reads as sealed.
           (add node (ellipse (* d 0.42) (* d 0.42) (rgb 0.40 0.43 0.47))))
          ((cracked-disc-p disc)
           ;; A crack: a thin dark slash across the face.
           (let ((crack (rect-sprite (rgb 0.25 0.27 0.30) (* d 0.7) 2.5d0)))
             (objc:invoke crack "setZRotation:" 0.55d0)
             (add node crack))))
    node))

(defun set-disc-node (col row node)
  (setf (aref *disc-nodes* row col) node))

(defun disc-node (col row)
  (aref *disc-nodes* row col))

;;; ------------------------------------------------------------------
;;; chrome

(defun format-score (n)
  (format nil "~:d" n))

(defun update-score ()
  (objc:invoke *score-label* "setText:" (format-score (game-score *game*)))
  (objc:invoke *best-label* "setText:"
               (format nil "best ~a" (format-score (max (game-high-score *game*)
                                                        (saved-high-score))))))

(defun update-rise-pips ()
  "Light as many pips as drops remain until the next rise."
  (let ((left (game-rise-clock *game*)))
    (loop for pip across *rise-pips*
          for i from 1
          do (objc:invoke pip "setFillColor:"
                          (if (<= i left)
                              (rgb 0.95 0.78 0.25)
                              (rgb 1 1 1 0.15))))))

(defun show-overlay (title subtitle colour)
  (let ((panel (z (at (rounded 300 150 18 (rgb 0.08 0.08 0.10 0.92) colour 3)
                      (/ *scene-width* 2) 460)
                  100)))
    (add panel (at (text title 32 colour) 0 28))
    (add panel (at (text subtitle 15 (rgb 1 1 1 0.85) :font "AvenirNext-DemiBold") 0 -18))
    (add panel (at (text (format nil "Score  ~a" (format-score (game-score *game*)))
                         18 (rgb 1 1 1) :font "AvenirNext-DemiBold")
                   0 -52))
    (objc:invoke panel "setScale:" 0.6d0)
    (add *world* panel)
    (run panel (scale-to 1 0.2d0))
    (setf *overlay* panel)))

;;; ------------------------------------------------------------------
;;; building a round

(defun clear-disc-nodes ()
  (when *disc-nodes*
    (dotimes (row *board-size*)
      (dotimes (col *board-size*)
        (let ((node (disc-node col row)))
          (when node
            (objc:invoke node "removeFromParent")
            (set-disc-node col row nil))))))
  (setf *disc-nodes* (make-array (list *board-size* *board-size*) :initial-element nil)))

(defun place-disc (disc col row &key (animate nil))
  (let ((node (make-disc-node disc)))
    (set-disc-node col row node)
    (if animate
        (progn
          (at node (cell-x col) (+ (cell-y (1- *board-size*)) *cell-size* 40))
          (objc:invoke node "setScale:" 0.6d0)
          (add *world* (z node 10))
          (run node
               (action "group:"
                       (vector (move-to (cell-x col) (cell-y row) 0.22d0)
                               (scale-to 1 0.22d0)))))
        (add *world* (z (at node (cell-x col) (cell-y row)) 10)))
    node))

(defun sync-next-preview ()
  (when *next-node*
    (objc:invoke *next-node* "removeFromParent")
    (setf *next-node* nil))
  (when (game-next *game*)
    (let ((node (make-disc-node (game-next *game*))))
      (setf *next-node* (add *world* (z (at node (/ *scene-width* 2) 690) 20))))))

(defun build-board-frame ()
  "The plate behind the 7×7 cells."
  (let* ((span (+ (* *board-size* *cell-size*)
                  (* (1- *board-size*) *board-gap*)))
         (pad 14d0)
         (plate (rounded (+ span pad) (+ span pad) 16
                         (rgb 0.10 0.12 0.16 0.95)
                         (rgb 1 1 1 0.18) 2)))
    (add *world* (z (at plate
                        (/ (+ (cell-x 0) (cell-x (1- *board-size*))) 2)
                        (/ (+ (cell-y 0) (cell-y (1- *board-size*))) 2))
                    0))
    ;; Soft cell wells.
    (dotimes (row *board-size*)
      (dotimes (col *board-size*)
        (add *world* (z (at (ellipse (- *cell-size* 6) (- *cell-size* 6)
                                     (rgb 1 1 1 0.04))
                            (cell-x col) (cell-y row))
                        1))))))

(defun build-round (game)
  ;; Disc nodes are kept alive only by *world*, so drop them while it still
  ;; holds them: messaging them after *world* goes would touch freed objects.
  (clear-disc-nodes)
  (when *world* (objc:invoke *world* "removeFromParent"))
  (setf *world* (add *scene* (objc:invoke "SKNode" "node"))
        *overlay* nil
        *settings* nil
        *busy* nil
        *next-node* nil
        *last-time* nil)
  (fit-world t)
  ;; Background wash inside the world, so the safe-area letterbox stays the
  ;; scene colour while chrome scales with the board.
  (add *world* (z (at (rect-sprite (rgb 0.12 0.14 0.20)
                                   (* 3 *scene-width*) (* 3 *scene-height*))
                      (/ *scene-width* 2) (/ *scene-height* 2))
                  -10))
  (build-board-frame)
  ;; Score and best.
  (setf *score-label* (add *world* (at (text "0" 28 (rgb 1 1 1)) (/ *scene-width* 2) *chrome-y*)))
  (setf *best-label* (add *world* (at (text "" 13 (rgb 1 1 1 0.55) :font "AvenirNext-Medium")
                                      (/ *scene-width* 2) (- *chrome-y* 28))))
  ;; Rise clock: five pips under the preview.
  (setf *rise-pips* (make-array *rise-every*))
  (let ((pip-y 640d0)
        (total-w 120d0))
    (add *world* (at (text "rise" 11 (rgb 1 1 1 0.45) :font "AvenirNext-Medium")
                     (/ *scene-width* 2) (+ pip-y 18)))
    (dotimes (i *rise-every*)
      (let* ((x (+ (/ *scene-width* 2)
                   (- (/ total-w 2))
                   (* i (/ total-w (1- *rise-every*)))))
             (pip (ellipse 14 14 (rgb 1 1 1 0.15))))
        (setf (aref *rise-pips* i) (add *world* (at pip x pip-y))))))
  ;; Settings / restart.
  (add *world* (z (at (button-sprite "settings") *settings-x* *chrome-y*) 30))
  (add *world* (z (at (button-sprite "restart") *restart-x* *chrome-y*) 30))
  ;; Existing discs (usually none on a fresh game).
  (dotimes (row *board-size*)
    (dotimes (col *board-size*)
      (let ((disc (board-ref (game-board game) col row)))
        (when disc (place-disc disc col row)))))
  (sync-next-preview)
  (update-score)
  (update-rise-pips))

;;; ------------------------------------------------------------------
;;; playing animation steps

(defun after (seconds thunk)
  (ui:after-every seconds
                  (lambda (timer)
                    (declare (ignore timer))
                    (funcall thunk))
                  :repeats nil))

(defun replace-disc-node (col row new-disc)
  (let ((old (disc-node col row)))
    (when old
      (objc:invoke old "removeFromParent")
      (set-disc-node col row nil))
    (when new-disc
      (place-disc new-disc col row))))

(defun play-steps (steps &optional (index 0))
  "Play STEPS from INDEX; unlock input when done."
  (if (>= index (length steps))
      (progn
        (setf *busy* nil)
        (update-score)
        (update-rise-pips)
        (sync-next-preview)
        (when (eq (game-state *game*) :over)
          (record-high-score (game-score *game*))
          (setf (game-high-score *game*) (max (game-high-score *game*) (saved-high-score)))
          (update-score)
          (notify :error)
          (sound "lost")
          (show-overlay "Game over"
                        (ecase (game-over-reason *game*)
                          (:blocked-rise "The board could not rise. Tap to retry.")
                          (:no-moves "No open column. Tap to retry."))
                        (rgb 1.0 0.55 0.45))))
      (let ((step (nth index steps)))
        (ecase (first step)
          (:drop
           (destructuring-bind (disc col row) (rest step)
             (sound "tap")
             (haptic 0)
             (place-disc disc col row :animate t)
             (after 0.24d0 (lambda () (play-steps steps (1+ index))))))
          (:wave
           (let ((clears (getf (rest step) :clears))
                 (hits (getf (rest step) :hits))
                 (points (getf (rest step) :points)))
             (declare (ignore points))
             (dolist (pos clears)
               (destructuring-bind (col row) pos
                 (let ((node (disc-node col row)))
                   (when node
                     (vanish node 0.14d0)
                     (set-disc-node col row nil)))))
             (when clears
               (sound "plop")
               (haptic 0 0.55))
             (dolist (hit hits)
               (destructuring-bind (col row new) hit
                 (replace-disc-node col row new)))
             (update-score)
             (after (if clears 0.22d0 0.05d0)
                    (lambda () (play-steps steps (1+ index))))))
          (:gravity
           (let ((falls (second step)))
             (dolist (fall falls)
               (destructuring-bind (col from to disc) fall
                 (declare (ignore disc))
                 (let ((node (disc-node col from)))
                   (when node
                     (set-disc-node col from nil)
                     (set-disc-node col to node)
                     (run node (move-to (cell-x col) (cell-y to) 0.16d0))))))
             (after (if falls 0.18d0 0.02d0)
                    (lambda () (play-steps steps (1+ index))))))
          (:rise
           ;; Disc nodes still mirror the pre-rise board; shift them up, then
           ;; spawn the new gray row the model already wrote into row 0.
           (let ((shifted (make-array (list *board-size* *board-size*)
                                      :initial-element nil)))
             (dotimes (row (1- *board-size*))
               (dotimes (col *board-size*)
                 (let ((node (disc-node col row)))
                   (when node
                     (setf (aref shifted (1+ row) col) node)
                     (run node (move-to (cell-x col) (cell-y (1+ row)) 0.22d0))))))
             (setf *disc-nodes* shifted)
             (haptic 1)
             (sound "won")
             (after 0.12d0
                    (lambda ()
                      (dotimes (col *board-size*)
                        (let ((disc (board-ref (game-board *game*) col 0)))
                          (when disc (place-disc disc col 0 :animate t))))
                      (update-score)
                      (update-rise-pips)
                      (after 0.26d0
                             (lambda () (play-steps steps (1+ index))))))))
          (:board-clear
           (notify :success)
           (sound "won")
           (update-score)
           (let ((flash (add *world* (z (at (text "CLEAR!" 36 (rgb 0.55 0.95 0.55))
                                            (/ *scene-width* 2) 460)
                                        80))))
             (objc:invoke flash "setScale:" 0.5d0)
             (run flash (scale-to 1.1d0 0.2d0) (action "waitForDuration:" 0.5d0)
                  (action "fadeOutWithDuration:" 0.25d0) (action "removeFromParent")))
           (after 0.9d0 (lambda () (play-steps steps (1+ index)))))
          (:deal
           (sync-next-preview)
           (update-rise-pips)
           (play-steps steps (1+ index)))
          (:game-over
           (play-steps steps (1+ index)))))))

;;; ------------------------------------------------------------------
;;; settings

(defparameter *settings-y* 430d0)
(defparameter *settings-rows*
  '(("Sound" "Taps, pops and chimes" "no sound")
    ("Vibration" "Soft ticks on clears" "no vibration")))

(defun settings-row-y (index) (- (+ *settings-y* 55) (* index 70)))
(defun settings-done-y () (- *settings-y* 115))

(defun show-settings ()
  (close-settings)
  (let ((panel (z (objc:invoke "SKNode" "node") 200)))
    (add panel (at (rect-sprite (rgb 0 0 0 0.45) (* 3 *scene-width*) (* 3 *scene-height*))
                   (/ *scene-width* 2) (/ *scene-height* 2)))
    (add panel (at (rounded 320 280 18 (rgb 0.08 0.08 0.10 0.95) (rgb 1 1 1 0.45) 2)
                   (/ *scene-width* 2) *settings-y*))
    (add panel (at (text "Settings" 22 (rgb 1 1 1)) (/ *scene-width* 2) (+ *settings-y* 100)))
    (loop for (title subtitle key) in *settings-rows*
          for index from 0
          for y = (settings-row-y index)
          for on = (zerop (saved key))
          do (loop for (string size alpha font dy) in `((,title 17 1 "AvenirNext-DemiBold" 9)
                                                        (,subtitle 12 0.6 "AvenirNext-Medium" -12))
                   do (let ((label (text string size (rgb 1 1 1 alpha) :font font)))
                        (objc:invoke label "setHorizontalAlignmentMode:" 1)
                        (add panel (at label 52 (+ y dy)))))
             (let ((switch (add panel (at (rounded 54 32 16
                                                   (if on (rgb 0.30 0.78 0.40) (rgb 1 1 1 0.2))
                                                   (rgb 1 1 1 0.35) 1.5d0)
                                          300 y))))
               (add switch (at (ellipse 26 26 (rgb 1 1 1) (rgb 0 0 0 0.15))
                               (if on 11 -11) 0))))
    (let ((done (add panel (at (rounded 120 40 12 (rgb 1 1 1 0.14) (rgb 1 1 1 0.3) 1.5d0)
                               (/ *scene-width* 2) (settings-done-y)))))
      (add done (text "Done" 17 (rgb 1 1 1) :font "AvenirNext-DemiBold")))
    (setf *settings* (add *world* panel))))

(defun close-settings ()
  (when *settings*
    (objc:invoke *settings* "removeFromParent")
    (setf *settings* nil)))

(defun toggle-setting (key)
  (save key (if (zerop (saved key)) 1 0))
  (show-settings))

(defun within (x y cx cy half-width half-height)
  (and (<= (abs (- x cx)) half-width) (<= (abs (- y cy)) half-height)))

(defun settings-tap (x y)
  (let ((row (position-if (lambda (index)
                            (within x y (/ *scene-width* 2) (settings-row-y index) 150 28))
                          (loop for index below (length *settings-rows*) collect index))))
    (cond (row
           (toggle-setting (third (nth row *settings-rows*)))
           (haptic 0))
          ((or (within x y (/ *scene-width* 2) (settings-done-y) 60 20)
               (not (within x y (/ *scene-width* 2) *settings-y* 160 140)))
           (close-settings)))))

;;; ------------------------------------------------------------------
;;; taps

(defun start-game (&optional seed)
  (setf *game* (new-game :seed (or seed (get-universal-time))
                         :high-score (saved-high-score))
        *failed* nil)
  (build-round *game*)
  (format t "DROP7: new game, next ~a~%" (disc-value (game-next *game*)))
  (finish-output))

(defun tap-column (col)
  (when (and *game* (not *busy*) (eq (game-state *game*) :playing) (null *settings*) (null *overlay*))
    (let ((steps (play-column *game* col)))
      (cond (steps
             (setf *busy* t)
             ;; The next preview is consumed; hide it for the drop.
             (when *next-node*
               (objc:invoke *next-node* "removeFromParent")
               (setf *next-node* nil))
             (play-steps steps))
            (t
             ;; Column full or otherwise illegal: nudge the preview.
             (when *next-node* (shake *next-node*)))))))

(defun tap-at (x y)
  (cond ((null *game*))
        (*settings* (settings-tap x y))
        ((within x y *settings-x* *chrome-y* 28 28)
         (show-settings))
        ((within x y *restart-x* *chrome-y* 28 28)
         (haptic 0)
         (sound "tap")
         (start-game))
        (*overlay*
         (start-game))
        (*busy*)
        (t
         (let ((col (column-from-x x)))
           (when (and col
                      (<= (- *board-bottom* (/ *cell-size* 2) 20) y
                          (+ (cell-y (1- *board-size*)) (/ *cell-size* 2) 80)))
             (tap-column col))))))

(defun tap-view-point (in-view)
  (let ((in-scene (objc:invoke *world* "convertPoint:fromNode:"
                               (objc:invoke *scene* "convertPointFromView:" in-view) *scene*)))
    (tap-at (aref in-scene 0) (aref in-scene 1))))

(defun tapped (recognizer)
  (tap-view-point (objc:invoke recognizer "locationInView:" *view*)))

;;; ------------------------------------------------------------------
;;; the scene

(objc:define-objc-class drop-scene () ()
  (:objc-class-name "LispDropScene")
  (:objc-superclass-name "SKScene"))

(defun fit-world (&optional force)
  (when (and *scene* *world*)
    (let* ((size (objc:invoke *scene* "size"))
           (insets (objc:invoke *view* "safeAreaInsets"))
           (left (aref insets 1))
           (bottom (aref insets 2))
           (w (- (aref size 0) left (aref insets 3)))
           (h (- (aref size 1) (aref insets 0) bottom)))
      (when (and (plusp w) (plusp h)
                 (or force (not (equalp (list size insets) *fitted*))))
        (setf *fitted* (list size insets))
        (let ((scale (min (/ w *scene-width*) (/ h *scene-height*))))
          (objc:invoke *world* "setScale:" scale)
          (objc:invoke *world* "setPosition:"
                       (point (+ left (/ (- w (* scale *scene-width*)) 2))
                              (+ bottom (/ (- h (* scale *scene-height*)) 2)))))))))

(objc:define-objc-method ("update:" :void)
    ((self drop-scene) (time :double))
  (declare (ignore self))
  (setf *last-time* time)
  (fit-world)
  (unless *failed*
    (handler-case nil
      (error (condition)
        (setf *failed* t)
        (format *error-output* "~&drop7: frame failed: ~a~%" condition)
        (finish-output *error-output*)))))

;;; ------------------------------------------------------------------
;;; autoplay, for watching without touching the screen
;;;
;;;   SIMCTL_CHILD_DROP7_AUTOPLAY=1 xcrun simctl launch booted com.burnsidemk.drop-game

(defun autotap (x y)
  (tap-view-point (objc:invoke *scene* "convertPointToView:"
                               (objc:invoke *world* "convertPoint:toNode:" (point x y) *scene*))))

(defvar *overlay-ticks* 0)

(defun autoplay-tick ()
  (cond ((or (null *game*) *settings* *busy*))
        (*overlay*
         (when (>= (incf *overlay-ticks*) 6)
           (setf *overlay-ticks* 0)
           (autotap (/ *scene-width* 2) 460)))
        (t
         (let ((open (legal-columns *game*)))
           (when open
             (let ((col (nth (random (length open)) open)))
               (autotap (cell-x col) (cell-y 3))))))))

(defun start ()
  (objc:ensure-objc-initialized)
  (let* ((root (ui:root-view))
         (view (ui:new "SKView"))
         (background (rgb 0.12 0.14 0.20)))
    (objc:invoke root "setBackgroundColor:" background)
    (objc:invoke root "addSubview:" view)
    (ui:pin view "topAnchor" root "topAnchor")
    (ui:pin view "bottomAnchor" root "bottomAnchor")
    (ui:pin view "leadingAnchor" root "leadingAnchor")
    (ui:pin view "trailingAnchor" root "trailingAnchor")
    (let ((scene (objc:invoke (make-instance 'drop-scene) "initWithSize:"
                              (point *scene-width* *scene-height*))))
      (objc:invoke scene "setBackgroundColor:" background)
      (objc:invoke scene "setScaleMode:" 3) ; resize fill: see FIT-WORLD
      (setf *view* (ui:keep view)
            *scene* (ui:keep scene))
      (objc:invoke (objc:invoke "AVAudioSession" "sharedInstance") "setCategory:error:"
                   "AVAudioSessionCategoryAmbient" nil)
      (start-game (let ((n (ext:getenv "DROP7_SEED")))
                    (and n (parse-integer n :junk-allowed t))))
      (when (ext:getenv "DROP7_SETTINGS")
        (show-settings))
      (objc:invoke view "presentScene:" scene))
    (objc:invoke view "addGestureRecognizer:"
                 (ui:keep (objc:invoke (objc:invoke "UITapGestureRecognizer" "alloc")
                                       "initWithTarget:action:"
                                       (ui:action-target #'tapped) "fire:")))
    (when (ext:getenv "DROP7_AUTOPLAY")
      (ui:after-every 0.7 (lambda (timer) (declare (ignore timer)) (autoplay-tick))))
    (values)))
