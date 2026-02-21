;;; dasel-convert-test.el --- Tests for dasel-convert -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; ERT tests for dasel-convert.el: format conversion and convenience commands.

;;; Code:

(require 'ert)
(require 'dasel-test-helpers)
(require 'dasel-convert)

(ert-deftest dasel-test-convert-success ()
  "Convert replaces buffer content with converted output."
  (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
    (dasel-test-with-buffer "json" dasel-test-sample-json
      (dasel-test-with-mock-run 0 dasel-test-sample-yaml ""
        (dasel-convert "yaml")
        (should (equal (buffer-string) dasel-test-sample-yaml))))))

(ert-deftest dasel-test-convert-updates-buffer-format ()
  "Convert updates `dasel-buffer-format' to the target format."
  (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
    (dasel-test-with-buffer "json" dasel-test-sample-json
      (dasel-test-with-mock-run 0 dasel-test-sample-yaml ""
        (dasel-convert "yaml")
        (should (equal dasel-buffer-format "yaml"))))))

(ert-deftest dasel-test-convert-error ()
  "Convert signals user-error on non-zero exit code."
  (dasel-test-with-buffer "json" "{invalid}"
    (dasel-test-with-mock-run 1 "" "conversion failed"
      (should-error (dasel-convert "yaml") :type 'user-error))))

(ert-deftest dasel-test-convert-json-to-yaml ()
  "Convenience command json-to-yaml converts and updates format."
  (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
    (dasel-test-with-buffer "json" dasel-test-sample-json
      (dasel-test-with-mock-run 0 dasel-test-sample-yaml ""
        (dasel-convert-json-to-yaml)
        (should (equal (buffer-string) dasel-test-sample-yaml))
        (should (equal dasel-buffer-format "yaml"))))))

(ert-deftest dasel-test-convert-yaml-to-json ()
  "Convenience command yaml-to-json converts and updates format."
  (dasel-test-with-buffer "yaml" dasel-test-sample-yaml
    (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
      (dasel-test-with-mock-run 0 dasel-test-sample-json ""
        (dasel-convert-yaml-to-json)
        (should (equal (buffer-string) dasel-test-sample-json))
        (should (equal dasel-buffer-format "json"))))))

(ert-deftest dasel-test-convert-json-to-toml ()
  "Convenience command json-to-toml converts and updates format."
  (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
    (dasel-test-with-buffer "json" dasel-test-sample-json
      (dasel-test-with-mock-run 0 dasel-test-sample-toml ""
        (dasel-convert-json-to-toml)
        (should (equal (buffer-string) dasel-test-sample-toml))
        (should (equal dasel-buffer-format "toml"))))))

(ert-deftest dasel-test-convert-toml-to-json ()
  "Convenience command toml-to-json converts and updates format."
  (dasel-test-with-buffer "toml" dasel-test-sample-toml
    (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
      (dasel-test-with-mock-run 0 dasel-test-sample-json ""
        (dasel-convert-toml-to-json)
        (should (equal (buffer-string) dasel-test-sample-json))
        (should (equal dasel-buffer-format "json"))))))

(ert-deftest dasel-test-convert-json-to-xml ()
  "Convenience command json-to-xml converts and updates format."
  (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
    (dasel-test-with-buffer "json" dasel-test-sample-json
      (dasel-test-with-mock-run 0 dasel-test-sample-xml ""
        (dasel-convert-json-to-xml)
        (should (equal (buffer-string) dasel-test-sample-xml))
        (should (equal dasel-buffer-format "xml"))))))

(ert-deftest dasel-test-convert-xml-to-json ()
  "Convenience command xml-to-json converts and updates format."
  (dasel-test-with-buffer "xml" dasel-test-sample-xml
    (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
      (dasel-test-with-mock-run 0 dasel-test-sample-json ""
        (dasel-convert-xml-to-json)
        (should (equal (buffer-string) dasel-test-sample-json))
        (should (equal dasel-buffer-format "json"))))))

(ert-deftest dasel-test-convert-yaml-to-toml ()
  "Convenience command yaml-to-toml converts and updates format."
  (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
    (dasel-test-with-buffer "yaml" dasel-test-sample-yaml
      (dasel-test-with-mock-run 0 dasel-test-sample-toml ""
        (dasel-convert-yaml-to-toml)
        (should (equal (buffer-string) dasel-test-sample-toml))
        (should (equal dasel-buffer-format "toml"))))))

(ert-deftest dasel-test-convert-toml-to-yaml ()
  "Convenience command toml-to-yaml converts and updates format."
  (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
    (dasel-test-with-buffer "toml" dasel-test-sample-toml
      (dasel-test-with-mock-run 0 dasel-test-sample-yaml ""
        (dasel-convert-toml-to-yaml)
        (should (equal (buffer-string) dasel-test-sample-yaml))
        (should (equal dasel-buffer-format "yaml"))))))

(ert-deftest dasel-test-convert-integration ()
  "Integration test: convert with real dasel binary."
  (skip-unless (dasel-test-v2-available-p))
  (let ((dasel--version-checked t)
        (dasel-output-mode-alist dasel-test-safe-mode-alist))
    (dasel-test-with-buffer "json" "{\"name\":\"Alice\"}"
      (dasel-convert "yaml")
      (should (string-match-p "name:" (buffer-string)))
      (should (equal dasel-buffer-format "yaml")))))

(ert-deftest dasel-test-convert-no-format ()
  "Convert signals error when format cannot be detected."
  (with-temp-buffer
    (insert "random content")
    (fundamental-mode)
    (should-error (dasel-convert "yaml") :type 'user-error)))

(ert-deftest dasel-test-convert-calls-mode-for-format ()
  "Convert activates appropriate major mode for target format."
  (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
    (dasel-test-with-buffer "json" dasel-test-sample-json
      (dasel-test-with-mock-run 0 dasel-test-sample-yaml ""
        (dasel-convert "yaml")
        (should (eq major-mode 'fundamental-mode))))))

(ert-deftest dasel-test-convert-replaces-buffer ()
  "Convert replaces full buffer and point ends at end of new content."
  (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
    (dasel-test-with-buffer "json" dasel-test-sample-json
      (goto-char 3)
      (dasel-test-with-mock-run 0 dasel-test-sample-yaml ""
        (dasel-convert "yaml")
        ;; insert moves point past the inserted text, landing at point-max.
        (should (= (point) (point-max)))))))

(ert-deftest dasel-test-convert-formats-customizable ()
  "`dasel-convert-formats' defaults to `dasel-supported-formats'."
  (should (equal dasel-convert-formats dasel-supported-formats)))

(provide 'dasel-convert-test)
;;; dasel-convert-test.el ends here
