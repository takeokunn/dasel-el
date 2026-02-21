;;; dasel-test-helpers.el --- Shared test helpers for dasel -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Shared macros and utilities for dasel ERT tests.
;; Provides two-level mocking:
;;   Level 1: `dasel-test-with-mock-process' - mocks `call-process-region'
;;   Level 2: `dasel-test-with-mock-run' - mocks `dasel--run'

;;; Code:

(require 'cl-lib)
(require 'dasel)

(defmacro dasel-test-with-mock-process (exit-code stdout stderr &rest body)
  "Execute BODY with `call-process-region' mocked.
EXIT-CODE is the integer exit code to return.
STDOUT is a string to insert into the output buffer.
STDERR is a string to write to the stderr temp file.
Also sets `dasel--version-checked' to t to bypass version checks."
  (declare (indent 3) (debug t))
  `(let ((dasel--version-checked t))
     (cl-letf (((symbol-function 'call-process-region)
                (lambda (_start _end _program &optional _delete destination _display &rest _args)
                  (let ((buf (if (listp destination) (car destination) destination))
                        (stderr-file (when (listp destination) (cadr destination))))
                    (when (bufferp buf)
                      (with-current-buffer buf (insert ,stdout)))
                    (when (and stderr-file (stringp ,stderr) (not (string-empty-p ,stderr)))
                      (with-temp-file stderr-file (insert ,stderr)))
                    ,exit-code))))
       ,@body)))

(defmacro dasel-test-with-mock-run (exit-code output error &rest body)
  "Execute BODY with `dasel--run' mocked.
EXIT-CODE is the integer exit code to return.
OUTPUT is the string output.
ERROR is the string error.
Also sets `dasel--version-checked' to t to bypass version checks."
  (declare (indent 3) (debug t))
  `(let ((dasel--version-checked t))
     (cl-letf (((symbol-function 'dasel--run)
                (lambda (_input _in-fmt &optional _out-fmt _selector &rest _extra)
                  (list :output ,output :exit-code ,exit-code :error ,error))))
       ,@body)))

(defmacro dasel-test-with-mock-put (exit-code output error &rest body)
  "Execute BODY with `dasel--run-put' mocked.
EXIT-CODE is the integer exit code to return.
OUTPUT is the string output.
ERROR is the string error.
Also sets `dasel--version-checked' to t to bypass version checks."
  (declare (indent 3) (debug t))
  `(let ((dasel--version-checked t))
     (cl-letf (((symbol-function 'dasel--run-put)
                (lambda (_input _fmt _type _value _selector)
                  (list :output ,output :exit-code ,exit-code :error ,error))))
       ,@body)))

(defmacro dasel-test-with-buffer (format content &rest body)
  "Execute BODY in a temp buffer with FORMAT and CONTENT.
Sets `dasel-buffer-format' as a buffer-local variable."
  (declare (indent 2) (debug t))
  `(with-temp-buffer
     (insert ,content)
     (setq-local dasel-buffer-format ,format)
     ,@body))

(defconst dasel-test-safe-mode-alist
  '(("json" . fundamental-mode)
    ("yaml" . fundamental-mode)
    ("toml" . fundamental-mode)
    ("xml"  . fundamental-mode)
    ("csv"  . fundamental-mode))
  "Mode alist using `fundamental-mode' for batch testing.
Avoids tree-sitter mode activation failures in --batch -Q.")

(defun dasel-test-v2-available-p ()
  "Return non-nil if dasel v2.8+ is available on this system."
  (and (executable-find dasel-command)
       (let ((output (with-temp-buffer
                       (call-process dasel-command nil (current-buffer) nil "--version")
                       (string-trim (buffer-string)))))
         (or (string-prefix-p "development" output)
             (when (string-match "\\([0-9]+\\)\\.\\([0-9]+\\)\\." output)
               (let ((major (string-to-number (match-string 1 output)))
                     (minor (string-to-number (match-string 2 output))))
                 (and (= major 2) (>= minor 8))))))))

(defconst dasel-test-sample-json
  "{\"name\":\"Alice\",\"age\":30,\"tags\":[\"admin\",\"user\"]}"
  "Sample JSON for testing.")

(defconst dasel-test-sample-yaml
  "name: Alice\nage: 30\ntags:\n  - admin\n  - user\n"
  "Sample YAML for testing.")

(defconst dasel-test-sample-toml
  "name = \"Alice\"\nage = 30\ntags = [\"admin\", \"user\"]\n"
  "Sample TOML for testing.")

(defconst dasel-test-sample-xml
  "<root><name>Alice</name><age>30</age></root>"
  "Sample XML for testing.")

(provide 'dasel-test-helpers)
;;; dasel-test-helpers.el ends here
