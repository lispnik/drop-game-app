;;;; test.lisp -- exercise the rules headless, on the host.
;;;;
;;;;   sbcl --script src/test.lisp      (or ecl --shell src/test.lisp)
;;;;
;;;; The model has no Objective-C in it, so it loads without objc; the
;;;; package's UI nickname wants a UIKIT package to exist, and an empty one
;;;; will do.

(defpackage #:uikit (:use #:cl))
(let ((here (directory-namestring (or *load-truename* *default-pathname-defaults*))))
  (load (merge-pathnames "package.lisp" here))
  (load (merge-pathnames "model.lisp" here)))

(in-package #:drop7)

(defun check (label condition)
  (unless condition
    (error "FAIL: ~a" label))
  (format t "ok  ~a~%" label))

(defun step-kinds (steps)
  (mapcar #'first steps))

;;; Wave points match the published Hardcore table.
(check "wave 1 = 7" (= (wave-points 1) 7))
(check "wave 2 = 39" (= (wave-points 2) 39))
(check "wave 3 = 109" (= (wave-points 3) 109))
(check "wave 4 = 224" (= (wave-points 4) 224))
(check "wave 5 = 391" (= (wave-points 5) 391))

;;; A lone 1 on an empty board clears itself (and earns the board-clear bonus).
(let* ((game (new-game :seed 1))
       (board (game-board game)))
  (setf (game-next game) (make-number 1))
  (let ((steps (play-column game 3)))
    (check "solo 1 clears"
           (and (null (board-ref board 3 0))
                (member :wave (step-kinds steps))
                (member :board-clear (step-kinds steps))
                (= (game-score game) (+ 7 *board-clear-bonus*))))))

;;; A 3 in a run of three clears; neighbours stay.
(let* ((game (new-game :seed 1))
       (board (game-board game)))
  (board-set board 0 0 (make-number 5))
  (board-set board 1 0 (make-number 6))
  (setf (game-next game) (make-number 3))
  (play-column game 2)
  (check "3 clears in a row of three"
         (and (null (board-ref board 2 0))
              (number-disc-p (board-ref board 0 0))
              (number-disc-p (board-ref board 1 0))
              (= (game-score game) 7))))

;;; A 2 in a run of three does not clear.
(let* ((game (new-game :seed 1))
       (board (game-board game)))
  (board-set board 0 0 (make-number 5))
  (board-set board 1 0 (make-number 6))
  (setf (game-next game) (make-number 2))
  (play-column game 2)
  (check "2 stays in a run of three"
         (and (number-disc-p (board-ref board 2 0))
              (= (game-score game) 0))))

;;; Gray discs lengthen runs.
(let* ((game (new-game :seed 1))
       (board (game-board game)))
  (board-set board 0 0 (make-number 5))
  (board-set board 1 0 (make-number 6))
  (board-set board 2 0 (make-solid 4))
  (setf (game-next game) (make-number 3))
  (play-column game 3)
  (check "gray lengthens a run so 3 does not clear"
         (and (number-disc-p (board-ref board 3 0))
              (= (game-score game) 0))))

;;; One adjacent clear cracks a solid gray.
(let* ((game (new-game :seed 1))
       (board (game-board game)))
  (board-set board 1 0 (make-solid 4))
  (setf (game-next game) (make-number 1))
  (play-column game 0)
  (check "one hit cracks solid gray"
         (cracked-disc-p (board-ref board 1 0))))

;;; Two hits in one wave reveal a solid gray.
(let* ((game (new-game :seed 1))
       (board (game-board game)))
  ;; 1 at (0,0) and 1 at (2,0) with solid gray between: both clear by
  ;; column-run of 1, hitting the gray twice.
  (board-set board 1 0 (make-solid 7))
  (board-set board 0 0 (make-number 1))
  (setf (game-next game) (make-number 1))
  (play-column game 2)
  (check "two hits in one wave reveal"
         (number-disc-p (board-ref board 1 0))))

;;; Vertical clear.
(let* ((game (new-game :seed 1))
       (board (game-board game)))
  (board-set board 0 0 (make-number 5))
  (setf (game-next game) (make-number 2))
  (play-column game 0)
  (check "vertical 2 clears"
         (and (null (board-ref board 0 1))
              (number-disc-p (board-ref board 0 0))
              (= (game-score game) 7))))

;;; Chain: clearing reveals a match for wave 2.
(let* ((game (new-game :seed 1))
       (board (game-board game)))
  ;; Bottom: cracked gray hiding a 1.  Drop a 1 beside it; the 1 clears,
  ;; reveals the gray as 1, which then clears in wave 2.
  (board-set board 0 0 (make-cracked 1))
  (setf (game-next game) (make-number 1))
  (let ((steps (play-column game 1)))
    (check "two-wave chain scores 7+39"
           (and (board-empty-p board)
                (= (game-score game) (+ 7 39 *board-clear-bonus*))
                (= (count :wave (step-kinds steps)) 2)
                (member :board-clear (step-kinds steps))))))

;;; Rise every five drops on an empty-enough board.
(let* ((game (new-game :seed 42)))
  (dotimes (i 4)
    (setf (game-next game) (make-number 7)) ; 7 almost never clears alone
    (play-column game (mod i 7)))
  (check "rise clock at 1 after four drops" (= (game-rise-clock game) 1))
  (setf (game-next game) (make-number 7))
  (let ((steps (play-column game 4)))
    (check "fifth drop rises"
           (and (member :rise (step-kinds steps))
                (= (game-rise-clock game) 5)
                (>= (game-score game) *rise-bonus*)
                (every #'solid-disc-p
                       (loop for col below 7
                             collect (board-ref (game-board game) col 0)))))))

;;; Blocked rise ends the game.  Fill a column with 6s so a stack of seven
;;; does not itself clear (column-run 7 ≠ 6).
(let* ((game (new-game :seed 1))
       (board (game-board game)))
  (dotimes (row *board-size*)
    (board-set board 0 row (make-number 6)))
  (setf (game-rise-clock game) 1
        (game-next game) (make-number 7))
  ;; Drop into another column so the move succeeds, then rise fails.
  (let ((steps (play-column game 1)))
    (check "blocked rise is game over"
           (and (eq (game-state game) :over)
                (eq (game-over-reason game) :blocked-rise)
                (member :game-over (step-kinds steps))))))

;;; A seeded game is deterministic.
(let* ((a (new-game :seed 99))
       (b (new-game :seed 99))
       (cols '(0 1 2 3 4 0 1 2 3)))
  (dolist (col cols)
    (when (column-open-p (game-board a) col)
      (play-column a col))
    (when (column-open-p (game-board b) col)
      (play-column b col)))
  (check "same seed, same score"
         (= (game-score a) (game-score b))))

(format t "~&All drop7 tests passed.~%")
