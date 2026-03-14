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
;; - dasel v2.8+ or v3.x binary installed and available in your PATH
;;   (https://github.com/TomWright/dasel).  Both major versions are
;;   supported; the package detects which is installed automatically.
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
;;   Prompts for a selector, a value type, and a value, then uses
;;   dasel to update the document without leaving Emacs.
;;
;; Quick start:
;;
;;   1. Open a JSON file in Emacs.
;;   2. Run M-x `dasel-interactive'.
;;   3. Type a selector such as "name" to extract values.
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

(require 'json)

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
When non-nil, this value is used instead of automatic format detection.
Must be one of the strings in `dasel-supported-formats' or nil.
Can be set via file-local variables: -*- dasel-buffer-format: \"json\" -*-")
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
  "Detect the data format of BUFFER, defaulting to the current buffer.
Detection order: buffer-local `dasel-buffer-format', major mode via
`dasel--mode-format-alist', file extension via
`dasel--extension-format-alist', content sniffing via
`dasel--sniff-content'.
Returns one of \"json\", \"yaml\", \"toml\", \"xml\", \"csv\", or nil."
  (with-current-buffer (or buffer (current-buffer))
    (or dasel-buffer-format
        (alist-get major-mode dasel--mode-format-alist)
        (when-let* ((file (buffer-file-name))
                    (ext (file-name-extension file)))
          (alist-get ext dasel--extension-format-alist nil nil #'string=))
        (dasel--sniff-content))))

(defun dasel--sniff-content ()
  "Guess data format from buffer content.
Checks the first non-whitespace character and common syntax patterns.
Returns a format string (\"json\", \"yaml\", \"toml\", or \"xml\"), or nil
when the format cannot be determined."
  (save-excursion
    (goto-char (point-min))
    (skip-chars-forward " \t\n\r")
    (cond
     ((memq (char-after) '(?\{ ?\[))
      "json")
     ((eql (char-after) ?<)
      "xml")
     ((looking-at-p "^[[:alpha:]_][[:alnum:]_-]*[[:space:]]*=")
      "toml")
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
  "Return non-nil if tree-sitter MODE is available and its grammar installed.
Returns nil if MODE is not in `dasel--ts-mode-language-alist', if
`treesit-language-available-p' is not defined, or if the grammar is absent."
  (and (fboundp mode)
       (fboundp 'treesit-language-available-p)
       (when-let* ((lang (alist-get mode dasel--ts-mode-language-alist)))
         (treesit-language-available-p lang))))

(defun dasel--mode-for-format (format)
  "Return the best available major mode symbol for FORMAT.
FORMAT is a dasel format string such as \"json\" or \"yaml\".
Checks `dasel-output-mode-alist' first; falls back to built-in defaults.
Tree-sitter modes are preferred when their grammar is installed."
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

;;; Version Detection

(defvar dasel--version-checked nil
  "Non-nil once the dasel binary version has been verified this session.
Reset to nil to force a fresh version check.")

(defvar dasel--major-version nil
  "Major version number of the detected dasel binary.
Set by `dasel--check-version'.  Either 2 or 3 (or nil before first check).")

(defun dasel--version-string ()
  "Return the raw version output from the dasel binary.
Uses `version' subcommand (v3+) first; falls back to `--version' flag (v2).
Returns nil when the binary is not found or produces no output."
  (when (executable-find dasel-command)
    (let ((output
           (with-temp-buffer
             ;; v3 uses `dasel version'; v2 uses `dasel --version'.
             ;; Try v3 first; if it fails, try v2.
             (if (zerop (call-process dasel-command nil (current-buffer) nil "version"))
                 (string-trim (buffer-string))
               (erase-buffer)
               (call-process dasel-command nil (current-buffer) nil "--version")
               (string-trim (buffer-string))))))
      (unless (string-empty-p output) output))))

(defun dasel--check-version ()
  "Verify the dasel binary is installed and detect its major version.
Supports dasel v2.8+ and v3.x.  Sets `dasel--major-version' to 2 or 3.
Signals `user-error' when the binary is missing or the version is
below 2.8.  Caches the result so the check runs only once per session."
  (unless dasel--version-checked
    (let ((output (dasel--version-string)))
      (unless output
        (user-error
         "Dasel binary not found; install from https://github.com/TomWright/dasel"))
      (if (string-prefix-p "development" output)
          ;; Development builds are treated as v3 (latest).
          (setq dasel--major-version 3)
        (let* ((pair (when (string-match "\\([0-9]+\\)\\.\\([0-9]+\\)" output)
                       (cons (string-to-number (match-string 1 output))
                             (string-to-number (match-string 2 output)))))
               (major (car pair))
               (minor (cdr pair)))
          (unless pair
            (user-error "Could not parse dasel version from: %s" output))
          (cond
           ((= major 3)
            (setq dasel--major-version 3))
           ((and (= major 2) (>= minor 8))
            (setq dasel--major-version 2))
           (t
            (user-error
             "Dasel v2.8+ or v3.x is required (found %s)" output))))))
    (setq dasel--version-checked t)))

;;; Process Invocation

(defun dasel--call-process (input-string args)
  "Run `dasel-command' with ARGS, feeding INPUT-STRING on stdin.
Returns a plist with :output (string), :exit-code (integer), :error (string)."
  (let ((stderr-file (make-temp-file "dasel-stderr")))
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

(defun dasel--run (input-string input-format &optional output-format selector &rest extra-args)
  "Run dasel on INPUT-STRING using INPUT-FORMAT as the read format.
OUTPUT-FORMAT specifies the write format; when nil the read format is used.
SELECTOR is a dasel selector expression; when nil no selector is passed.
EXTRA-ARGS is a list of additional flags inserted before the selector.
Returns a plist with keys :output (string), :exit-code (integer),
and :error (string).

This function automatically dispatches to the correct CLI syntax based
on the detected dasel major version (v2 or v3)."
  (dasel--check-version)
  (if (= dasel--major-version 3)
      (dasel--run-v3 input-string input-format output-format selector extra-args)
    (dasel--run-v2 input-string input-format output-format selector extra-args)))

(defun dasel--run-v2 (input-string input-format output-format selector extra-args)
  "Run a dasel v2 query on INPUT-STRING using INPUT-FORMAT.
OUTPUT-FORMAT, SELECTOR, and EXTRA-ARGS are handled identically to
`dasel--run'.  Internal helper; do not call directly."
  (let ((args (list "-r" input-format)))
    (when output-format
      (setq args (append args (list "-w" output-format))))
    (when extra-args
      (setq args (append args extra-args)))
    (when selector
      (setq args (append args (list selector))))
    (dasel--call-process input-string args)))

(defun dasel--run-v3 (input-string input-format output-format selector extra-args)
  "Run a dasel v3 query on INPUT-STRING using INPUT-FORMAT.
OUTPUT-FORMAT, SELECTOR, and EXTRA-ARGS are handled identically to
`dasel--run'.  Internal helper; do not call directly."
  (let ((args (list "-i" input-format)))
    (when output-format
      (setq args (append args (list "-o" output-format))))
    ;; When no selector is given, output the full document via --root.
    (unless selector
      (setq args (append args (list "--root"))))
    (when extra-args
      (setq args (append args extra-args)))
    (when selector
      (setq args (append args (list selector))))
    (dasel--call-process input-string args)))

(defun dasel--run-put (input-string format type value selector)
  "Run dasel put on INPUT-STRING in FORMAT.
TYPE is one of \"string\", \"int\", \"float\", \"bool\", or \"json\".
VALUE is the new value to assign at SELECTOR.
SELECTOR is a dasel selector path.
Returns a plist with keys :output (string), :exit-code (integer),
and :error (string).

Dispatches to v2 or v3 syntax based on the detected dasel version."
  (dasel--check-version)
  (if (= dasel--major-version 3)
      (dasel--run-put-v3 input-string format type value selector)
    (dasel--run-put-v2 input-string format type value selector)))

(defun dasel--run-put-v2 (input-string format type value selector)
  "Run a dasel v2 put on INPUT-STRING in FORMAT.
TYPE, VALUE, and SELECTOR are passed as v2 put subcommand flags.
Internal helper; do not call directly."
  (let ((args (list "put" "-r" format "-w" format "-t" type "-v" value selector)))
    (dasel--call-process input-string args)))

(defun dasel--run-put-v3 (input-string format type value selector)
  "Run a dasel v3 put on INPUT-STRING in FORMAT.
TYPE determines how VALUE is quoted in the assignment expression.
SELECTOR is the target path.  Internal helper; do not call directly."
  (let* ((quoted-value (dasel--v3-quote-value type value))
         (expr (format "%s = %s" selector quoted-value))
         (args (list "-i" format "-o" format "--root" expr)))
    (dasel--call-process input-string args)))

(defun dasel--v3-quote-value (type value)
  "Return VALUE formatted as a dasel v3 literal for TYPE.
TYPE is one of \"string\", \"int\", \"float\", \"bool\", or \"json\"."
  (pcase type
    ("string" (format "%S" value))           ; Emacs %S produces "value"
    ("bool"   value)                          ; true / false as-is
    ("json"   value)                          ; raw JSON object/array
    (_        value)))                        ; int, float: bare number

;;; Output Buffer Management

(defun dasel--get-output-buffer ()
  "Get or create the dasel output buffer."
  (get-buffer-create dasel-output-buffer-name))

(defun dasel--display-output (output-string format)
  "Display OUTPUT-STRING in the dasel output buffer with syntax highlighting.
FORMAT is a dasel format string used to select the appropriate major mode
via `dasel--mode-for-format'.  Returns the output buffer."
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
  "Display ERROR-STRING in the dasel output buffer using the error face.
Returns the output buffer."
  (let ((buf (dasel--get-output-buffer)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (fundamental-mode)
        (insert (propertize error-string 'face 'error))))
    (dasel--show-output-window)
    buf))

(defun dasel--show-output-window ()
  "Display the dasel output buffer in a side window.
The side and size are determined by `dasel-output-window-side' and
`dasel-output-window-size'."
  (let ((buf (dasel--get-output-buffer)))
    (display-buffer-in-side-window
     buf
     `((side . ,dasel-output-window-side)
       (window-width . ,dasel-output-window-size)
       (window-height . ,dasel-output-window-size)))))

(defun dasel--close-output-window ()
  "Close the dasel output window if it is currently visible.
Does nothing when the output buffer does not exist or has no window."
  (when-let* ((buf (get-buffer dasel-output-buffer-name))
              (win (get-buffer-window buf t)))
    (delete-window win)))

;;; Selector Candidates

(defun dasel--selector-candidates (input-string format &optional prefix)
  "Return key names under PREFIX in INPUT-STRING parsed as FORMAT.
PREFIX is a dasel selector path; when nil, top-level keys are returned.
On dasel v2, uses dasel's \".all().key()\" selector.
On dasel v3, fetches the sub-document as JSON and extracts keys in Emacs.
Returns a list of strings, or nil if the query fails or yields no output."
  (dasel--check-version)
  (if (= dasel--major-version 3)
      (dasel--selector-candidates-v3 input-string format prefix)
    (dasel--selector-candidates-v2 input-string format prefix)))

(defun dasel--selector-candidates-v2 (input-string format prefix)
  "Return key names under PREFIX in INPUT-STRING (FORMAT) using dasel v2.
Internal helper for `dasel--selector-candidates'."
  (let* ((selector (concat (or prefix "") ".all().key()"))
         (result (dasel--run input-string format "plain" selector)))
    (when (zerop (plist-get result :exit-code))
      (let ((output (string-trim (plist-get result :output))))
        (unless (string-empty-p output)
          (split-string output "\n" t))))))

(defun dasel--selector-candidates-v3 (input-string format prefix)
  "Return key names under PREFIX in INPUT-STRING (FORMAT) using dasel v3.
Fetches the sub-document as JSON and extracts object keys in Emacs Lisp.
Internal helper for `dasel--selector-candidates'."
  (let* ((selector (or prefix nil))
         ;; Fetch the target node as JSON; fall back to full doc when no prefix.
         (result (dasel--run input-string format "json" selector)))
    (when (zerop (plist-get result :exit-code))
      (condition-case nil
          (let* ((json-str (string-trim (plist-get result :output)))
                 (parsed (json-parse-string json-str :object-type 'hash-table)))
            (when (hash-table-p parsed)
              (let (keys)
                (maphash (lambda (k _v) (push k keys)) parsed)
                (nreverse keys))))
        (json-parse-error nil)))))

(provide 'dasel)
;;; dasel.el ends here
