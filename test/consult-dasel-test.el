;;; consult-dasel-test.el --- Tests for consult-dasel -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; ERT tests for `consult-dasel'.

;;; Code:

(require 'ert)
(require 'dasel-test-helpers)
(condition-case nil
    (require 'consult-dasel)
  (error nil))

(ert-deftest dasel-test-consult-dasel-feature-available ()
  "Test that `consult-dasel' feature loads when consult is present."
  (skip-unless (featurep 'consult))
  (should (featurep 'consult-dasel)))

(ert-deftest dasel-test-consult-dasel-state-preview ()
  "Test state function preview action displays output."
  (skip-unless (featurep 'consult-dasel))
  (let ((dasel-output-mode-alist dasel-test-safe-mode-alist))
    (dasel-test-with-buffer "json" dasel-test-sample-json
      (dasel-test-with-mock-run 0 "\"Alice\"" ""
        (cl-letf (((symbol-function 'display-buffer-in-side-window)
                   (lambda (_buf _alist) nil)))
          (let* ((buf (current-buffer))
                 (state-fn (consult-dasel--state buf "json" nil)))
            (funcall state-fn 'preview "name")
            (let ((output-buf (get-buffer dasel-output-buffer-name)))
              (unwind-protect
                  (progn
                    (should output-buf)
                    (should (string= (with-current-buffer output-buf
                                       (buffer-string))
                                     "\"Alice\"")))
                (when-let* ((b (get-buffer dasel-output-buffer-name)))
                  (kill-buffer b))))))))))

(ert-deftest dasel-test-consult-dasel-state-exit ()
  "Test state function exit action closes the output window."
  (skip-unless (featurep 'consult-dasel))
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (let* ((buf (current-buffer))
           (state-fn (consult-dasel--state buf "json" nil)))
      (funcall state-fn 'exit nil))))

(ert-deftest dasel-test-consult-dasel-output-format-default ()
  "Default `consult-dasel-output-format' is nil."
  (skip-unless (featurep 'consult-dasel))
  (should-not consult-dasel-output-format))

(ert-deftest dasel-test-consult-dasel-state-return ()
  "Test state function return action returns nil."
  (skip-unless (featurep 'consult-dasel))
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (let* ((buf (current-buffer))
           (state-fn (consult-dasel--state buf "json" nil)))
      (should-not (funcall state-fn 'return "name")))))

(ert-deftest dasel-test-consult-dasel-state-preview-empty ()
  "Test state function preview with empty string closes output window."
  (skip-unless (featurep 'consult-dasel))
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (let* ((buf (current-buffer))
           (close-called nil)
           (state-fn (consult-dasel--state buf "json" nil)))
      (cl-letf (((symbol-function 'dasel--close-output-window)
                 (lambda () (setq close-called t))))
        (funcall state-fn 'preview "")
        (should close-called)))))

(ert-deftest dasel-test-consult-dasel-state-preview-nil ()
  "Test state function preview with nil candidate closes output window."
  (skip-unless (featurep 'consult-dasel))
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (let* ((buf (current-buffer))
           (close-called nil)
           (state-fn (consult-dasel--state buf "json" nil)))
      (cl-letf (((symbol-function 'dasel--close-output-window)
                 (lambda () (setq close-called t))))
        (funcall state-fn 'preview nil)
        (should close-called)))))

(ert-deftest dasel-test-consult-dasel-state-preview-error ()
  "Test state function preview shows error on failed query."
  (skip-unless (featurep 'consult-dasel))
  (let ((dasel-output-mode-alist dasel-test-safe-mode-alist)
        (dasel-output-buffer-name "*dasel-test-consult-err*"))
    (dasel-test-with-buffer "json" dasel-test-sample-json
      (unwind-protect
          (dasel-test-with-mock-run 1 "" "bad selector"
            (cl-letf (((symbol-function 'display-buffer-in-side-window)
                       (lambda (_buf _alist) nil)))
              (let* ((buf (current-buffer))
                     (state-fn (consult-dasel--state buf "json" nil)))
                (funcall state-fn 'preview "invalid.path")
                (let ((out-buf (get-buffer "*dasel-test-consult-err*")))
                  (should out-buf)
                  (with-current-buffer out-buf
                    (should (string= (buffer-string) "bad selector"))
                    (should (eq 'error (get-text-property (point-min) 'face))))))))
        (when-let* ((b (get-buffer "*dasel-test-consult-err*")))
          (kill-buffer b))))))

(ert-deftest dasel-test-consult-dasel-state-with-output-format ()
  "Test state function passes output format to dasel--run."
  (skip-unless (featurep 'consult-dasel))
  (let ((dasel-output-mode-alist dasel-test-safe-mode-alist)
        (dasel-output-buffer-name "*dasel-test-consult-fmt*")
        (captured-out-fmt nil))
    (dasel-test-with-buffer "json" dasel-test-sample-json
      (unwind-protect
          (let ((dasel--version-checked t))
            (cl-letf (((symbol-function 'dasel--run)
                       (lambda (_input _in-fmt &optional out-fmt _selector &rest _extra)
                         (setq captured-out-fmt out-fmt)
                         (list :output "name: Alice" :exit-code 0 :error "")))
                      ((symbol-function 'display-buffer-in-side-window)
                       (lambda (_buf _alist) nil)))
              (let* ((buf (current-buffer))
                     (state-fn (consult-dasel--state buf "json" "yaml")))
                (funcall state-fn 'preview "name")
                (should (equal captured-out-fmt "yaml")))))
        (when-let* ((b (get-buffer "*dasel-test-consult-fmt*")))
          (kill-buffer b))))))

(provide 'consult-dasel-test)
;;; consult-dasel-test.el ends here
