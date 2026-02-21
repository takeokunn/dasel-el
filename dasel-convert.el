;;; dasel-convert.el --- Format conversion commands for dasel -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>
;; Maintainer: takeokunn <bararararatty@gmail.com>
;; URL: https://github.com/takeokunn/dasel-el
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, data

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

;; Format conversion commands for dasel.  Provides an interactive
;; `dasel-convert' command that converts buffer or region content
;; between structured data formats (JSON, YAML, TOML, XML, CSV),
;; plus convenience commands for common conversion pairs.

;;; Code:

(require 'dasel)

(defcustom dasel-convert-formats dasel-supported-formats
  "Available target formats for conversion."
  :type '(repeat string)
  :group 'dasel)

;;;###autoload
(defun dasel-convert (target-format)
  "Convert buffer or region to TARGET-FORMAT using dasel.
When called interactively, prompts for the target format.
If region is active, convert only the region; otherwise convert
the entire buffer."
  (interactive
   (let ((input-format (dasel--detect-format)))
     (unless input-format
       (user-error "Cannot detect input format; set `dasel-buffer-format'"))
     (list (completing-read
            "Convert to: "
            (remove input-format dasel-convert-formats)
            nil t))))
  (let* ((input-format (dasel--detect-format)))
    (unless input-format
      (user-error "Cannot detect input format; set `dasel-buffer-format'"))
    (let* ((beg (if (use-region-p) (region-beginning) (point-min)))
           (end (if (use-region-p) (region-end) (point-max)))
           (content (buffer-substring-no-properties beg end))
           (result (dasel--run content input-format target-format)))
      (if (zerop (plist-get result :exit-code))
          (progn
            (undo-boundary)
            (atomic-change-group
              (delete-region beg end)
              (goto-char beg)
              (insert (plist-get result :output)))
            (funcall (dasel--mode-for-format target-format))
            (setq dasel-buffer-format target-format))
        (user-error "%s" (plist-get result :error))))))

(defmacro dasel-convert--define (from to)
  "Define a convenience command `dasel-convert-FROM-to-TO'.
FROM and TO are unquoted symbols naming dasel format strings."
  (let ((fn-name (intern (format "dasel-convert-%s-to-%s" from to)))
        (from-str (symbol-name from))
        (to-str (symbol-name to)))
    `(defun ,fn-name ()
         ,(format "Convert buffer or region from %s to %s." from-str to-str)
         (interactive)
         (let* ((beg (if (use-region-p) (region-beginning) (point-min)))
                (end (if (use-region-p) (region-end) (point-max)))
                (content (buffer-substring-no-properties beg end))
                (result (dasel--run content ,from-str ,to-str)))
           (if (zerop (plist-get result :exit-code))
               (progn
                 (undo-boundary)
                 (atomic-change-group
                   (delete-region beg end)
                   (goto-char beg)
                   (insert (plist-get result :output)))
                 (funcall (dasel--mode-for-format ,to-str))
                 (setq dasel-buffer-format ,to-str))
             (user-error "%s" (plist-get result :error)))))))

;;;###autoload (autoload 'dasel-convert-json-to-yaml "dasel-convert" nil t)
;;;###autoload (autoload 'dasel-convert-yaml-to-json "dasel-convert" nil t)
;;;###autoload (autoload 'dasel-convert-json-to-toml "dasel-convert" nil t)
;;;###autoload (autoload 'dasel-convert-toml-to-json "dasel-convert" nil t)
;;;###autoload (autoload 'dasel-convert-json-to-xml "dasel-convert" nil t)
;;;###autoload (autoload 'dasel-convert-xml-to-json "dasel-convert" nil t)
;;;###autoload (autoload 'dasel-convert-yaml-to-toml "dasel-convert" nil t)
;;;###autoload (autoload 'dasel-convert-toml-to-yaml "dasel-convert" nil t)
(dasel-convert--define json yaml)
(dasel-convert--define yaml json)
(dasel-convert--define json toml)
(dasel-convert--define toml json)
(dasel-convert--define json xml)
(dasel-convert--define xml json)
(dasel-convert--define yaml toml)
(dasel-convert--define toml yaml)

(provide 'dasel-convert)
;;; dasel-convert.el ends here
