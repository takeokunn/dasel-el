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
;; and see the query result update in real time.

;;; Code:

(require 'cl-lib)
(require 'dasel)

(defgroup dasel-interactive nil
  "Interactive querying with dasel."
  :group 'dasel
  :prefix "dasel-interactive-")

(defcustom dasel-interactive-delay 0.3
  "Debounce delay in seconds before executing a dasel query."
  :type 'float
  :group 'dasel-interactive)

(defcustom dasel-interactive-output-format nil
  "Output format override for interactive queries.
When nil, the output format is the same as the input format."
  :type '(choice (const :tag "Same as input" nil)
                 (string :tag "Format"))
  :group 'dasel-interactive)

(defvar dasel-interactive--source-buffer nil
  "The buffer being queried.")

(defvar dasel-interactive--input-format nil
  "Detected input format of the source buffer.")

(defvar dasel-interactive--output-format nil
  "Current output format (may be cycled by the user).")

(defvar dasel-interactive--timer nil
  "Debounce timer for live updates.")

(defvar dasel-interactive--last-input nil
  "Last minibuffer contents, used for change detection.")

;;; Keymap

(defvar dasel-interactive-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map minibuffer-local-map)
    (define-key map (kbd "C-c C-o") #'dasel-interactive-cycle-output-format)
    (define-key map (kbd "C-j") #'electric-newline-and-maybe-indent)
    (define-key map (kbd "TAB") #'completion-at-point)
    map)
  "Keymap for `dasel-interactive'.")

;;; Completion

(defun dasel-interactive--completion-at-point ()
  "Completion-at-point function for dasel selectors.
Provides key-name completion based on the current path in the selector.
Parses the selector to find the parent path (up to the last dot),
then queries dasel for available keys under that path.
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
  "Execute the current dasel query and display the result."
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
  "Called from `after-change-functions' in the minibuffer.
Debounces and triggers `dasel-interactive--execute'."
  (let ((input (minibuffer-contents-no-properties)))
    (unless (equal input dasel-interactive--last-input)
      (setq dasel-interactive--last-input input)
      (when dasel-interactive--timer
        (cancel-timer dasel-interactive--timer)
        (setq dasel-interactive--timer nil))
      (if (string-empty-p input)
          (let ((buf (get-buffer dasel-output-buffer-name)))
            (when buf
              (with-current-buffer buf
                (let ((inhibit-read-only t))
                  (erase-buffer)))))
        (setq dasel-interactive--timer
              (run-with-timer dasel-interactive-delay nil
                              #'dasel-interactive--execute))))))

;;; Minibuffer Setup

(defun dasel-interactive--minibuffer-setup ()
  "Set up the minibuffer for interactive dasel querying.
Adds `dasel-interactive--update' to `after-change-functions' and
registers `dasel-interactive--completion-at-point' for TAB completion."
  (add-hook 'after-change-functions #'dasel-interactive--update nil t)
  (add-hook 'completion-at-point-functions #'dasel-interactive--completion-at-point nil t))

;;; Cycle Output Format

(defun dasel-interactive-cycle-output-format ()
  "Cycle through available output formats and re-execute the query."
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
Type a dasel selector in the minibuffer and see the result update
in real time.  Use \\<dasel-interactive-map>\\[dasel-interactive-cycle-output-format] to cycle output formats."
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
