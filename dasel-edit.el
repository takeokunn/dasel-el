;;; dasel-edit.el --- In-place data editing via dasel -*- lexical-binding: t; -*-

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

;; Provides in-place data editing via dasel's put subcommand.
;; Use `dasel-edit-put' to modify values in JSON, YAML, TOML, XML, and CSV
;; buffers using dasel selectors.

;;; Code:

(require 'dasel)

(defvar dasel-edit--selector-history nil
  "History list for dasel-edit-put selector input.")

(defvar dasel-edit--value-history nil
  "History list for dasel-edit-put value input.")

(defvar dasel-edit--type-history nil
  "History list for dasel-edit-put type input.")

;;;###autoload
(defun dasel-edit-put ()
  "Edit a value in the current buffer using dasel's put subcommand.
Prompts for a selector, a value type, and a value, then runs dasel put
to produce the full modified document and replaces the buffer contents
with the result."
  (interactive)
  (let ((fmt (dasel--detect-format)))
    (unless fmt
      (user-error "Cannot detect data format for current buffer"))
    (let* ((selector (read-string "Selector: " nil 'dasel-edit--selector-history))
           (type (completing-read "Type: "
                                  '("string" "int" "float" "bool" "json")
                                  nil t nil 'dasel-edit--type-history "string"))
           (value (read-string "Value: " nil 'dasel-edit--value-history))
           (input (buffer-substring-no-properties (point-min) (point-max)))
           (saved-point (point))
           (result (dasel--run-put input fmt type value selector)))
      (if (zerop (plist-get result :exit-code))
          (progn
            (undo-boundary)
            (atomic-change-group
              (erase-buffer)
              (insert (plist-get result :output)))
            (goto-char (min saved-point (point-max))))
        (user-error "Dasel error: %s" (string-trim (plist-get result :error)))))))

(provide 'dasel-edit)
;;; dasel-edit.el ends here
