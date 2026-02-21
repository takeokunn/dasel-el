;;; dasel.el --- Emacs interface to dasel -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>
;; Maintainer: takeokunn <bararararatty@gmail.com>
;; URL: https://github.com/takeokunn/dasel-el
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, data, json, yaml, toml, xml

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

;; This package provides an Emacs interface to dasel
;; (https://github.com/TomWright/dasel), a command-line tool for
;; querying, converting, formatting, and editing structured data in
;; JSON, YAML, TOML, XML, and CSV formats.
;;
;; Prerequisites:
;;
;; - Emacs 29.1 or later
;; - dasel v2.8 or later binary installed and available in your PATH
;;   (https://github.com/TomWright/dasel)
;;
;; The package is organized into several modules:
;;
;; - `dasel-interactive' / `consult-dasel' -- Live querying with
;;   real-time preview.  Type a dasel selector in the minibuffer and
;;   see matching results update in a side window as you type.
;;   `consult-dasel' provides the same experience using consult's
;;   asynchronous preview mechanism.
;;
;; - `dasel-convert' -- Convert between data formats.  Transform a
;;   buffer or region from one format to another (e.g., JSON to YAML).
;;   Includes convenience commands for common conversions.
;;
;; - `dasel-format' -- Pretty-print structured data in a buffer or
;;   region.  Also provides `dasel-format-on-save-mode', a minor mode
;;   that automatically formats the buffer before each save.
;;
;; - `dasel-edit' -- Modify values in-place using dasel selectors.
;;   Prompts for a selector, a value type, and a value, then runs
;;   dasel's put subcommand to update the document without leaving Emacs.
;;
;; Quick start:
;;
;;   1. Open a JSON file in Emacs.
;;   2. Run M-x `dasel-interactive'.
;;   3. Type a selector such as ".name" to extract values.
;;   4. Results appear in the *dasel-output* side window.
;;
;; Key customization variables:
;;
;; - `dasel-command' -- Path to the dasel binary (default: "dasel").
;; - `dasel-output-window-side' -- Side of the frame where the output
;;   window appears (default: right).
;; - `dasel-output-window-size' -- Size ratio for the output window.
;; - `dasel-output-mode-alist' -- Alist mapping format strings to
;;   major modes for syntax highlighting in the output buffer.

;;; Code:

(declare-function json-mode "ext:json-mode")
(declare-function json-ts-mode "json-ts-mode")
(declare-function js-json-mode "js")
(declare-function yaml-mode "ext:yaml-mode")
(declare-function yaml-ts-mode "yaml-ts-mode")
(declare-function toml-mode "ext:toml-mode")
(declare-function toml-ts-mode "toml-ts-mode")
(declare-function conf-toml-mode "conf-mode")
(declare-function nxml-mode "nxml-mode")
(declare-function xml-mode "ext:xml-mode")
(declare-function csv-mode "ext:csv-mode")

(defgroup dasel nil
  "Emacs interface to dasel."
  :group 'tools
  :prefix "dasel-")

(defcustom dasel-command "dasel"
  "Path to dasel binary."
  :type 'string
  :risky t
  :group 'dasel)

(defcustom dasel-output-buffer-name "*dasel-output*"
  "Name of the buffer used to display dasel output."
  :type 'string
  :group 'dasel)

(defcustom dasel-output-window-side 'right
  "Side of the frame where the dasel output window is displayed."
  :type '(choice (const :tag "Right" right)
                 (const :tag "Bottom" bottom)
                 (const :tag "Left" left)
                 (const :tag "Top" top))
  :group 'dasel)

(defcustom dasel-output-window-size 0.4
  "Size ratio for the dasel output window."
  :type 'float
  :group 'dasel)

(defcustom dasel-output-mode-alist
  '(("json" . json-ts-mode)
    ("yaml" . yaml-ts-mode)
    ("toml" . toml-ts-mode)
    ("xml"  . nxml-mode)
    ("csv"  . csv-mode))
  "Alist mapping dasel format strings to major mode symbols."
  :type '(alist :key-type string :value-type symbol)
  :group 'dasel)

(defvar-local dasel-buffer-format nil
  "Buffer-local override for the data format used by dasel.
When non-nil, this takes priority over all other format detection methods.")
(put 'dasel-buffer-format 'risky-local-variable t)

(defconst dasel-supported-formats '("json" "yaml" "toml" "xml" "csv")
  "List of data formats supported by dasel.")

;;; Format Detection

(defconst dasel--mode-format-alist
  '((json-mode     . "json")
    (json-ts-mode  . "json")
    (js-json-mode  . "json")
    (yaml-mode     . "yaml")
    (yaml-ts-mode  . "yaml")
    (toml-mode     . "toml")
    (toml-ts-mode  . "toml")
    (conf-toml-mode . "toml")
    (nxml-mode     . "xml")
    (xml-mode      . "xml")
    (csv-mode      . "csv"))
  "Alist mapping major modes to dasel format strings.")

(defconst dasel--extension-format-alist
  '(("json" . "json")
    ("yaml" . "yaml")
    ("yml"  . "yaml")
    ("toml" . "toml")
    ("xml"  . "xml")
    ("csv"  . "csv"))
  "Alist mapping file extensions to dasel format strings.")

(defun dasel--detect-format (&optional buffer)
  "Detect the data format of BUFFER (defaults to current buffer).
Returns a format string (\"json\", \"yaml\", \"toml\", \"xml\", \"csv\") or nil."
  (with-current-buffer (or buffer (current-buffer))
    (or dasel-buffer-format
        (alist-get major-mode dasel--mode-format-alist)
        (when-let* ((file (buffer-file-name))
                    (ext (file-name-extension file)))
          (alist-get ext dasel--extension-format-alist nil nil #'string=))
        (dasel--sniff-content))))

(defun dasel--sniff-content ()
  "Guess data format from buffer content.
Returns a format string or nil."
  (save-excursion
    (goto-char (point-min))
    (skip-chars-forward " \t\n\r")
    (cond
     ((memq (char-after) '(?\{ ?\[))
      "json")
     ((eql (char-after) ?<)
      "xml")
     ((looking-at-p "^[[:alpha:]_-].*:")
      "yaml")
     ((looking-at-p "^- ")
      "yaml"))))

;;; Mode Mapping

(defconst dasel--ts-mode-language-alist
  '((json-ts-mode . json)
    (yaml-ts-mode . yaml)
    (toml-ts-mode . toml))
  "Alist mapping tree-sitter modes to their language grammar symbols.")

(defun dasel--ts-mode-available-p (mode)
  "Return non-nil if tree-sitter MODE is usable.
Checks both that the mode function is defined and that
the required language grammar is installed."
  (and (fboundp mode)
       (fboundp 'treesit-language-available-p)
       (when-let* ((lang (alist-get mode dasel--ts-mode-language-alist)))
         (treesit-language-available-p lang))))

(defun dasel--mode-for-format (format)
  "Return the best available major mode symbol for FORMAT string.
Checks `dasel-output-mode-alist' first, then falls back to built-in defaults.
Prefers tree-sitter modes when available."
  (or (when-let* ((mode (alist-get format dasel-output-mode-alist nil nil #'string=)))
        (when (if (alist-get mode dasel--ts-mode-language-alist)
                  (dasel--ts-mode-available-p mode)
                (fboundp mode))
          mode))
      (pcase format
        ("json" (cond ((dasel--ts-mode-available-p 'json-ts-mode)  'json-ts-mode)
                      ((fboundp 'json-mode)     'json-mode)
                      (t                        'javascript-mode)))
        ("yaml" (cond ((dasel--ts-mode-available-p 'yaml-ts-mode)  'yaml-ts-mode)
                      ((fboundp 'yaml-mode)     'yaml-mode)
                      (t                        'fundamental-mode)))
        ("toml" (cond ((dasel--ts-mode-available-p 'toml-ts-mode)  'toml-ts-mode)
                      ((fboundp 'toml-mode)     'toml-mode)
                      ((fboundp 'conf-toml-mode) 'conf-toml-mode)
                      (t                        'fundamental-mode)))
        ("xml"  'nxml-mode)
        ("csv"  (if (fboundp 'csv-mode) 'csv-mode 'fundamental-mode))
        (_      'fundamental-mode))))

;;; Process Invocation

(defun dasel--run (input-string input-format &optional output-format selector &rest extra-args)
  "Run dasel with INPUT-STRING in INPUT-FORMAT.
Optional OUTPUT-FORMAT specifies the output format.
Optional SELECTOR is the dasel query selector.
Optional EXTRA-ARGS are additional arguments passed to dasel
before the selector.
Returns a plist (:output STRING :exit-code INT :error STRING)."
  (dasel--check-version)
  (let ((args (list "-r" input-format))
        (stderr-file (make-temp-file "dasel-stderr")))
    (when output-format
      (setq args (append args (list "-w" output-format))))
    (when extra-args
      (setq args (append args extra-args)))
    (when selector
      (setq args (append args (list selector))))
    (unwind-protect
        (with-temp-buffer
          (let* ((exit-code
                  (apply #'call-process-region
                         input-string nil
                         dasel-command
                         nil
                         (list (current-buffer) stderr-file)
                         nil
                         args))
                 (output (buffer-string))
                 (error-output
                  (with-temp-buffer
                    (insert-file-contents stderr-file)
                    (buffer-string))))
            (list :output output
                  :exit-code exit-code
                  :error error-output)))
      (delete-file stderr-file))))

(defun dasel--run-put (input-string format type value selector)
  "Run dasel put with INPUT-STRING in FORMAT.
TYPE is the value type (\"string\", \"int\", \"float\", \"bool\", \"json\").
VALUE is the new value to set.
SELECTOR is the dasel selector path.
Returns a plist (:output STRING :exit-code INT :error STRING)."
  (dasel--check-version)
  (let ((args (list "put" "-r" format "-w" format "-t" type "-v" value selector))
        (stderr-file (make-temp-file "dasel-stderr")))
    (unwind-protect
        (with-temp-buffer
          (let* ((exit-code
                  (apply #'call-process-region
                         input-string nil
                         dasel-command
                         nil
                         (list (current-buffer) stderr-file)
                         nil
                         args))
                 (output (buffer-string))
                 (error-output
                  (with-temp-buffer
                    (insert-file-contents stderr-file)
                    (buffer-string))))
            (list :output output
                  :exit-code exit-code
                  :error error-output)))
      (delete-file stderr-file))))

;;; Output Buffer Management

(defun dasel--get-output-buffer ()
  "Get or create the dasel output buffer."
  (get-buffer-create dasel-output-buffer-name))

(defun dasel--display-output (output-string format)
  "Display OUTPUT-STRING in the dasel output buffer with syntax highlighting.
FORMAT is used to determine the appropriate major mode."
  (let ((buf (dasel--get-output-buffer))
        (mode (dasel--mode-for-format format)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (unless (eq major-mode mode)
          (funcall mode))
        (insert output-string)
        (font-lock-flush)))
    (dasel--show-output-window)
    buf))

(defun dasel--display-error (error-string)
  "Display ERROR-STRING in the dasel output buffer with error face."
  (let ((buf (dasel--get-output-buffer)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (fundamental-mode)
        (insert (propertize error-string 'face 'error))))
    (dasel--show-output-window)
    buf))

(defun dasel--show-output-window ()
  "Show the dasel output buffer in a side window."
  (let ((buf (dasel--get-output-buffer)))
    (display-buffer-in-side-window
     buf
     `((side . ,dasel-output-window-side)
       (window-width . ,dasel-output-window-size)
       (window-height . ,dasel-output-window-size)))))

(defun dasel--close-output-window ()
  "Close the dasel output window if it is visible."
  (when-let* ((buf (get-buffer dasel-output-buffer-name))
              (win (get-buffer-window buf t)))
    (delete-window win)))

(defvar dasel--version-checked nil
  "Non-nil once dasel version has been verified in this session.")

;;; Version Check

(defun dasel--check-version ()
  "Check that dasel is installed and is version 2.8 or later.
Only dasel v2 is supported; v3 has incompatible CLI changes.
Signals `user-error' if dasel is not found or version is unsupported.
Caches the result so the check runs only once per Emacs session."
  (unless dasel--version-checked
    (unless (executable-find dasel-command)
      (user-error "Dasel binary not found; install from https://github.com/TomWright/dasel"))
    (let* ((output (with-temp-buffer
                     (call-process dasel-command nil (current-buffer) nil "--version")
                     (string-trim (buffer-string)))))
      (unless (string-prefix-p "development" output)
        (let* ((version-pair (when (string-match "\\([0-9]+\\)\\.\\([0-9]+\\)\\.[0-9]+" output)
                                (cons (string-to-number (match-string 1 output))
                                      (string-to-number (match-string 2 output)))))
               (major-version (car version-pair))
               (minor-version (cdr version-pair)))
          (unless version-pair
            (user-error "Could not parse dasel version from: %s" output))
          ;; Only v2.8+ is supported.  Dasel v3 introduces breaking CLI
          ;; changes (different subcommands, flags, and output behaviour)
          ;; that are incompatible with this package.
          (unless (and (= major-version 2) (>= minor-version 8))
            (user-error "Dasel v2.8+ is required; v3 is not supported (found %s)"
                        output)))))
    (setq dasel--version-checked t)))

;;; Selector Candidates

(defun dasel--selector-candidates (input-string format &optional prefix)
  "Return key names under PREFIX from INPUT-STRING in FORMAT.
PREFIX is a dasel selector path (e.g. \".users.[0]\").
When nil, returns top-level keys.
Uses dasel's .all().key() selector to enumerate keys.
Returns nil if the query fails."
  (let* ((selector (concat (or prefix "") ".all().key()"))
         (result (dasel--run input-string format "plain" selector)))
    (when (zerop (plist-get result :exit-code))
      (let ((output (string-trim (plist-get result :output))))
        (unless (string-empty-p output)
          (split-string output "\n" t))))))

(provide 'dasel)
;;; dasel.el ends here
