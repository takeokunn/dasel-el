;;; dasel-format.el --- Pretty-print and format buffers with dasel -*- lexical-binding: t; -*-

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

;; Pretty-printing and on-save formatting for structured data files
;; (JSON, YAML, TOML, XML, CSV) using dasel.  Provides `dasel-format-buffer',
;; `dasel-format-region', and `dasel-format-on-save-mode'.

;;; Code:

(require 'dasel)

;;;###autoload
(defun dasel-format-buffer ()
  "Format the current buffer using dasel.
Detects the data format via `dasel--detect-format' and pretty-prints
the buffer contents by performing an identity conversion (same input
and output format).  Point position is preserved as much as possible."
  (interactive)
  (let ((fmt (dasel--detect-format)))
    (unless fmt
      (user-error "Cannot detect data format for buffer"))
    (let* ((saved-point (point))
           (input (buffer-substring-no-properties (point-min) (point-max)))
           (result (dasel--run input fmt fmt))
           (exit-code (plist-get result :exit-code))
           (output (plist-get result :output))
           (err (plist-get result :error)))
      (unless (zerop exit-code)
        (user-error "Dasel format error: %s" (string-trim (or err "unknown error"))))
      (undo-boundary)
      (atomic-change-group
        (delete-region (point-min) (point-max))
        (insert output))
      (goto-char (min saved-point (point-max))))))

;;;###autoload
(defun dasel-format-region (beg end)
  "Format the region between BEG and END using dasel.
Detects the data format via `dasel--detect-format' and pretty-prints
the region contents by performing an identity conversion."
  (interactive "r")
  (let ((fmt (dasel--detect-format)))
    (unless fmt
      (user-error "Cannot detect data format for buffer"))
    (let* ((input (buffer-substring-no-properties beg end))
           (result (dasel--run input fmt fmt))
           (exit-code (plist-get result :exit-code))
           (output (plist-get result :output))
           (err (plist-get result :error)))
      (unless (zerop exit-code)
        (user-error "Dasel format error: %s" (string-trim (or err "unknown error"))))
      (undo-boundary)
      (atomic-change-group
        (delete-region beg end)
        (goto-char beg)
        (insert output)))))

;;;###autoload
(define-minor-mode dasel-format-on-save-mode
  "Minor mode to auto-format buffer with dasel before saving."
  :lighter " DaselFmt"
  :group 'dasel
  (if dasel-format-on-save-mode
      (add-hook 'before-save-hook #'dasel-format-buffer nil t)
    (remove-hook 'before-save-hook #'dasel-format-buffer t)))

(provide 'dasel-format)
;;; dasel-format.el ends here
