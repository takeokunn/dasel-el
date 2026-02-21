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
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt _collection &optional _predicate _require-match _initial _hist _def)
                 (pcase prompt
                   ("Selector: " "name")
                   ("Type: " "string")
                   ("Value: " "Bob")))))
      (dasel-test-with-mock-run 0 "name\nage\ntags" ""
        (dasel-test-with-mock-put 0 "{\"name\":\"Bob\",\"age\":30,\"tags\":[\"admin\",\"user\"]}" ""
          (dasel-edit-put)
          (should (equal (buffer-string)
                         "{\"name\":\"Bob\",\"age\":30,\"tags\":[\"admin\",\"user\"]}")))))))


(ert-deftest dasel-test-edit-put-preserves-point ()
  "Edit put restores point position after modification."
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (goto-char 5)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt _collection &optional _predicate _require-match _initial _hist _def)
                 (pcase prompt
                   ("Selector: " "name")
                   ("Type: " "string")
                   ("Value: " "Bob")))))
      (dasel-test-with-mock-run 0 "name\nage\ntags" ""
        (dasel-test-with-mock-put 0 "{\"name\":\"Bob\",\"age\":30}" ""
          (dasel-edit-put)
          (should (= (point) 5)))))))

(ert-deftest dasel-test-edit-put-error ()
  "Edit put signals user-error on non-zero exit code."
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt _collection &optional _predicate _require-match _initial _hist _def)
                 (pcase prompt
                   ("Selector: " "invalid.selector")
                   ("Type: " "string")
                   ("Value: " "x")))))
      (dasel-test-with-mock-run 0 "name\nage\ntags" ""
        (dasel-test-with-mock-put 1 "" "selector not found"
          (should-error (dasel-edit-put) :type 'user-error))))))

(ert-deftest dasel-test-edit-put-no-format ()
  "Edit put signals error when format cannot be detected."
  (with-temp-buffer
    (insert "random content")
    (fundamental-mode)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt _collection &optional _predicate _require-match _initial _hist _def)
                 (pcase prompt
                   ("Selector: " "dummy")
                   ("Type: " "string")
                   ("Value: " "dummy")))))
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
                ((symbol-function 'dasel--run)
                 (lambda (_input _in-fmt &optional _out-fmt _selector &rest _extra)
                   (list :output "db\nhost" :exit-code 0 :error "")))
                ((symbol-function 'completing-read)
                 (lambda (prompt _collection &optional _predicate _require-match _initial _hist _def)
                   (pcase prompt
                     ("Selector: " "db.host")
                     ("Type: " "string")
                     ("Value: " "prod")))))
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
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt _collection &optional _predicate _require-match _initial _hist _def)
                 (pcase prompt
                   ("Selector: " "name")
                   ("Type: " "string")
                   ("Value: " "Bob")))))
      (dasel-test-with-mock-run 0 "name\nage\ntags" ""
        (dasel-test-with-mock-put 0 "{\"name\":\"Bob\"}" ""
          (dasel-edit-put)
          (should (equal (buffer-string) "{\"name\":\"Bob\"}"))
          (should (listp buffer-undo-list))
          (should buffer-undo-list))))))

(ert-deftest dasel-test-edit-put-integration ()
  "Integration test: edit put with real dasel binary."
  (skip-unless (dasel-test-v2-available-p))
  (let ((dasel--version-checked t))
    (dasel-test-with-buffer "json" "{\"name\":\"Alice\"}"
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt _collection &optional _predicate _require-match _initial _hist _def)
                   (pcase prompt
                     ("Selector: " ".name")
                     ("Type: " "string")
                     ("Value: " "Bob")))))
        (dasel-edit-put)
        (should (string-match-p "Bob" (buffer-string)))))))

(ert-deftest dasel-test-edit-selector-candidates-success ()
  "Selector candidates returns list of keys."
  (dasel-test-with-mock-run 0 "name\nage\ntags" ""
    (let ((result (dasel-edit--selector-candidates "{}" "json")))
      (should (equal result '("name" "age" "tags"))))))

(ert-deftest dasel-test-edit-selector-candidates-failure ()
  "Selector candidates returns nil on dasel error."
  (dasel-test-with-mock-run 1 "" "error"
    (should-not (dasel-edit--selector-candidates "{}" "json"))))

(ert-deftest dasel-test-edit-selector-candidates-empty ()
  "Selector candidates returns nil for empty output."
  (dasel-test-with-mock-run 0 "" ""
    (should-not (dasel-edit--selector-candidates "{}" "json"))))

(ert-deftest dasel-test-edit-infer-type-int ()
  "Infer type returns int for integer strings."
  (should (equal (dasel-edit--infer-type "42") "int"))
  (should (equal (dasel-edit--infer-type "-7") "int"))
  (should (equal (dasel-edit--infer-type "0") "int")))

(ert-deftest dasel-test-edit-infer-type-float ()
  "Infer type returns float for decimal strings."
  (should (equal (dasel-edit--infer-type "3.14") "float"))
  (should (equal (dasel-edit--infer-type "-0.5") "float")))

(ert-deftest dasel-test-edit-infer-type-bool ()
  "Infer type returns bool for true/false."
  (should (equal (dasel-edit--infer-type "true") "bool"))
  (should (equal (dasel-edit--infer-type "false") "bool")))

(ert-deftest dasel-test-edit-infer-type-json ()
  "Infer type returns json for object/array values."
  (should (equal (dasel-edit--infer-type "{\"a\":1}") "json"))
  (should (equal (dasel-edit--infer-type "[1,2]") "json")))

(ert-deftest dasel-test-edit-infer-type-string ()
  "Infer type returns string for other values."
  (should (equal (dasel-edit--infer-type "hello") "string"))
  (should (equal (dasel-edit--infer-type "") "string")))

(ert-deftest dasel-test-edit-current-value-success ()
  "Current value returns trimmed output on success."
  (dasel-test-with-mock-run 0 "Alice\n" ""
    (should (equal (dasel-edit--current-value "{}" "json" ".name") "Alice"))))

(ert-deftest dasel-test-edit-current-value-failure ()
  "Current value returns nil on dasel error."
  (dasel-test-with-mock-run 1 "" "not found"
    (should-not (dasel-edit--current-value "{}" "json" ".missing"))))

(ert-deftest dasel-test-edit-put-free-form-selector ()
  "Edit put works with free-form selector when candidates are empty."
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt _collection &optional _predicate _require-match _initial _hist _def)
                 (pcase prompt
                   ("Selector: " ".tags.[0]")
                   ("Type: " "string")
                   ("Value: " "superadmin")))))
      (dasel-test-with-mock-run 1 "" "error"
        (dasel-test-with-mock-put 0 "{\"name\":\"Alice\",\"tags\":[\"superadmin\",\"user\"]}" ""
          (dasel-edit-put)
          (should (string-match-p "superadmin" (buffer-string))))))))

(ert-deftest dasel-test-edit-put-nil-current-value ()
  "Edit put defaults to string type when current value is nil."
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (let ((captured-type nil)
          (captured-def nil)
          (captured-require-match nil))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt _collection &optional _predicate require-match _initial _hist def)
                   (pcase prompt
                     ("Selector: " ".newkey")
                     ("Type: " (setq captured-type def) "string")
                     ("Value: "
                      (setq captured-def def)
                      (setq captured-require-match require-match)
                      "newval")))))
        (dasel-test-with-mock-run 1 "" "not found"
          (dasel-test-with-mock-put 0 "{\"name\":\"Alice\",\"newkey\":\"newval\"}" ""
            (dasel-edit-put)
            (should (equal captured-type "string"))
            (should (null captured-def))
            (should (null captured-require-match))))))))

(ert-deftest dasel-test-edit-value-candidates-bool ()
  "Value candidates for bool type returns true and false."
  (should (equal (dasel-edit--value-candidates "bool" nil) '("true" "false")))
  (should (equal (dasel-edit--value-candidates "bool" "true") '("true" "false"))))

(ert-deftest dasel-test-edit-value-candidates-with-current ()
  "Value candidates returns current value as candidate."
  (should (equal (dasel-edit--value-candidates "string" "Alice") '("Alice")))
  (should (equal (dasel-edit--value-candidates "int" "42") '("42"))))

(ert-deftest dasel-test-edit-value-candidates-nil ()
  "Value candidates returns nil when no current value and not bool."
  (should-not (dasel-edit--value-candidates "string" nil))
  (should-not (dasel-edit--value-candidates "int" nil)))

(provide 'dasel-edit-test)
;;; dasel-edit-test.el ends here
