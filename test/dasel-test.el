;;; dasel-test.el --- ERT tests for dasel.el -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; ERT tests for the core dasel.el library.

;;; Code:

(require 'ert)
(require 'dasel-test-helpers)

;;; Format Detection tests

(ert-deftest dasel-test-detect-format-buffer-local ()
  "Buffer-local `dasel-buffer-format' takes priority."
  (with-temp-buffer
    (setq-local dasel-buffer-format "toml")
    (should (equal "toml" (dasel--detect-format)))))

(ert-deftest dasel-test-detect-format-major-mode ()
  "Major mode is used via `dasel--mode-format-alist'."
  (with-temp-buffer
    (let ((major-mode 'json-ts-mode))
      (should (equal "json" (dasel--detect-format))))))

(ert-deftest dasel-test-detect-format-extension ()
  "File extension is used as fallback."
  (with-temp-buffer
    (let ((buffer-file-name "/tmp/test.json"))
      (should (equal "json" (dasel--detect-format))))))

(ert-deftest dasel-test-detect-format-nil ()
  "Returns nil for unrecognized buffer."
  (with-temp-buffer
    (should (eq nil (dasel--detect-format)))))

;;; Content sniffing tests

(ert-deftest dasel-test-sniff-json-object ()
  "`{' at start of content is detected as JSON."
  (with-temp-buffer
    (insert "{\"key\": \"value\"}")
    (should (equal "json" (dasel--sniff-content)))))

(ert-deftest dasel-test-sniff-json-array ()
  "`[' at start of content is detected as JSON."
  (with-temp-buffer
    (insert "[1, 2, 3]")
    (should (equal "json" (dasel--sniff-content)))))

(ert-deftest dasel-test-sniff-xml ()
  "`<' at start of content is detected as XML."
  (with-temp-buffer
    (insert "<root><name>Alice</name></root>")
    (should (equal "xml" (dasel--sniff-content)))))

(ert-deftest dasel-test-sniff-yaml-mapping ()
  "`key: value' pattern is detected as YAML."
  (with-temp-buffer
    (insert "name: Alice\nage: 30\n")
    (should (equal "yaml" (dasel--sniff-content)))))

(ert-deftest dasel-test-sniff-yaml-list ()
  "`- item' pattern is detected as YAML."
  (with-temp-buffer
    (insert "- admin\n- user\n")
    (should (equal "yaml" (dasel--sniff-content)))))

(ert-deftest dasel-test-sniff-whitespace-prefix ()
  "Leading whitespace is skipped before sniffing."
  (with-temp-buffer
    (insert "  \n\t  {\"key\": \"value\"}")
    (should (equal "json" (dasel--sniff-content)))))

;;; Tree-sitter availability tests

(ert-deftest dasel-test-ts-mode-available-p-no-grammar ()
  "Returns nil when tree-sitter grammar is not installed."
  (cl-letf (((symbol-function 'treesit-language-available-p)
             (lambda (_lang &optional _detail) nil)))
    (should-not (dasel--ts-mode-available-p 'json-ts-mode))))

(ert-deftest dasel-test-ts-mode-available-p-unknown-mode ()
  "Returns nil for a mode not in `dasel--ts-mode-language-alist'."
  (should-not (dasel--ts-mode-available-p 'some-unknown-ts-mode)))

(ert-deftest dasel-test-ts-mode-available-p-with-grammar ()
  "Returns non-nil when tree-sitter grammar is installed."
  (cl-letf (((symbol-function 'treesit-language-available-p)
             (lambda (_lang &optional _detail) t)))
    (should (dasel--ts-mode-available-p 'json-ts-mode))))

(ert-deftest dasel-test-mode-for-format-ts-grammar-missing-fallback ()
  "Falls back from tree-sitter mode when grammar is not installed."
  (cl-letf (((symbol-function 'treesit-language-available-p)
             (lambda (_lang &optional _detail) nil)))
    (let ((mode (dasel--mode-for-format "json")))
      (should-not (eq mode 'json-ts-mode))
      (should (memq mode '(json-mode javascript-mode))))))

(ert-deftest dasel-test-ts-mode-alist-sync ()
  "Every tree-sitter mode in output alist has a language mapping."
  (dolist (entry dasel-output-mode-alist)
    (let ((mode (cdr entry)))
      (when (string-suffix-p "-ts-mode" (symbol-name mode))
        (should (alist-get mode dasel--ts-mode-language-alist))))))

;;; Mode mapping tests

(ert-deftest dasel-test-mode-for-format-json ()
  "JSON format returns a JSON major mode."
  (let ((mode (dasel--mode-for-format "json")))
    (should (memq mode '(json-ts-mode json-mode javascript-mode)))))

(ert-deftest dasel-test-mode-for-format-xml ()
  "XML format returns `nxml-mode'."
  (should (eq 'nxml-mode (dasel--mode-for-format "xml"))))

(ert-deftest dasel-test-mode-for-format-unknown ()
  "Unknown format returns `fundamental-mode'."
  (should (eq 'fundamental-mode (dasel--mode-for-format "unknown-format"))))

(ert-deftest dasel-test-mode-for-format-custom-alist ()
  "Custom `dasel-output-mode-alist' is respected."
  (let ((dasel-output-mode-alist '(("json" . fundamental-mode))))
    (should (eq 'fundamental-mode (dasel--mode-for-format "json")))))

;;; Process invocation tests (Level 1 mock)

(ert-deftest dasel-test-run-success ()
  "Successful run returns plist with exit-code 0 and output."
  (dasel-test-with-mock-process 0 "{\"name\":\"Alice\"}" ""
    (let ((result (dasel--run "{\"name\":\"Alice\"}" "json")))
      (should (= 0 (plist-get result :exit-code)))
      (should (equal "{\"name\":\"Alice\"}" (plist-get result :output))))))

(ert-deftest dasel-test-run-error ()
  "Failed run returns plist with non-zero exit-code and error."
  (dasel-test-with-mock-process 1 "" "error: invalid selector"
    (let ((result (dasel--run "{}" "json" nil "bad-selector")))
      (should (= 1 (plist-get result :exit-code)))
      (should (equal "" (plist-get result :output)))
      (should (string-match-p "invalid selector" (plist-get result :error))))))

(ert-deftest dasel-test-run-with-selector ()
  "Selector is passed as the last argument."
  (let ((captured-args nil))
    (dasel-test-with-mock-process 0 "Alice" ""
      (cl-letf (((symbol-function 'call-process-region)
                 (lambda (_start _end _program &optional _delete destination _display &rest args)
                   (setq captured-args args)
                   (let ((buf (if (listp destination) (car destination) destination)))
                     (when (bufferp buf)
                       (with-current-buffer buf (insert "Alice"))))
                   0)))
        (dasel--run "{\"name\":\"Alice\"}" "json" nil ".name")
        (should (equal ".name" (car (last captured-args))))))))

(ert-deftest dasel-test-run-with-output-format ()
  "Output format flag -o is added to arguments."
  (let ((captured-args nil))
    (dasel-test-with-mock-process 0 "name: Alice\n" ""
      (cl-letf (((symbol-function 'call-process-region)
                 (lambda (_start _end _program &optional _delete destination _display &rest args)
                   (setq captured-args args)
                   (let ((buf (if (listp destination) (car destination) destination)))
                     (when (bufferp buf)
                       (with-current-buffer buf (insert "name: Alice\n"))))
                   0)))
        (dasel--run "{\"name\":\"Alice\"}" "json" "yaml")
        (should (member "-w" captured-args))
        (let ((pos (cl-position "-w" captured-args :test #'equal)))
          (should (equal "yaml" (nth (1+ pos) captured-args))))))))

(ert-deftest dasel-test-run-with-extra-args ()
  "Extra args are passed through to dasel."
  (let ((captured-args nil))
    (dasel-test-with-mock-process 0 "output" ""
      (cl-letf (((symbol-function 'call-process-region)
                 (lambda (_start _end _program &optional _delete destination _display &rest args)
                   (setq captured-args args)
                   (let ((buf (if (listp destination) (car destination) destination)))
                     (when (bufferp buf)
                       (with-current-buffer buf (insert "output"))))
                   0)))
        (dasel--run "{}" "json" nil nil "--compact" "--color=false")
        (should (member "--compact" captured-args))
        (should (member "--color=false" captured-args))))))

(ert-deftest dasel-test-run-put-args ()
  "put subcommand passes correct arguments to `call-process-region'."
  (let ((captured-args nil))
    (dasel-test-with-mock-process 0 "{\"name\":\"Bob\"}" ""
      (cl-letf (((symbol-function 'call-process-region)
                 (lambda (_start _end _program &optional _delete destination _display &rest args)
                   (setq captured-args args)
                   (let ((buf (if (listp destination) (car destination) destination)))
                     (when (bufferp buf)
                       (with-current-buffer buf (insert "{\"name\":\"Bob\"}"))))
                   0)))
        (dasel--run-put "{\"name\":\"Alice\"}" "json" "string" "Bob" ".name")
        (should (equal "put" (car captured-args)))
        (should (member "-r" captured-args))
        (should (member "-w" captured-args))
        (should (member "-t" captured-args))
        (should (member "-v" captured-args))
        (let ((r-pos (cl-position "-r" captured-args :test #'equal))
              (w-pos (cl-position "-w" captured-args :test #'equal))
              (t-pos (cl-position "-t" captured-args :test #'equal))
              (v-pos (cl-position "-v" captured-args :test #'equal)))
          (should (equal "json" (nth (1+ r-pos) captured-args)))
          (should (equal "json" (nth (1+ w-pos) captured-args)))
          (should (equal "string" (nth (1+ t-pos) captured-args)))
          (should (equal "Bob" (nth (1+ v-pos) captured-args))))
        (should (equal ".name" (car (last captured-args))))))))

;;; Version check tests

(ert-deftest dasel-test-check-version-not-found ()
  "Signals user-error when dasel binary is not found."
  (let ((dasel--version-checked nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) nil)))
      (should-error (dasel--check-version) :type 'user-error))))

(ert-deftest dasel-test-check-version-v2-ok ()
  "Succeeds for version 2.8.x output."
  (let ((dasel--version-checked nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) "/usr/bin/dasel"))
              ((symbol-function 'call-process)
               (lambda (_program &optional _infile _destination _display &rest _args)
                 (insert "dasel version 2.8.1")
                 0)))
      (dasel--check-version)
      (should (eq t dasel--version-checked)))))

(ert-deftest dasel-test-check-version-v3-rejected ()
  "Signals user-error for version 3.x.x."
  (let ((dasel--version-checked nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) "/usr/bin/dasel"))
              ((symbol-function 'call-process)
               (lambda (_program &optional _infile _destination _display &rest _args)
                 (insert "v3.2.2")
                 0)))
      (should-error (dasel--check-version) :type 'user-error))))

(ert-deftest dasel-test-check-version-v2-old ()
  "Signals user-error for version 2.7.x (below minimum 2.8)."
  (let ((dasel--version-checked nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) "/usr/bin/dasel"))
              ((symbol-function 'call-process)
               (lambda (_program &optional _infile _destination _display &rest _args)
                 (insert "dasel version 2.7.0")
                 0)))
      (should-error (dasel--check-version) :type 'user-error))))

(ert-deftest dasel-test-check-version-v1 ()
  "Signals user-error for version 1.x.x."
  (let ((dasel--version-checked nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) "/usr/bin/dasel"))
              ((symbol-function 'call-process)
               (lambda (_program &optional _infile _destination _display &rest _args)
                 (insert "dasel version 1.27.0")
                 0)))
      (should-error (dasel--check-version) :type 'user-error))))

(ert-deftest dasel-test-check-version-development ()
  "Accepts \"development\" as a valid version."
  (let ((dasel--version-checked nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) "/usr/bin/dasel"))
              ((symbol-function 'call-process)
               (lambda (_program &optional _infile _destination _display &rest _args)
                 (insert "development")
                 0)))
      (dasel--check-version)
      (should (eq t dasel--version-checked)))))

(ert-deftest dasel-test-check-version-caching ()
  "Version is only checked once per session."
  (let ((dasel--version-checked nil)
        (check-count 0))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (_cmd)
                 (cl-incf check-count)
                 "/usr/bin/dasel"))
              ((symbol-function 'call-process)
               (lambda (_program &optional _infile _destination _display &rest _args)
                 (insert "dasel version 2.8.1")
                 0)))
      (dasel--check-version)
      (dasel--check-version)
      (should (= 1 check-count)))))

;;; Output buffer tests

(ert-deftest dasel-test-get-output-buffer ()
  "Creates buffer with the configured name."
  (let ((dasel-output-buffer-name "*dasel-test-output*"))
    (unwind-protect
        (let ((buf (dasel--get-output-buffer)))
          (should (bufferp buf))
          (should (equal "*dasel-test-output*" (buffer-name buf))))
      (when-let* ((buf (get-buffer "*dasel-test-output*")))
        (kill-buffer buf)))))

(ert-deftest dasel-test-display-output ()
  "Inserts content into the output buffer and triggers font-lock-flush."
  (let ((dasel-output-buffer-name "*dasel-test-display*")
        (dasel-output-mode-alist dasel-test-safe-mode-alist)
        (font-lock-flushed nil))
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda () (setq font-lock-flushed t)))
                  ((symbol-function 'display-buffer-in-side-window)
                   (lambda (_buf _alist) nil)))
          (let ((buf (dasel--display-output "{\"key\":\"value\"}" "json")))
            (should (bufferp buf))
            (with-current-buffer buf
              (should (string-match-p "\"key\"" (buffer-string))))
            (should font-lock-flushed)))
      (when-let* ((buf (get-buffer "*dasel-test-display*")))
        (kill-buffer buf)))))

(ert-deftest dasel-test-display-error ()
  "Inserts error string with error face."
  (let ((dasel-output-buffer-name "*dasel-test-error*"))
    (unwind-protect
        (cl-letf (((symbol-function 'display-buffer-in-side-window)
                   (lambda (_buf _alist) nil)))
          (let ((buf (dasel--display-error "something went wrong")))
            (should (bufferp buf))
            (with-current-buffer buf
              (should (equal "something went wrong" (buffer-string)))
              (should (eq 'error (get-text-property (point-min) 'face))))))
      (when-let* ((buf (get-buffer "*dasel-test-error*")))
        (kill-buffer buf)))))

;;; Integration tests (with real binary)

(ert-deftest dasel-test-integration-run-json-query ()
  "Run a real dasel query on JSON data."
  (skip-unless (dasel-test-v2-available-p))
  (let ((dasel--version-checked t))
    (let ((result (dasel--run dasel-test-sample-json "json" nil "name")))
      (should (= 0 (plist-get result :exit-code)))
      (should (string-match-p "Alice" (plist-get result :output))))))

(ert-deftest dasel-test-sniff-content-nil ()
  "Returns nil when content is not recognized as any format."
  (with-temp-buffer
    (insert "12345 some random content")
    (should-not (dasel--sniff-content))))

(ert-deftest dasel-test-detect-format-sniff-fallback ()
  "`dasel--detect-format' falls back to content sniffing."
  (with-temp-buffer
    (insert "{\"key\": \"value\"}")
    (should (equal "json" (dasel--detect-format)))))

(ert-deftest dasel-test-detect-format-extension-yml ()
  "File extension .yml maps to yaml format."
  (with-temp-buffer
    (let ((buffer-file-name "/tmp/test.yml"))
      (should (equal "yaml" (dasel--detect-format))))))

(ert-deftest dasel-test-mode-for-format-yaml ()
  "YAML format returns a YAML major mode."
  (let ((mode (dasel--mode-for-format "yaml")))
    (should (memq mode '(yaml-ts-mode yaml-mode fundamental-mode)))))

(ert-deftest dasel-test-mode-for-format-toml ()
  "TOML format returns a TOML major mode."
  (let ((mode (dasel--mode-for-format "toml")))
    (should (memq mode '(toml-ts-mode toml-mode conf-toml-mode fundamental-mode)))))

(ert-deftest dasel-test-mode-for-format-csv ()
  "CSV format returns `csv-mode' or `fundamental-mode'."
  (let ((mode (dasel--mode-for-format "csv")))
    (should (memq mode '(csv-mode fundamental-mode)))))

(ert-deftest dasel-test-close-output-window ()
  "Closing output window succeeds even when no window exists."
  (let ((dasel-output-buffer-name "*dasel-test-close*"))
    (dasel--close-output-window)
    (should t)))

(ert-deftest dasel-test-close-output-window-with-buffer ()
  "Closing output window succeeds when buffer exists without window."
  (let ((dasel-output-buffer-name "*dasel-test-close2*"))
    (unwind-protect
        (progn
          (get-buffer-create "*dasel-test-close2*")
          (dasel--close-output-window)
          (should t))
      (when-let* ((buf (get-buffer "*dasel-test-close2*")))
        (kill-buffer buf)))))

(ert-deftest dasel-test-supported-formats ()
  "`dasel-supported-formats' contains all expected formats."
  (should (equal dasel-supported-formats '("json" "yaml" "toml" "xml" "csv"))))

(ert-deftest dasel-test-display-output-erase-previous ()
  "Subsequent display-output calls replace previous content."
  (let ((dasel-output-buffer-name "*dasel-test-erase*")
        (dasel-output-mode-alist dasel-test-safe-mode-alist))
    (unwind-protect
        (cl-letf (((symbol-function 'display-buffer-in-side-window)
                   (lambda (_buf _alist) nil)))
          (dasel--display-output "first" "json")
          (dasel--display-output "second" "json")
          (with-current-buffer (get-buffer "*dasel-test-erase*")
            (should (equal (buffer-string) "second"))))
      (when-let* ((buf (get-buffer "*dasel-test-erase*")))
        (kill-buffer buf)))))

(ert-deftest dasel-test-check-version-unparseable ()
  "Signals user-error for unparseable version string."
  (let ((dasel--version-checked nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) "/usr/bin/dasel"))
              ((symbol-function 'call-process)
               (lambda (_program &optional _infile _destination _display &rest _args)
                 (insert "something-without-version")
                 0)))
      (should-error (dasel--check-version) :type 'user-error))))

(provide 'dasel-test)
;;; dasel-test.el ends here
