;;; dasel-edit-test.el --- Tests for dasel-edit -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; ERT tests for dasel-edit.el: in-place data editing via dasel selectors.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'dasel-test-helpers)
(require 'dasel-edit)

(ert-deftest dasel-test-edit-put-success ()
  "Edit put replaces buffer with modified output."
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &optional _initial _history)
                 (pcase prompt
                   ("Selector: " "name")
                   ("Value: " "Bob"))))
              ((symbol-function 'completing-read)
               (lambda (_prompt _collection &optional _predicate _require-match _initial _hist _def)
                 "string")))
      (dasel-test-with-mock-put 0 "{\"name\":\"Bob\",\"age\":30,\"tags\":[\"admin\",\"user\"]}" ""
        (dasel-edit-put)
        (should (equal (buffer-string)
                       "{\"name\":\"Bob\",\"age\":30,\"tags\":[\"admin\",\"user\"]}"))))))

(ert-deftest dasel-test-edit-put-preserves-point ()
  "Edit put restores point position after modification."
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (goto-char 5)
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &optional _initial _history)
                 (pcase prompt
                   ("Selector: " "name")
                   ("Value: " "Bob"))))
              ((symbol-function 'completing-read)
               (lambda (_prompt _collection &optional _predicate _require-match _initial _hist _def)
                 "string")))
      (dasel-test-with-mock-put 0 "{\"name\":\"Bob\",\"age\":30}" ""
        (dasel-edit-put)
        (should (= (point) 5))))))

(ert-deftest dasel-test-edit-put-error ()
  "Edit put signals user-error on non-zero exit code."
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &optional _initial _history)
                 (pcase prompt
                   ("Selector: " "invalid.selector")
                   ("Value: " "x"))))
              ((symbol-function 'completing-read)
               (lambda (_prompt _collection &optional _predicate _require-match _initial _hist _def)
                 "string")))
      (dasel-test-with-mock-put 1 "" "selector not found"
        (should-error (dasel-edit-put) :type 'user-error)))))

(ert-deftest dasel-test-edit-put-no-format ()
  "Edit put signals error when format cannot be detected."
  (with-temp-buffer
    (insert "random content")
    (fundamental-mode)
    (cl-letf (((symbol-function 'read-string)
               (lambda (_prompt &optional _initial _history) "dummy"))
              ((symbol-function 'completing-read)
               (lambda (_prompt _collection &optional _predicate _require-match _initial _hist _def)
                 "string")))
      (should-error (dasel-edit-put) :type 'user-error))))

(ert-deftest dasel-test-edit-put-calls-run-put ()
  "Edit put passes separate type, value, and selector to dasel--run-put."
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (let ((captured-args nil))
      (cl-letf (((symbol-function 'dasel--run-put)
                 (lambda (input fmt type value selector)
                   (setq captured-args (list :input input :fmt fmt :type type
                                             :value value :selector selector))
                   (list :output input :exit-code 0 :error "")))
                ((symbol-function 'read-string)
                 (lambda (prompt &optional _initial _history)
                   (pcase prompt
                     ("Selector: " "db.host")
                     ("Value: " "prod"))))
                ((symbol-function 'completing-read)
                 (lambda (_prompt _collection &optional _predicate _require-match _initial _hist _def)
                   "string")))
        (let ((dasel--version-checked t))
          (dasel-edit-put)
          (should (equal (plist-get captured-args :type) "string"))
          (should (equal (plist-get captured-args :value) "prod"))
          (should (equal (plist-get captured-args :selector) "db.host")))))))

(ert-deftest dasel-test-edit-put-atomic ()
  "Edit put change records undo information."
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (buffer-enable-undo)
    (undo-boundary)
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &optional _initial _history)
                 (pcase prompt
                   ("Selector: " "name")
                   ("Value: " "Bob"))))
              ((symbol-function 'completing-read)
               (lambda (_prompt _collection &optional _predicate _require-match _initial _hist _def)
                 "string")))
      (dasel-test-with-mock-put 0 "{\"name\":\"Bob\"}" ""
        (dasel-edit-put)
        (should (equal (buffer-string) "{\"name\":\"Bob\"}"))
        (should (listp buffer-undo-list))
        (should buffer-undo-list)))))

(ert-deftest dasel-test-edit-put-integration ()
  "Integration test: edit put with real dasel binary."
  (skip-unless (dasel-test-v2-available-p))
  (let ((dasel--version-checked t))
    (dasel-test-with-buffer "json" "{\"name\":\"Alice\"}"
      (cl-letf (((symbol-function 'read-string)
                 (lambda (prompt &optional _initial _history)
                   (pcase prompt
                     ("Selector: " ".name")
                     ("Value: " "Bob"))))
                ((symbol-function 'completing-read)
                 (lambda (_prompt _collection &optional _predicate _require-match _initial _hist _def)
                   "string")))
        (dasel-edit-put)
        (should (string-match-p "Bob" (buffer-string)))))))

(provide 'dasel-edit-test)
;;; dasel-edit-test.el ends here
