;;;; model.lisp -- Drop7 rules, with no Objective-C in them.
;;;;
;;;; A 7×7 board of numbered discs (1–7) and gray discs.  Each turn the
;;;; player drops the next disc into a column; it falls to the lowest empty
;;;; cell.  A numbered disc clears when the contiguous occupied run through
;;;; it, along its row or its column, has length exactly equal to its number.
;;;; Clears happen in waves: gravity between waves can start another.  Gray
;;;; discs count as occupied; an orthogonally adjacent clear hits them --
;;;; solid → cracked, cracked → revealed number.  Every fifth drop the board
;;;; rises and a new gray row appears (+17 000).  An empty board after a move
;;;; scores +70 000.  The game ends when a rise is blocked or no column is
;;;; open.
;;;;
;;;; Everything here is plain Lisp, so a whole game can be played headless
;;;; on the host (see test.lisp).  The view reads the board and plays the
;;;; steps PLAY-COLUMN returns; it decides nothing.

(in-package #:drop7)

;;; ------------------------------------------------------------------
;;; geometry of the scene, in SpriteKit's points (y up)

(defparameter *scene-width* 390d0)
(defparameter *scene-height* 800d0)
(defparameter *board-size* 7)
(defparameter *cell-size* 48d0)
(defparameter *board-bottom* 168d0 "Centre of row 0 (bottom row).")
(defparameter *board-gap* 4d0)
(defparameter *board-left*
  (/ (- *scene-width*
        (+ (* *board-size* *cell-size*) (* (1- *board-size*) *board-gap*)))
     2)
  "Left edge of column 0, so the board sits centred in the scene.")
(defparameter *disc-radius* 21d0)

(defun cell-x (col)
  (+ *board-left* (* col (+ *cell-size* *board-gap*)) (/ *cell-size* 2)))

(defun cell-y (row)
  (+ *board-bottom* (* row (+ *cell-size* *board-gap*))))

(defun column-from-x (x)
  "The column whose centre is nearest X, or nil if off the board."
  (let ((col (round (/ (- x *board-left* (/ *cell-size* 2))
                       (+ *cell-size* *board-gap*)))))
    (when (<= 0 col (1- *board-size*)) col)))

;;; ------------------------------------------------------------------
;;; discs
;;;
;;; A disc is (KIND . VALUE): KIND is :number, :solid or :cracked; VALUE is
;;; 1–7.  VALUE is latent under gray discs and becomes visible on reveal.
;;; NIL is an empty cell.

(defun make-number (n) (cons :number n))
(defun make-solid (n) (cons :solid n))
(defun make-cracked (n) (cons :cracked n))

(defun disc-kind (disc) (car disc))
(defun disc-value (disc) (cdr disc))

(defun number-disc-p (disc) (and disc (eq (disc-kind disc) :number)))
(defun solid-disc-p (disc) (and disc (eq (disc-kind disc) :solid)))
(defun cracked-disc-p (disc) (and disc (eq (disc-kind disc) :cracked)))
(defun gray-disc-p (disc) (or (solid-disc-p disc) (cracked-disc-p disc)))
(defun occupied-p (disc) (not (null disc)))

;;; ------------------------------------------------------------------
;;; colours, matching the classic number palette

(defparameter *number-rgb*
  '((1 0.62 0.32 0.88)                  ; violet
    (2 0.22 0.48 0.92)                  ; blue
    (3 0.18 0.72 0.78)                  ; teal
    (4 0.28 0.72 0.32)                  ; green
    (5 0.95 0.78 0.18)                  ; yellow
    (6 0.96 0.52 0.14)                  ; orange
    (7 0.92 0.26 0.24))                 ; red
  "Each number's fill colour.")

(defparameter *gray-rgb* '(0.55 0.58 0.62))
(defparameter *cracked-rgb* '(0.68 0.70 0.74))

(defun number-rgb (n)
  (rest (assoc n *number-rgb*)))

(defun light-number-p (n)
  (destructuring-bind (r g b) (number-rgb n)
    (> (+ (* 0.3 r) (* 0.59 g) (* 0.11 b)) 0.7)))

;;; ------------------------------------------------------------------
;;; scoring (Hardcore five-move mode, as on drop7.dev)

(defun wave-points (depth)
  "Points for one disc cleared in chain wave DEPTH (1-based)."
  (floor (* 7 (expt (float depth 1d0) 2.5d0))))

(defparameter *rise-bonus* 17000)
(defparameter *board-clear-bonus* 70000)
(defparameter *rise-every* 5 "Drops between rises.")

;;; ------------------------------------------------------------------
;;; RNG: a tiny LCG so a seeded game is reproducible on host and device

(defstruct (rng (:constructor %make-rng (state)))
  state)

(defun make-rng (&optional (seed 1))
  (%make-rng (logand seed #xffffffff)))

(defun rng-next (rng &optional (limit nil))
  "Next 31-bit value, or a value in [0, LIMIT)."
  (let ((n (logand (+ (* (rng-state rng) 1103515245) 12345) #x7fffffff)))
    (setf (rng-state rng) n)
    (if limit (mod n limit) n)))

(defun rng-disc-value (rng)
  (1+ (rng-next rng 7)))

;;; ------------------------------------------------------------------
;;; the game

(defstruct game
  board                                 ; 7×7 array, row 0 = bottom
  next                                  ; the disc waiting to drop (:number . n)
  (rise-clock *rise-every*)             ; drops remaining until the next rise
  (score 0)
  (drops 0)                             ; discs the player has placed
  (state :playing)                      ; :playing or :over
  (over-reason nil)                     ; :blocked-rise or :no-moves
  rng
  (high-score 0))

(defun empty-board ()
  (make-array (list *board-size* *board-size*) :initial-element nil))

(defun board-ref (board col row)
  (aref board row col))

(defun (setf board-ref) (value board col row)
  (setf (aref board row col) value))

(defun copy-board (board)
  (let ((out (empty-board)))
    (dotimes (row *board-size*)
      (dotimes (col *board-size*)
        (setf (board-ref out col row) (board-ref board col row))))
    out))

(defun new-game (&key (seed 1) (high-score 0))
  (let* ((rng (make-rng seed))
         (game (make-game :board (empty-board)
                          :rng rng
                          :high-score high-score
                          :next (make-number (rng-disc-value rng)))))
    game))

(defun column-height (board col)
  "How many occupied cells in COLUMN, from the bottom."
  (loop for row from 0 below *board-size*
        while (occupied-p (board-ref board col row))
        count t))

(defun column-open-p (board col)
  (null (board-ref board col (1- *board-size*))))

(defun legal-columns (game)
  (when (eq (game-state game) :playing)
    (loop for col below *board-size*
          when (column-open-p (game-board game) col)
            collect col)))

(defun board-empty-p (board)
  (dotimes (row *board-size* t)
    (dotimes (col *board-size*)
      (when (occupied-p (board-ref board col row))
        (return-from board-empty-p nil)))))

(defun drop-row (board col)
  "The row a disc lands in if dropped in COLUMN, or nil if the column is full."
  (when (column-open-p board col)
    (column-height board col)))

;;; ------------------------------------------------------------------
;;; runs and matches

(defun row-run (board col row)
  "Length of the contiguous occupied run through (COL, ROW) along its row."
  (let ((left col) (right col))
    (loop while (and (plusp left)
                     (occupied-p (board-ref board (1- left) row)))
          do (decf left))
    (loop while (and (< right (1- *board-size*))
                     (occupied-p (board-ref board (1+ right) row)))
          do (incf right))
    (1+ (- right left))))

(defun column-run (board col row)
  "Length of the contiguous occupied run through (COL, ROW) along its column."
  (let ((bottom row) (top row))
    (loop while (and (plusp bottom)
                     (occupied-p (board-ref board col (1- bottom))))
          do (decf bottom))
    (loop while (and (< top (1- *board-size*))
                     (occupied-p (board-ref board col (1+ top))))
          do (incf top))
    (1+ (- top bottom))))

(defun matching-cells (board)
  "All (col . row) of numbered discs whose row-run or column-run equals their number."
  (let ((out '()))
    (dotimes (row *board-size*)
      (dotimes (col *board-size*)
        (let ((disc (board-ref board col row)))
          (when (and (number-disc-p disc)
                     (let ((n (disc-value disc)))
                       (or (= n (row-run board col row))
                           (= n (column-run board col row)))))
            (push (cons col row) out)))))
    (nreverse out)))

(defun neighbours (col row)
  (loop for (dc . dr) in '((0 . 1) (0 . -1) (1 . 0) (-1 . 0))
        for c = (+ col dc)
        for r = (+ row dr)
        when (and (<= 0 c (1- *board-size*))
                  (<= 0 r (1- *board-size*)))
          collect (cons c r)))

;;; ------------------------------------------------------------------
;;; gravity

(defun apply-gravity (board)
  "Pull every disc straight down.  Returns a list of (col from-row to-row disc)
for discs that moved."
  (let ((falls '()))
    (dotimes (col *board-size*)
      (let ((write 0))
        (dotimes (row *board-size*)
          (let ((disc (board-ref board col row)))
            (when disc
              (setf (board-ref board col row) nil)
              (setf (board-ref board col write) disc)
              (unless (= write row)
                (push (list col row write disc) falls))
              (incf write))))))
    (nreverse falls)))

;;; ------------------------------------------------------------------
;;; one wave of clears

(defun apply-hits (board clears)
  "Hit every gray disc orthogonally adjacent to a clearing cell.  Hits are
counted on the pre-clear board: a solid hit twice in one wave reveals at
once.  Returns a list of (col row new-disc) for cells that changed."
  (let ((hits (make-hash-table :test 'equal)))
    (dolist (pos clears)
      (destructuring-bind (col . row) pos
        (dolist (n (neighbours col row))
          (let ((disc (board-ref board (car n) (cdr n))))
            (when (gray-disc-p disc)
              (incf (gethash n hits 0)))))))
    (let ((changes '()))
      (maphash
       (lambda (pos count)
         (destructuring-bind (col . row) pos
           (let* ((disc (board-ref board col row))
                  (value (disc-value disc))
                  (new (cond ((solid-disc-p disc)
                              (if (>= count 2)
                                  (make-number value)
                                  (make-cracked value)))
                             ((cracked-disc-p disc)
                              (make-number value))
                             (t disc))))
             (unless (eq (disc-kind new) (disc-kind disc))
               (setf (board-ref board col row) new)
               (push (list col row new) changes)))))
       hits)
      (nreverse changes))))

(defun clear-cells (board clears)
  (dolist (pos clears)
    (setf (board-ref board (car pos) (cdr pos)) nil)))

;;; ------------------------------------------------------------------
;;; rise

(defun can-rise-p (board)
  (dotimes (col *board-size* t)
    (when (occupied-p (board-ref board col (1- *board-size*)))
      (return nil))))

(defun rise-board (board rng)
  "Shift every disc up one row and fill row 0 with solid gray discs.
Returns the seven new discs."
  (loop for row from (1- *board-size*) downto 1
        do (dotimes (col *board-size*)
             (setf (board-ref board col row)
                   (board-ref board col (1- row)))))
  (let ((new '()))
    (dotimes (col *board-size*)
      (let ((disc (make-solid (rng-disc-value rng))))
        (setf (board-ref board col 0) disc)
        (push disc new)))
    (nreverse new)))

;;; ------------------------------------------------------------------
;;; resolve cascades

(defun resolve-cascades (game &optional (wave 1))
  "Clear, hit, gravity, repeat.  Returns (steps . next-wave), where STEPS is
a list of animation steps and NEXT-WAVE is the wave depth to continue from
(after a rise, for example)."
  (let ((board (game-board game))
        (steps '())
        (depth wave))
    (loop
      (let ((clears (matching-cells board)))
        (unless clears (return))
        (let* ((n (length clears))
               (points (* n (wave-points depth)))
               (hits (apply-hits board clears)))
          (incf (game-score game) points)
          (clear-cells board clears)
          (push (list :wave
                      :depth depth
                      :clears (mapcar (lambda (p) (list (car p) (cdr p))) clears)
                      :hits hits
                      :points points
                      :score (game-score game))
                steps)
          (let ((falls (apply-gravity board)))
            (when falls
              (push (list :gravity falls) steps)))
          (incf depth))))
    (values (nreverse steps) depth)))

(defun maybe-board-clear (game)
  (when (board-empty-p (game-board game))
    (incf (game-score game) *board-clear-bonus*)
    (list (list :board-clear :points *board-clear-bonus*
                :score (game-score game)))))

(defun deal-next (game)
  (setf (game-next game) (make-number (rng-disc-value (game-rng game))))
  (list (list :deal (game-next game))))

(defun finish-if-stuck (game)
  (cond ((null (legal-columns game))
         (setf (game-state game) :over
               (game-over-reason game) :no-moves)
         (when (> (game-score game) (game-high-score game))
           (setf (game-high-score game) (game-score game)))
         (list (list :game-over :no-moves :score (game-score game))))
        (t '())))

;;; ------------------------------------------------------------------
;;; the public move

(defun play-column (game col)
  "Drop the next disc into COLUMN.  Mutates GAME and returns a list of
animation steps describing what happened.  Returns NIL if the move is
illegal."
  (unless (and (eq (game-state game) :playing)
               (integerp col)
               (<= 0 col (1- *board-size*))
               (column-open-p (game-board game) col))
    (return-from play-column nil))
  (let* ((board (game-board game))
         (disc (game-next game))
         (row (drop-row board col))
         (steps (list (list :drop disc col row))))
    (setf (board-ref board col row) disc
          (game-next game) nil)
    (incf (game-drops game))
    (multiple-value-bind (cascade-steps wave)
        (resolve-cascades game 1)
      (setf steps (append steps cascade-steps))
      (setf steps (append steps (maybe-board-clear game)))
      ;; Tick the rise clock; on zero, rise (or lose).
      (decf (game-rise-clock game))
      (when (zerop (game-rise-clock game))
        (cond ((not (can-rise-p board))
               (setf (game-state game) :over
                     (game-over-reason game) :blocked-rise)
               (when (> (game-score game) (game-high-score game))
                 (setf (game-high-score game) (game-score game)))
               (setf steps (append steps
                                   (list (list :game-over :blocked-rise
                                               :score (game-score game)))))
               (return-from play-column steps))
              (t
               (let ((new-row (rise-board board (game-rng game))))
                 (incf (game-score game) *rise-bonus*)
                 (setf (game-rise-clock game) *rise-every*)
                 (setf steps
                       (append steps
                               (list (list :rise :new-row new-row
                                           :points *rise-bonus*
                                           :score (game-score game)))))
                 ;; Cascades from the new row continue the wave count.
                 (multiple-value-bind (more _)
                     (resolve-cascades game wave)
                   (declare (ignore _))
                   (setf steps (append steps more)))
                 (setf steps (append steps (maybe-board-clear game)))))))
      (when (eq (game-state game) :playing)
        (setf steps (append steps (deal-next game)))
        (setf steps (append steps (finish-if-stuck game))))
      steps)))

;;; ------------------------------------------------------------------
;;; helpers for tests and debugging

(defun board-from-rows (rows)
  "Build a board from ROWS, top row first, each a string of characters:
digits 1–7, #\\X solid gray (value 1), #\\x cracked gray (value 1), #\\. empty.
Use BOARD-SET to put real latent values afterwards when needed."
  (assert (= (length rows) *board-size*))
  (let ((board (empty-board)))
    (loop for row-string in rows
          for screen-row from 0
          for row = (- (1- *board-size*) screen-row)
          do (assert (= (length row-string) *board-size*))
             (loop for char across row-string
                   for col from 0
                   do (setf (board-ref board col row)
                            (case char
                              (#\. nil)
                              (#\X (make-solid 1))
                              (#\x (make-cracked 1))
                              (otherwise
                               (let ((n (digit-char-p char)))
                                 (assert (and n (<= 1 n 7)))
                                 (make-number n)))))))
    board))

(defun board-set (board col row disc)
  (setf (board-ref board col row) disc))

(defun format-board (board &optional (stream t))
  (loop for screen-row from 0 below *board-size*
        for row = (- (1- *board-size*) screen-row)
        do (loop for col below *board-size*
                 for disc = (board-ref board col row)
                 do (format stream "~c"
                            (cond ((null disc) #\.)
                                  ((number-disc-p disc)
                                   (digit-char (disc-value disc)))
                                  ((solid-disc-p disc) #\X)
                                  ((cracked-disc-p disc) #\x)
                                  (t #\?))))
           (terpri stream)))
