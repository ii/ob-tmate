;;; ob-tmate.el --- Babel Support for Interactive Terminal -*- lexical-binding: t; -*-

;; Copyright (C) 2009-2017 Free Software Foundation, Inc.
;; Copyright (C) 2017 Allard Hendriksen

;; Author: Allard Hendriksen
;; Keywords: literate programming, interactive shell, tmate
;; URL: https://github.com/ahendriksen/ob-tmate
;; Version: 0.1.5
;; Package-version: 0.1.5
;; Package-Requires: ((emacs "25.1") (seq "2.3") (s "1.9.0"))

;; This file is NOT part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Org-Babel support for tmate.
;;
;; Heavily inspired by 'eev' from Eduardo Ochs and ob-screen.el from
;; Benjamin Andresen.
;;
;; See documentation on https://github.com/ahendriksen/ob-tmate
;;
;; You can test the default setup with
;; M-x org-babel-tmate-test RET

;;; Code:

(require 'ob)
(require 'seq)
;; s was a bit of a pain to get into spacemacs, unsure why
;; (require 's)
;; we only use s-join, so I found a simple implementation

;; https://stackoverflow.com/questions/8830888/whats-the-canonical-way-to-join-strings-in-a-list
;; renamed function to s-join
(defun %d (stream &rest args)
  "internal function, writing the dynamic value of the variable
DELIM to the output STREAM. To be called from inside JOIN."
  (declare (ignore args)
           (special delim))
  (princ delim stream))

(defun s-join (delim list)
  "creates a string, with the elements of list printed and each
element separated by DELIM"
  (declare (special delim))
  (format nil "~{~a~^~/%d/~:*~}" list))

 ;; "~{      iteration start
 ;; ~a      print element
 ;; ~^      exit iteration if no more elements
 ;; ~/%d/   call function %d with one element
 ;; ~:*     move one element backwards
 ;; ~}"     end of iteration command


(defcustom org-babel-tmate-location "tmate"
  "The command location for tmate.
Change in case you want to use a different tmate than the one in your $PATH."
  :group 'org-babel
  :type 'string)

(defcustom org-babel-tmate-session-prefix "org-babel-session-"
  "The string that will be prefixed to tmate session names started by ob-tmate."
  :group 'org-babel
  :type 'string)

(defcustom org-babel-tmate-default-window-name "ob1"
  "This is the default tmate window name used for windows that are not explicitly named in an org session."
  :group 'org-babel
  :type 'string)

(defvar org-babel-default-header-args:tmate
  '((:results . "silent")
    (:session . "default")
    (:socket . nil)
    (:terminal . "gnome-terminal"))
  "Default arguments to use when running tmate source blocks.")

(add-to-list 'org-src-lang-modes '("tmate" . sh))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; org-babel interface
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun org-babel-execute:tmate (body params)
  "Send a block of code via tmate to a terminal using Babel.
\"default\" session is used when none is specified.
Argument BODY the body of the tmate code block.
Argument PARAMS the org parameters of the code block."
  (message "Sending source code block to interactive terminal session...")
  (save-window-excursion
    (let* ((org-session (cdr (assq :session params)))
	   (terminal (cdr (assq :terminal params)))
	   (socket (cdr (assq :socket params)))
	   (socket (when socket (expand-file-name socket)))
	   (ob-session (ob-tmate--from-org-session org-session socket))
     (session-alive (ob-tmate--session-alive-p ob-session))
	   (window-alive (ob-tmate--window-alive-p ob-session)))
      ;; Create tmate session and window if they do not yet exist
      (message "OB-TMATE: Checking for session: %S" session-alive)
      (unless session-alive (message "OB-TMATE: create-session"))
      (unless session-alive (ob-tmate--create-session ob-session))
      (message "OB-TMATE: Checking for window: %S" window-alive)
      (unless window-alive (message "OB-TMATE: create-window"))
      (unless window-alive (ob-tmate--create-window ob-session))
      ;; Start terminal window if the session does not yet exist
      ;; (unless session-alive
	    ;; (ob-tmate--start-terminal-window ob-session terminal))
      ;; Wait until tmate window is available
      (while (not (ob-tmate--window-alive-p ob-session)))
      ;; Disable window renaming from within tmate
      (ob-tmate--disable-renaming ob-session)
      (ob-tmate--send-body
       ob-session (org-babel-expand-body:generic body params)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ob-tmate object
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(cl-defstruct (ob-tmate- (:constructor ob-tmate--create)
			(:copier ob-tmate--copy))
  session
  window
  socket)

(defun ob-tmate--tmate-session (org-session)
  "Extract tmate session from ORG-SESSION string."
  (let* ((session (car (split-string org-session ":"))))
    (concat org-babel-tmate-session-prefix
	    (if (string-equal "" session) "default" session))))
(defun ob-tmate--tmate-window (org-session)
  "Extract tmate window from ORG-SESSION string."
  (let* ((window (cadr (split-string org-session ":"))))
    (if (string-equal "" window) nil window)))

(defun ob-tmate--from-org-session (org-session &optional socket)
  "Create a new ob-tmate-session object from ORG-SESSION specification.
Optional argument SOCKET: the location of the tmate socket (only use if non-standard)."

  (ob-tmate--create
   :session (ob-tmate--tmate-session org-session)
   :window (ob-tmate--tmate-window org-session)
   :socket socket))

(defun ob-tmate--window-default (ob-session)
  "Extracts the tmate window from the ob-tmate- object.
Returns `org-babel-tmate-default-window-name' if no window specified.

Argument OB-SESSION: the current ob-tmate session."
  (if (ob-tmate--window ob-session)
      (ob-tmate--window ob-session)
      org-babel-tmate-default-window-name))

(defun ob-tmate--target (ob-session)
  "Constructs a tmate target from the `ob-tmate-' object.

If no window is specified, use first window.

Argument OB-SESSION: the current ob-tmate session."
  (let* ((target-session (ob-tmate--session ob-session))
	 (window (ob-tmate--window ob-session))
	 (target-window (if window (concat "=" window) "^")))
    (concat target-session ":" target-window)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Process execution functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun ob-tmate--execute (ob-session &rest args)
  "Execute a tmate command with arguments as given.

Argument OB-SESSION: the current ob-tmate session.
Optional command-line arguments can be passed in ARGS."
  (if (ob-tmate--socket ob-session)
      (progn
        (message (concat "OB-TMATE: execute on provided socket: => " (ob-tmate--socket ob-session)))
        (message (concat "OB-TMATE: execute args: => " (s-join " " args)))
        (message (concat "OB-TMATE: applying 'start-process"))
        (setenv "TMUX")
       (apply 'start-process "ob-tmate" "*Messages*"
	     org-babel-tmate-location
	     "-S" (ob-tmate--socket ob-session)
	     args)
       )
    (progn
      (message (concat "OB-TMATE: execute args: => " (s-join " " args)))
      ;; (message (concat "OB-TMATE: execute ob-session: => " ob-session))
     (message (concat "OB-TMATE: execute start-process:" (ob-tmate--socket ob-session)))
     (setenv "TMUX")
    (apply 'start-process
	   "ob-tmate" "*Messages*" org-babel-tmate-location args)))
  )

(defun ob-tmate--execute-string (ob-session &rest args)
  "Execute a tmate command with arguments as given.
Returns stdout as a string.

Argument OB-SESSION: the current ob-tmate session.  Optional
command-line arguments can be passed in ARGS and are
automatically space separated."
  (let* ((socket (ob-tmate--socket ob-session))
	 (args (if socket (cons "-S" (cons socket args)) args)))
    (message "OB_TMATE: execute-string %S" args)
  (shell-command-to-string
   (concat org-babel-tmate-location " "
	   (s-join " " args)))))

(defun ob-tmate--start-terminal-window (ob-session terminal)
  "Start a TERMINAL window with tmate attached to session.

Argument OB-SESSION: the current ob-tmate session."
  (message "OB-TMATE: start-terminal-window")
  (let* ((process-name (concat "org-babel: terminal")))
    (unless (ob-tmate--socket ob-session)
      (if (string-equal terminal "xterm")
	  (start-process process-name "*Messages*"
			 terminal
			 "-T" (ob-tmate--target ob-session)
			 "-e" org-babel-tmate-location "attach-session"
       )
	(start-process process-name "*Messages*"
		       terminal "--"
		       org-babel-tmate-location "attach-session"
           )))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Tmate interaction
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun ob-tmate--create-session (ob-session)
  "Create a tmate session if it does not yet exist.

Argument OB-SESSION: the current ob-tmate session."
  (unless (ob-tmate--session-alive-p ob-session)
    ;; This ensures the TMATE variable is unset
    ;; This hack gets us a tmate_ssh string
    ;; tmate -S /tmp/tmate.sock new-session -d ; tmate -S /tmp/tmate.sock wait tmate-ready ; tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}'
    (message "OB-TMATE: Creating new / connect to existing tmate session")
    ;; (message (concat "OB-TMATE: ob-session" ob-session))
    (message (concat "OB-TMATE: ob-tmate--session ob-session => " (ob-tmate--session ob-session)))
    (message (concat "OB-TMATE: ob-tmate--window => " (ob-tmate--window ob-session)))
    (message (concat "OB-TMATE: ob-tmate--window-default => " (ob-tmate--window-default ob-session)))
    (ob-tmate--execute ob-session
                       "new-session"
                       ;; "-A" ;; attach if it already exists
                       "-d" ;; just create the session, don't attach.
                       ;; "-S" (ob-tmate--socket ob-session)
                       ;; "-S" "/tmp/ob-tmate-socket" ;; Static for now
                       ;; "-u" ;; UTF-8 please... only in newer tmux
                       ;; "-vv" ;; Logs please... also only in newer tmux
                       ;; "-c" (expand-file-name "~") ;; start in home directory
                       "-s" (ob-tmate--session ob-session)
                       "-n" (ob-tmate--window-default ob-session)
                       )
    (message "OB-TMATE: Waiting for tmate to be ready")
    (ob-tmate--execute ob-session
    "wait" "tmate-ready"
    )
    ;; how can we capture this?
    ;; (setq ob-tmate-ssh-string (ob-tmate--execute-string ob-session
    ;;                   "display" "-p" "#{tmate_ssh}"
    ;;                   ))
    ;; (message (concat "OB-TMATE: " ob-tmate-ssh-string))
    )
  )

(defun ob-tmate--create-window (ob-session)
  "Create a tmate window in session if it does not yet exist.

Argument OB-SESSION: the current ob-tmate session."
  (unless (ob-tmate--window-alive-p ob-session)
    (message "tmate execute session")
    (ob-tmate--execute ob-session
     ;; "-S" (ob-tmate--socket ob-session)
     "new-window"
     "-c" (expand-file-name "~") ;; start in home directory
     "-n" (ob-tmate--window-default ob-session))))

(defun ob-tmate--set-window-option (ob-session option value)
  "If window exists, set OPTION for window.

Argument OB-SESSION: the current ob-tmate session."
  (when (ob-tmate--window-alive-p ob-session)
    (ob-tmate--execute ob-session
    ;; "-S" (ob-tmate--socket ob-session)
    "new-window"
     "set-window-option"
     "-t" (ob-tmate--window ob-session)
     option value)))

(defun ob-tmate--disable-renaming (ob-session)
  "Disable renaming features for tmate window.

Disabling renaming improves the chances that ob-tmate will be able
to find the window again later.

Argument OB-SESSION: the current ob-tmate session."
  (progn
    (ob-tmate--set-window-option ob-session "allow-rename" "off")
    (ob-tmate--set-window-option ob-session "automatic-rename" "off")))

(defun ob-tmate--send-keys (ob-session line)
  "If tmate window exists, send a LINE of text to it.

Argument OB-SESSION: the current ob-tmate session."
  (when (ob-tmate--window-alive-p ob-session)
    (ob-tmate--execute ob-session
     ;; "-S" (ob-tmate--socket ob-session)
     "send-keys"
     "-l"
     ;; "-t" (ob-tmate--target ob-session)
     line "\n")))

(defun ob-tmate--send-body (ob-session body)
  "If tmate window (passed in OB-SESSION) exists, send BODY to it.

Argument OB-SESSION: the current ob-tmate session."
  (let ((lines (split-string body "[\n\r]+")))
    (when (ob-tmate--window-alive-p ob-session)
      (mapc (lambda (l) (ob-tmate--send-keys ob-session l)) lines))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Tmate interrogation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun start-process--advice (name buffer program &rest program-args)
  "figure out how the process is being called"
  (message "%S %S %S %S" name buffer program (s-join " " program-args))
  )
(advice-add 'start-process :after 'start-process--advice)
(advice-remove 'start-process 'advice-start--process)


(defun ob-tmate--session-alive-p (ob-session)
  "Check if SESSION exists by parsing output of \"tmate ls\".

Argument OB-SESSION: the current ob-tmate session."
  (message (concat "OB-TMATE: session-alive-p socket: " (ob-tmate--socket ob-session)))
  ;; session check is a bit simpler with tmate
  ;; There is only one session per socket
  ;; if we can 'tmate ls' and return zero, we are good
  (= 0 (apply 'call-process org-babel-tmate-location nil nil nil
	       "-S" (ob-tmate--socket ob-session)
	       '("ls"))
  ))

(defun ob-tmate--window-alive-p (ob-session)
  "Check if WINDOW exists in tmate session.

If no window is specified in OB-SESSION, returns 't."
  (let* ((window (ob-tmate--window ob-session))
	 (target (ob-tmate--target ob-session))
	 (output (ob-tmate--execute-string ob-session
		  "list-panes"
		  "-F 'yes_exists'"
		  "-t" (concat "'" window "'")
      )))
    (cond (window
	   (string-equal "yes_exists\n" output))
	  ((null window)
	   't))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Test functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun ob-tmate--open-file (path)
  "Open file as string.

Argument PATH: the location of the file."
(with-temp-buffer
    (insert-file-contents-literally path)
    (buffer-substring (point-min) (point-max))))

(defun ob-tmate--test ()
  "Test if the default setup works.  The terminal should shortly flicker."
  (interactive)
  (let* ((random-string (format "%s" (random 99999)))
         (tmpfile (org-babel-temp-file "ob-tmate-test-"))
         (body (concat "echo '" random-string "' > " tmpfile))
         tmp-string)
    (org-babel-execute:tmate body org-babel-default-header-args:tmate)
    ;; XXX: need to find a better way to do the following
    (while (or (not (file-readable-p tmpfile))
	       (= 0 (length (ob-tmate--open-file tmpfile))))
      ;; do something, otherwise this will be optimized away
      (format "org-babel-tmate: File not readable yet."))
    (setq tmp-string (ob-tmate--open-file tmpfile))
    (delete-file tmpfile)
    (message (concat "org-babel-tmate: Setup "
                     (if (string-match random-string tmp-string)
                         "WORKS."
		       "DOESN'T work.")))))

(provide 'ob-tmate)



;;; ob-tmate.el ends here
