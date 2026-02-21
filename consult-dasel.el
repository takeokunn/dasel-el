;;; consult-dasel.el --- Consult integration for dasel -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>
;; Maintainer: takeokunn <bararararatty@gmail.com>
;; URL: https://github.com/takeokunn/dasel-el
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (consult "1.0"))
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

;; Consult integration for dasel, providing interactive dasel queries
;; with live preview using the consult framework.
;;
;; Usage:
;;   M-x consult-dasel
;;
;; Open a buffer containing JSON, YAML, TOML, XML, or CSV data and
;; invoke `consult-dasel'.  Type a dasel selector (e.g., "name",
;; "users[0]") to see the query result displayed live in a side
;; window.

;;; Code:

(require 'dasel)
(require 'consult)

(defgroup consult-dasel nil
  "Consult integration for dasel."
  :group 'consult
  :group 'dasel
  :prefix "consult-dasel-")

(defcustom consult-dasel-output-format nil
  "Output format override for consult-dasel queries.
When nil, the output format matches the input format."
  :type '(choice (const :tag "Same as input" nil)
                 (const :tag "JSON" "json")
                 (const :tag "YAML" "yaml")
                 (const :tag "TOML" "toml")
                 (const :tag "XML" "xml")
                 (const :tag "CSV" "csv"))
  :group 'consult-dasel)

(defvar consult-dasel--history nil
  "History for `consult-dasel' queries.")

(defun consult-dasel--state (source-buffer input-format output-format)
  "Create a consult state function for dasel queries.
SOURCE-BUFFER is the buffer containing the input data.
INPUT-FORMAT is the detected format of the source data.
OUTPUT-FORMAT is the desired output format, or nil for same as input."
  (lambda (action candidate)
    (pcase action
      ('preview
       (if (and candidate (not (string-empty-p candidate)))
           (let* ((input (with-current-buffer source-buffer
                           (buffer-substring-no-properties (point-min) (point-max))))
                  (result (dasel--run input input-format output-format candidate)))
             (if (zerop (plist-get result :exit-code))
                 (dasel--display-output (plist-get result :output)
                                        (or output-format input-format))
               (dasel--display-error (plist-get result :error))))
         (dasel--close-output-window)))
      ('exit
       (dasel--close-output-window))
      ('return nil))))

;;;###autoload
(defun consult-dasel ()
  "Interactively query the current buffer with dasel using consult.
The current buffer must contain data in a format supported by dasel
\(JSON, YAML, TOML, XML, or CSV).  As you type a dasel selector,
the query result is displayed live in a side window."
  (interactive)
  (let* ((source-buffer (current-buffer))
         (input-format (dasel--detect-format source-buffer)))
    (unless input-format
      (user-error "Cannot detect data format in current buffer"))
    (consult--prompt
     :prompt "dasel: "
     :initial ""
     :state (consult-dasel--state source-buffer input-format
                                  consult-dasel-output-format)
     :preview-key (list :debounce 0.3 'any)
     :history 'consult-dasel--history)))

(provide 'consult-dasel)
;;; consult-dasel.el ends here
