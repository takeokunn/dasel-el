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
;; buffers using dasel selectors.  The selector prompt offers completion
;; candidates from top-level keys, the value prompt is pre-filled with the
;; current value, and the type is automatically inferred.

;;; Code:

(require 'dasel)

(defvar dasel-edit--selector-history nil
  "History list for dasel-edit-put selector input.")

(defvar dasel-edit--value-history nil
  "History list for dasel-edit-put value input.")

(defvar dasel-edit--type-history nil
  "History list for dasel-edit-put type input.")

(defun dasel-edit--selector-candidates (input-string format)
  "Return a list of top-level key names from INPUT-STRING in FORMAT.
Uses dasel's .all().key() selector to enumerate keys.
Returns nil if the query fails."
  (dasel--selector-candidates input-string format))

(defun dasel-edit--infer-type (value-string)
  "Infer the dasel put type from VALUE-STRING.
Returns one of \"int\", \"float\", \"bool\", \"json\", or \"string\"."
  (cond
   ((string-match-p "\\`-?[0-9]+\\'" value-string) "int")
   ((string-match-p "\\`-?[0-9]+\\.[0-9]+\\'" value-string) "float")
   ((string-match-p "\\`\\(true\\|false\\)\\'" value-string) "bool")
   ((and (not (string-empty-p value-string))
         (memq (aref value-string 0) '(?\{ ?\[)))
    "json")
   (t "string")))

(defun dasel-edit--current-value (input-string format selector)
  "Return the current value at SELECTOR in INPUT-STRING with FORMAT.
Returns the value as a string, or nil if the query fails."
  (let ((result (dasel--run input-string format "plain" selector)))
    (when (zerop (plist-get result :exit-code))
      (string-trim (plist-get result :output)))))

(defun dasel-edit--value-candidates (type current-value)
  "Return completion candidates for the value prompt based on TYPE.
When TYPE is \"bool\", returns (\"true\" \"false\").
Otherwise, returns a list containing CURRENT-VALUE if non-nil."
  (cond
   ((equal type "bool") '("true" "false"))
   (current-value (list current-value))
   (t nil)))

;;;###autoload
(defun dasel-edit-put ()
  "Edit a value in the current buffer using dasel's put subcommand.
Offers completion candidates for the selector from top-level keys,
pre-fills the value prompt with the current value at the selected path,
and infers a default type from the current value.
Runs dasel put to produce the full modified document and replaces
the buffer contents with the result."
  (interactive)
  (let ((fmt (dasel--detect-format)))
    (unless fmt
      (user-error "Cannot detect data format for current buffer"))
    (let* ((input (buffer-substring-no-properties (point-min) (point-max)))
           (candidates (dasel-edit--selector-candidates input fmt))
           (selector (completing-read "Selector: " candidates
                                      nil nil nil 'dasel-edit--selector-history))
           (current-val (dasel-edit--current-value input fmt selector))
           (default-type (if current-val
                             (dasel-edit--infer-type current-val)
                           "string"))
           (type (completing-read "Type: "
                                  '("string" "int" "float" "bool" "json")
                                  nil t nil 'dasel-edit--type-history default-type))
           (value (completing-read "Value: "
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
        (user-error "Dasel error: %s" (string-trim (plist-get result :error)))))))

(provide 'dasel-edit)
;;; dasel-edit.el ends here
