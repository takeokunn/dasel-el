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

;; In-place data editing using dasel's put subcommand.  The main entry
;; point is `dasel-edit-put', which prompts for a selector, value type,
;; and value, then replaces the buffer with the modified document.
;;
;; The selector prompt offers completion candidates from the document's
;; top-level keys.  The value prompt is pre-filled with the current value
;; at the selected path when it can be determined.  The value type is
;; inferred automatically from the current value and may be changed at
;; the prompt.

;;; Code:

(require 'dasel)

(defvar dasel-edit--selector-history nil
  "Minibuffer history for `dasel-edit-put' selector input.")

(defvar dasel-edit--value-history nil
  "Minibuffer history for `dasel-edit-put' value input.")

(defvar dasel-edit--type-history nil
  "Minibuffer history for `dasel-edit-put' type input.")

;;; Internal helpers

(defun dasel-edit--infer-type (value-string)
  "Infer the dasel put type from VALUE-STRING.
Returns one of \"int\", \"float\", \"bool\", \"json\", or \"string\"."
  (cond
   ((string-match-p "\\`-?[0-9]+\\'" value-string)
    "int")
   ((string-match-p "\\`-?[0-9]+\\.[0-9]+\\'" value-string)
    "float")
   ((string-match-p "\\`\\(true\\|false\\)\\'" value-string)
    "bool")
   ((and (not (string-empty-p value-string))
         (memq (aref value-string 0) '(?\{ ?\[)))
    "json")
   (t "string")))

(defun dasel-edit--current-value (input-string format selector)
  "Return the current value at SELECTOR in INPUT-STRING parsed as FORMAT.
Uses dasel's plain output format to obtain a raw string value.
Returns the trimmed output string, or nil if the query fails."
  (let ((result (dasel--run input-string format "plain" selector)))
    (when (zerop (plist-get result :exit-code))
      (string-trim (plist-get result :output)))))

(defun dasel-edit--value-candidates (type current-value)
  "Return completion candidates for the value prompt given TYPE and CURRENT-VALUE.
When TYPE is \"bool\", returns (\"true\" \"false\").
Otherwise, returns a singleton list containing CURRENT-VALUE when non-nil,
or nil when there is no current value."
  (cond
   ((equal type "bool") '("true" "false"))
   (current-value (list current-value))
   (t nil)))

;;; Interactive command

;;;###autoload
(defun dasel-edit-put ()
  "Edit a value in the current buffer using dasel's put subcommand.
Prompts for a selector with completion from top-level keys, a value type
inferred from the current value and confirmed at the prompt, and a value
pre-filled with the current value when available.
Replaces the entire buffer with the modified document on success.
Signals `user-error' when the format cannot be detected or dasel fails."
  (interactive)
  (let ((fmt (dasel--detect-format)))
    (unless fmt
      (user-error "Cannot detect data format for current buffer"))
    (let* ((input (buffer-substring-no-properties (point-min) (point-max)))
           (candidates (dasel--selector-candidates input fmt))
           (selector
            (completing-read "Selector: " candidates
                             nil nil nil 'dasel-edit--selector-history))
           (current-val (dasel-edit--current-value input fmt selector))
           (default-type
            (if current-val (dasel-edit--infer-type current-val) "string"))
           (type
            (completing-read "Type: "
                             '("string" "int" "float" "bool" "json")
                             nil t nil 'dasel-edit--type-history default-type))
           (value
            (completing-read "Value: "
                             (dasel-edit--value-candidates type current-val)
                             nil (equal type "bool")
                             nil 'dasel-edit--value-history
                             current-val))
           (saved-point (point))
           (result (dasel--run-put input fmt type value selector)))
      (if (zerop (plist-get result :exit-code))
          (progn
            (undo-boundary)
            (atomic-change-group
              (erase-buffer)
              (insert (plist-get result :output)))
            (goto-char (min saved-point (point-max))))
        (user-error "Dasel error: %s"
                    (string-trim
                     (or (plist-get result :error) "unknown error")))))))

(provide 'dasel-edit)
;;; dasel-edit.el ends here
