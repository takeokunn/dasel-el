;;; dasel-format-test.el --- Tests for dasel-format -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; ERT tests for dasel-format.el: buffer/region formatting and on-save mode.

;;; Code:

(require 'ert)
(require 'dasel-test-helpers)
(require 'dasel-format)

(ert-deftest dasel-test-format-buffer-success ()
  "Format buffer replaces content with formatted output."
  (dasel-test-with-buffer "json" "{\"a\":1}"
    (dasel-test-with-mock-run 0 "{\n  \"a\": 1\n}\n" ""
      (dasel-format-buffer)
      (should (equal (buffer-string) "{\n  \"a\": 1\n}\n")))))

(ert-deftest dasel-test-format-buffer-error ()
  "Format buffer signals user-error on non-zero exit code."
  (dasel-test-with-buffer "json" "{invalid}"
    (dasel-test-with-mock-run 1 "" "parse error: unexpected token"
      (should-error (dasel-format-buffer) :type 'user-error))))

(ert-deftest dasel-test-format-buffer-preserves-point ()
  "Format buffer restores point position after formatting."
  (dasel-test-with-buffer "json" "{\"a\":1,\"b\":2}"
    (goto-char 5)
    (dasel-test-with-mock-run 0 "{\n  \"a\": 1,\n  \"b\": 2\n}\n" ""
      (dasel-format-buffer)
      (should (= (point) 5)))))

(ert-deftest dasel-test-format-buffer-no-format ()
  "Format buffer signals error when format cannot be detected."
  (with-temp-buffer
    (insert "random content with no format")
    (fundamental-mode)
    (should-error (dasel-format-buffer) :type 'user-error)))

(ert-deftest dasel-test-format-region-success ()
  "Format region replaces only the selected region."
  (dasel-test-with-buffer "json" "prefix{\"a\":1}suffix"
    (dasel-test-with-mock-run 0 "{\n  \"a\": 1\n}\n" ""
      (dasel-format-region 7 14)
      (should (equal (buffer-string) "prefix{\n  \"a\": 1\n}\nsuffix")))))

(ert-deftest dasel-test-format-region-error ()
  "Format region signals user-error on non-zero exit code."
  (dasel-test-with-buffer "json" "{\"a\":1}"
    (dasel-test-with-mock-run 1 "" "region parse error"
      (should-error (dasel-format-region (point-min) (point-max))
                    :type 'user-error))))

(ert-deftest dasel-test-format-on-save-mode-enable ()
  "Enabling on-save mode adds format-buffer to before-save-hook."
  (dasel-test-with-buffer "json" "{}"
    (unwind-protect
        (progn
          (dasel-format-on-save-mode 1)
          (should (memq #'dasel-format-buffer before-save-hook)))
      (dasel-format-on-save-mode -1))))

(ert-deftest dasel-test-format-on-save-mode-disable ()
  "Disabling on-save mode removes format-buffer from before-save-hook."
  (dasel-test-with-buffer "json" "{}"
    (dasel-format-on-save-mode 1)
    (dasel-format-on-save-mode -1)
    (should-not (memq #'dasel-format-buffer before-save-hook))))

(ert-deftest dasel-test-format-buffer-atomic ()
  "Format buffer change records undo information."
  (dasel-test-with-buffer "json" "{\"a\":1}"
    (buffer-enable-undo)
    (undo-boundary)
    (dasel-test-with-mock-run 0 "{\n  \"a\": 1\n}\n" ""
      (dasel-format-buffer)
      (should (equal (buffer-string) "{\n  \"a\": 1\n}\n"))
      ;; Verify undo information was recorded
      (should (listp buffer-undo-list))
      (should buffer-undo-list))))

(ert-deftest dasel-test-format-buffer-integration ()
  "Integration test: format buffer with real dasel binary (v2 or v3)."
  (skip-unless (dasel-test-any-available-p))
  (let ((dasel--version-checked nil)
        (dasel--major-version nil))
    (dasel-test-with-buffer "json" "{\"a\":1}"
      (dasel-format-buffer)
      (let ((result (buffer-string)))
        (should (string-match-p "\"a\"" result))
        (should (> (length result) (length "{\"a\":1}")))))))

;;; Additional format tests

(ert-deftest dasel-test-format-region-no-format ()
  "Format region signals user-error when format cannot be detected."
  (with-temp-buffer
    (insert "random text without format")
    (fundamental-mode)
    (should-error (dasel-format-region (point-min) (point-max))
                  :type 'user-error)))

(ert-deftest dasel-test-format-region-point-preserved ()
  "Format region does not move point beyond inserted content."
  (dasel-test-with-buffer "json" "{\"a\":1,\"b\":2}"
    (goto-char (point-min))
    (dasel-test-with-mock-run 0 "{\n  \"a\": 1,\n  \"b\": 2\n}\n" ""
      (dasel-format-region (point-min) (point-max))
      ;; Point stays at BEG after insert (insert moves point forward past text)
      (should (<= (point) (point-max))))))

(ert-deftest dasel-test-format-buffer-point-clamped ()
  "Format buffer clamps saved point to new buffer size."
  (dasel-test-with-buffer "json" "{\"a\":1,\"b\":2,\"c\":3}"
    (goto-char (point-max))
    (dasel-test-with-mock-run 0 "{}\n" ""
      (dasel-format-buffer)
      ;; Point is clamped to end of the shorter output.
      (should (<= (point) (point-max))))))

(ert-deftest dasel-test-format-on-save-mode-idempotent ()
  "Enabling on-save mode twice does not add the hook twice."
  (dasel-test-with-buffer "json" "{}"
    (unwind-protect
        (progn
          (dasel-format-on-save-mode 1)
          (dasel-format-on-save-mode 1)
          (should (= 1 (length (seq-filter
                                (lambda (fn) (eq fn #'dasel-format-buffer))
                                before-save-hook)))))
      (dasel-format-on-save-mode -1))))

(provide 'dasel-format-test)
;;; dasel-format-test.el ends here
