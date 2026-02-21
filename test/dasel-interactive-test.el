;;; dasel-interactive-test.el --- Tests for dasel-interactive -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; ERT tests for `dasel-interactive'.

;;; Code:

(require 'ert)
(require 'dasel-test-helpers)
(require 'dasel-interactive)

(ert-deftest dasel-test-interactive-keymap-bindings ()
  "Verify that C-c C-o and C-j are bound in `dasel-interactive-map'."
  (should (eq (lookup-key dasel-interactive-map (kbd "C-c C-o"))
              #'dasel-interactive-cycle-output-format))
  (should (eq (lookup-key dasel-interactive-map (kbd "C-j"))
              #'electric-newline-and-maybe-indent)))

(ert-deftest dasel-test-interactive-cycle-output-format ()
  "Test that cycling output format advances through `dasel-supported-formats'."
  (let ((dasel-interactive--output-format nil))
    (cl-letf (((symbol-function 'dasel-interactive--execute) #'ignore))
      (dasel-interactive-cycle-output-format)
      (should (equal dasel-interactive--output-format "json"))
      (dasel-interactive-cycle-output-format)
      (should (equal dasel-interactive--output-format "yaml")))))

(ert-deftest dasel-test-interactive-cycle-wraps ()
  "Test that cycling past the last format wraps to the first."
  (let ((dasel-interactive--output-format "csv"))
    (cl-letf (((symbol-function 'dasel-interactive--execute) #'ignore))
      (dasel-interactive-cycle-output-format)
      (should (equal dasel-interactive--output-format "json")))))

(ert-deftest dasel-test-interactive-default-delay ()
  "Default `dasel-interactive-delay' is 0.3."
  (should (= dasel-interactive-delay 0.3)))

(ert-deftest dasel-test-interactive-default-output-format ()
  "Default `dasel-interactive-output-format' is nil."
  (should-not dasel-interactive-output-format))

(ert-deftest dasel-test-interactive-detect-format-error ()
  "Signal `user-error' when format cannot be detected."
  (cl-letf (((symbol-function 'dasel--detect-format) (lambda (&optional _buf) nil)))
    (should-error (dasel-interactive) :type 'user-error)))

(ert-deftest dasel-test-interactive-execute-success ()
  "Execute displays output on successful dasel query."
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (let ((dasel-interactive--source-buffer (current-buffer))
          (dasel-interactive--input-format "json")
          (dasel-interactive--output-format nil)
          (dasel-output-mode-alist dasel-test-safe-mode-alist)
          (dasel-output-buffer-name "*dasel-test-interactive*"))
      (unwind-protect
          (cl-letf (((symbol-function 'active-minibuffer-window) (lambda () t))
                    ((symbol-function 'window-buffer) (lambda (_win) (current-buffer)))
                    ((symbol-function 'minibuffer-contents-no-properties) (lambda () "name"))
                    ((symbol-function 'display-buffer-in-side-window) (lambda (_buf _alist) nil)))
            (dasel-test-with-mock-run 0 "\"Alice\"" ""
              (dasel-interactive--execute)
              (let ((out-buf (get-buffer "*dasel-test-interactive*")))
                (should out-buf)
                (should (string= (with-current-buffer out-buf (buffer-string))
                                 "\"Alice\"")))))
        (when-let* ((b (get-buffer "*dasel-test-interactive*")))
          (kill-buffer b))))))

(ert-deftest dasel-test-interactive-execute-error ()
  "Execute displays error on failed dasel query."
  (dasel-test-with-buffer "json" dasel-test-sample-json
    (let ((dasel-interactive--source-buffer (current-buffer))
          (dasel-interactive--input-format "json")
          (dasel-interactive--output-format nil)
          (dasel-output-buffer-name "*dasel-test-interactive-err*"))
      (unwind-protect
          (cl-letf (((symbol-function 'active-minibuffer-window) (lambda () t))
                    ((symbol-function 'window-buffer) (lambda (_win) (current-buffer)))
                    ((symbol-function 'minibuffer-contents-no-properties) (lambda () "bad.selector"))
                    ((symbol-function 'display-buffer-in-side-window) (lambda (_buf _alist) nil)))
            (dasel-test-with-mock-run 1 "" "selector not found"
              (dasel-interactive--execute)
              (let ((out-buf (get-buffer "*dasel-test-interactive-err*")))
                (should out-buf)
                (with-current-buffer out-buf
                  (should (string= (buffer-string) "selector not found"))
                  (should (eq 'error (get-text-property (point-min) 'face)))))))
        (when-let* ((b (get-buffer "*dasel-test-interactive-err*")))
          (kill-buffer b))))))

(ert-deftest dasel-test-interactive-execute-no-minibuffer ()
  "Execute does nothing when there is no active minibuffer."
  (cl-letf (((symbol-function 'active-minibuffer-window) (lambda () nil)))
    (dasel-interactive--execute)
    (should t)))

(ert-deftest dasel-test-interactive-update-change-detection ()
  "Update skips execution when input hasn't changed."
  (let ((dasel-interactive--last-input "name")
        (dasel-interactive--timer nil)
        (timer-created nil))
    (cl-letf (((symbol-function 'minibuffer-contents-no-properties) (lambda () "name"))
              ((symbol-function 'run-with-timer)
               (lambda (_secs _repeat fn &rest _args)
                 (setq timer-created t)
                 'fake-timer)))
      (dasel-interactive--update nil nil nil)
      (should-not timer-created))))

(ert-deftest dasel-test-interactive-update-empty-clears ()
  "Update clears output buffer when input becomes empty."
  (let ((dasel-interactive--last-input "something")
        (dasel-interactive--timer nil)
        (dasel-output-buffer-name "*dasel-test-clear*"))
    (unwind-protect
        (progn
          (with-current-buffer (get-buffer-create "*dasel-test-clear*")
            (insert "previous output"))
          (cl-letf (((symbol-function 'minibuffer-contents-no-properties) (lambda () "")))
            (dasel-interactive--update nil nil nil)
            (with-current-buffer (get-buffer "*dasel-test-clear*")
              (should (string-empty-p (buffer-string))))))
      (when-let* ((b (get-buffer "*dasel-test-clear*")))
        (kill-buffer b)))))

(ert-deftest dasel-test-interactive-update-creates-timer ()
  "Update creates a debounce timer when input changes."
  (let ((dasel-interactive--last-input nil)
        (dasel-interactive--timer nil)
        (dasel-interactive-delay 0.3)
        (timer-created nil))
    (cl-letf (((symbol-function 'minibuffer-contents-no-properties) (lambda () "name"))
              ((symbol-function 'run-with-timer)
               (lambda (secs _repeat _fn &rest _args)
                 (setq timer-created t)
                 (should (= secs 0.3))
                 'fake-timer)))
      (dasel-interactive--update nil nil nil)
      (should timer-created)
      (should (equal dasel-interactive--last-input "name")))))

(ert-deftest dasel-test-interactive-update-cancels-previous-timer ()
  "Update cancels existing timer before creating a new one."
  (let ((dasel-interactive--last-input "na")
        (dasel-interactive--timer 'old-timer)
        (cancelled-timer nil))
    (cl-letf (((symbol-function 'minibuffer-contents-no-properties) (lambda () "name"))
              ((symbol-function 'cancel-timer)
               (lambda (timer) (setq cancelled-timer timer)))
              ((symbol-function 'run-with-timer)
               (lambda (_secs _repeat _fn &rest _args) 'new-timer)))
      (dasel-interactive--update nil nil nil)
      (should (eq cancelled-timer 'old-timer))
      (should (eq dasel-interactive--timer 'new-timer)))))

(provide 'dasel-interactive-test)
;;; dasel-interactive-test.el ends here
