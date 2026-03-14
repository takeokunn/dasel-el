;;; dasel-interactive.el --- Interactive querying of structured data with live preview -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>
;; Maintainer: takeokunn <bararararatty@gmail.com>
;; URL: https://github.com/takeokunn/dasel-el
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, data

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

;; Interactive querying of structured data (JSON, YAML, TOML, XML, CSV)
;; with live preview using dasel.  Type a dasel selector in the minibuffer
;; and see the query result update in real time in a side window.
;;
;; Use `dasel-interactive' as the entry point.  While the minibuffer is
;; active, \\<dasel-interactive-map>\\[dasel-interactive-cycle-output-format]
;; cycles through available output formats and \\[completion-at-point]
;; offers key completion based on the current selector path.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'dasel)

(defgroup dasel-interactive nil
  "Interactive querying with dasel."
  :group 'dasel
  :prefix "dasel-interactive-")

(defcustom dasel-interactive-delay 0.3
  "Debounce delay in seconds before executing a dasel query.
A lower value gives faster feedback but increases CPU usage."
  :type 'float
  :group 'dasel-interactive)

(defcustom dasel-interactive-output-format nil
  "Default output format for interactive queries.
When nil, the output format matches the input format.
Can be changed at runtime with `dasel-interactive-cycle-output-format'."
  :type '(choice (const :tag "Same as input" nil)
                 (string :tag "Format"))
  :group 'dasel-interactive)

(defvar dasel-interactive--source-buffer nil
  "The buffer being queried during an interactive session.")

(defvar dasel-interactive--input-format nil
  "Detected data format of `dasel-interactive--source-buffer'.")

(defvar dasel-interactive--output-format nil
  "Output format used in the current interactive session.
May be nil (same as input) or a dasel format string.
Cycled by `dasel-interactive-cycle-output-format'.")

(defvar dasel-interactive--timer nil
  "Debounce timer for deferred query execution.")

(defvar dasel-interactive--last-input nil
  "Last minibuffer contents seen by `dasel-interactive--update'.
Used to avoid redundant query executions.")

;;; Keymap

(defvar dasel-interactive-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map minibuffer-local-map)
    (define-key map (kbd "C-c C-o") #'dasel-interactive-cycle-output-format)
    (define-key map (kbd "C-j") #'electric-newline-and-maybe-indent)
    (define-key map (kbd "TAB") #'completion-at-point)
    map)
  "Keymap used in the `dasel-interactive' minibuffer.")

;;; Completion

(defun dasel-interactive--completion-at-point ()
  "Completion-at-point function for dasel selectors in the minibuffer.
Parses the selector text up to the last dot to determine the parent path,
queries dasel for available keys under that path, and returns a completion
table for the fragment after the last dot.
Note: dots inside bracket selectors (e.g. [\"my.key\"]) are not handled."
  (let* ((input (minibuffer-contents-no-properties))
         (input-start (minibuffer-prompt-end))
         (dot-pos (cl-position ?. input :from-end t)))
    (when dot-pos
      (let* ((parent (substring input 0 dot-pos))
             (frag-start (+ input-start dot-pos 1))
             (source-content (with-current-buffer dasel-interactive--source-buffer
                               (buffer-substring-no-properties (point-min) (point-max))))
             (keys (dasel--selector-candidates source-content
                                               dasel-interactive--input-format
                                               (if (string-empty-p parent) nil parent))))
        (when keys
          (list frag-start (point) keys))))))

;;; Execute

(defun dasel-interactive--execute ()
  "Execute the current minibuffer selector and display the result.
Does nothing when no minibuffer window is active."
  (when (active-minibuffer-window)
    (let* ((selector (with-current-buffer (window-buffer (active-minibuffer-window))
                       (minibuffer-contents-no-properties)))
           (source-content (with-current-buffer dasel-interactive--source-buffer
                             (buffer-substring-no-properties (point-min) (point-max))))
           (out-fmt dasel-interactive--output-format)
           (result (dasel--run source-content
                               dasel-interactive--input-format
                               out-fmt
                               selector)))
      (if (zerop (plist-get result :exit-code))
          (dasel--display-output (plist-get result :output)
                                 (or out-fmt dasel-interactive--input-format))
        (dasel--display-error (plist-get result :error))))))

;;; Live Update

(defun dasel-interactive--update (_beg _end _len)
  "Debounced handler for minibuffer input change.
Called from `after-change-functions'.  Clear the output buffer when
the selector is empty; otherwise schedule `dasel-interactive--execute'
after `dasel-interactive-delay' seconds."
  (let ((input (minibuffer-contents-no-properties)))
    (unless (equal input dasel-interactive--last-input)
      (setq dasel-interactive--last-input input)
      (when dasel-interactive--timer
        (cancel-timer dasel-interactive--timer)
        (setq dasel-interactive--timer nil))
      (if (string-empty-p input)
          (when-let* ((buf (get-buffer dasel-output-buffer-name)))
            (with-current-buffer buf
              (let ((inhibit-read-only t))
                (erase-buffer))))
        (setq dasel-interactive--timer
              (run-with-timer dasel-interactive-delay nil
                              #'dasel-interactive--execute))))))

;;; Minibuffer Setup

(defun dasel-interactive--minibuffer-setup ()
  "Prepare the minibuffer for interactive dasel querying.
Registers `dasel-interactive--update' on `after-change-functions' and
`dasel-interactive--completion-at-point' on `completion-at-point-functions'."
  (add-hook 'after-change-functions #'dasel-interactive--update nil t)
  (add-hook 'completion-at-point-functions #'dasel-interactive--completion-at-point nil t))

;;; Cycle Output Format

(defun dasel-interactive-cycle-output-format ()
  "Cycle to the next output format in `dasel-supported-formats' and re-query.
Wraps around after the last format.  The current format is shown in the
echo area."
  (interactive)
  (let* ((current dasel-interactive--output-format)
         (pos (if current
                  (seq-position dasel-supported-formats current #'string=)
                -1))
         (next-pos (mod (1+ (or pos -1)) (length dasel-supported-formats)))
         (next-fmt (nth next-pos dasel-supported-formats)))
    (setq dasel-interactive--output-format next-fmt)
    (message "Output format: %s" next-fmt)
    (dasel-interactive--execute)))

;;; Entry Point

;;;###autoload
(defun dasel-interactive ()
  "Interactively query the current buffer with dasel.
Opens a minibuffer session.  As you type a dasel selector the result
is displayed in real time in a side window.
Press \\<dasel-interactive-map>\\[dasel-interactive-cycle-output-format] \
to cycle output formats.
Press \\[completion-at-point] for key completion.
Abort the session with \\[keyboard-quit] to close the output window."
  (interactive)
  (let ((fmt (dasel--detect-format)))
    (unless fmt
      (user-error "Cannot detect data format for current buffer"))
    (setq dasel-interactive--source-buffer (current-buffer)
          dasel-interactive--input-format fmt
          dasel-interactive--output-format dasel-interactive-output-format
          dasel-interactive--last-input nil)
    (let ((aborted t))
      (unwind-protect
          (progn
            (minibuffer-with-setup-hook #'dasel-interactive--minibuffer-setup
              (read-from-minibuffer "dasel: " nil dasel-interactive-map))
            (setq aborted nil))
        (when dasel-interactive--timer
          (cancel-timer dasel-interactive--timer)
          (setq dasel-interactive--timer nil))
        (setq dasel-interactive--source-buffer nil
              dasel-interactive--input-format nil
              dasel-interactive--last-input nil)
        (when aborted
          (dasel--close-output-window))))))

(provide 'dasel-interactive)
;;; dasel-interactive.el ends here
