;;; el-get --- Manage the external elisp bits and pieces you depend upon
;;
;; Copyright (C) 2010-2011 Dimitri Fontaine
;;
;; Author: Dimitri Fontaine <dim@tapoueh.org>
;; URL: http://www.emacswiki.org/emacs/el-get
;; GIT: https://github.com/dimitri/el-get
;; Licence: WTFPL, grab your copy here: http://sam.zoy.org/wtfpl/
;;
;; This file is NOT part of GNU Emacs.
;;
;; Install
;;     Please see the README.asciidoc file from the same distribution

;;
;; package status --- a plist saved on a file, using symbols
;;
;; it should be possible to use strings instead, but in my tests it failed
;; miserably.
;;

(require 'cl)
(require 'pp)
(require 'el-get-core)

(defun el-get-package-name (package-symbol)
  "Returns a package name as a string."
  (cond ((keywordp package-symbol)
         (substring (symbol-name package-symbol) 1))
        ((symbolp package-symbol)
         (symbol-name package-symbol))
        ((stringp package-symbol)
         package-symbol)
        (t (error "Unknown package: %s"))))

(defun el-get-package-symbol (package)
  "Returns a package name as a non-keyword symbol"
  (cond ((keywordp package)
         (intern (substring (symbol-name package) 1)))
        ((symbolp package)
         package)
        ((stringp package) (intern package))
        (t (error "Unknown package: %s"))))

(defun el-get-package-keyword (package-name)
  "Returns a package name as a keyword :package."
  (if (keywordp package-name)
      package-name
    (intern (format ":%s" package-name))))

(defun el-get-pp-status-alist-to-string (object)
  (with-temp-buffer
    (lisp-mode-variables nil)
    (set-syntax-table emacs-lisp-mode-syntax-table)
    (let ((print-escape-newlines pp-escape-newlines)
          (print-quoted t))
      (prin1 object (current-buffer)))
    (goto-char (point-min))
    ;; The `(ignore-errors (while t ...))' pattern is guaranteed not
    ;; to loop infinitely because the movement commands `down-list',
    ;; `up-list', and `forward-sexp' will keep moving forward until
    ;; the hit the end of the status list (outer loop) or end of the
    ;; recipe (inner loop), at which point they will throw errors and
    ;; break out of the loop.
    (ignore-errors
      ;; Descend into status list
      (down-list 1)
      (while t
        ;; Descend into recipe
        (down-list 2)
        ;; Put a newline after each property value (except the last one)
        (ignore-errors
          (while t
            ;; We want to move forward by 2 sexps, but we also want to
            ;; make sure that there's another sexp after point before
            ;; inserting a newline.
            (forward-sexp 3)
            (backward-sexp 1)
            (delete-region (point) (progn (skip-chars-backward " \t\n") (point)))
            (insert ?\n)))
        ;; Exit from status entry for this package
        (up-list 2)))
    (pp-buffer)
    (goto-char (point-min))
    ;; Make sure we didn't change the value. That would be bad.
    (assert (equal object (read (current-buffer))) nil
            "Pretty-printing status changes its value. Your pretty-printing function is messed up.")
    (buffer-string)))

(defun el-get-save-package-status (package status)
  "Save given package status"
  (let* ((package (el-get-as-symbol package))
         (recipe (el-get-package-def package))
         (package-status-alist
          (assq-delete-all package (el-get-read-status-file)))
         (new-package-status-alist
          (sort (append package-status-alist
                        (list            ; alist of (PACKAGE . PROPERTIES-LIST)
                         (cons package (list 'status status 'recipe recipe))))
                (lambda (p1 p2)
                  (string< (el-get-as-string (car p1))
                           (el-get-as-string (car p2)))))))
    (with-temp-file el-get-status-file
      (insert (el-get-pp-status-alist-to-string new-package-status-alist)))
    ;; Return the new alist
    new-package-status-alist))

(defun el-get-read-status-file ()
  "read `el-get-status-file' and return an alist of plist like:
   (PACKAGE . (status \"status\" recipe (:name ...)))"
  (let ((ps
         (when (file-exists-p el-get-status-file)
           (car (with-temp-buffer
                  (insert-file-contents-literally el-get-status-file)
                  (read-from-string (buffer-string)))))))
    (if (consp (car ps))         ; check for an alist, new format
        ps
      ;; convert to the new format, fetching recipes as we go
      (loop for (p s) on ps by 'cddr
            for x = (el-get-package-symbol p)
            when x
            collect (cons x (list 'status s
                                  'recipe (el-get-package-def x)))))))

(defun el-get-package-status-alist (&optional package-status-alist)
  "return an alist of (PACKAGE . STATUS)"
  (loop for (p . prop) in (or package-status-alist
                              (el-get-read-status-file))
        collect (cons p (plist-get prop 'status))))

(defun el-get-package-status-recipes (&optional package-status-alist)
  "return the list of recipes stored in the status file"
  (loop for (p . prop) in (or package-status-alist
                              (el-get-read-status-file))
        collect (plist-get prop 'recipe)))

(defun el-get-read-package-status (package &optional package-status-alist)
  "return current status for PACKAGE"
  (let ((p-alist (or package-status-alist (el-get-read-status-file))))
    (plist-get (cdr (assq (el-get-as-symbol package) p-alist)) 'status)))

(define-obsolete-function-alias 'el-get-package-status 'el-get-read-package-status)

(defun el-get-read-package-status-recipe (package &optional package-status-alist)
  "return current status for PACKAGE"
  (let ((p-alist (or package-status-alist (el-get-read-status-file))))
    (plist-get (cdr (assq (el-get-as-symbol package) p-alist)) 'recipe)))

(defun el-get-filter-package-alist-with-status (package-status-alist &rest statuses)
  "Return package names that are currently in given status"
  (loop for (p . prop) in package-status-alist
        for s = (plist-get prop 'status)
	when (member s statuses)
        collect (el-get-as-string p)))

(defun el-get-list-package-names-with-status (&rest statuses)
  "Return package names that are currently in given status"
  (apply #'el-get-filter-package-alist-with-status
         (el-get-read-status-file)
         statuses))

(defun el-get-read-package-with-status (action &rest statuses)
  "Read a package name in given status"
  (completing-read (format "%s package: " action)
                   (apply 'el-get-list-package-names-with-status statuses)))

(defun el-get-count-package-with-status (&rest statuses)
  "Return how many packages are currently in given status"
  (length (apply #'el-get-list-package-names-with-status statuses)))

(defun el-get-count-packages-with-status (packages &rest statuses)
  "Return how many packages are currently in given status in PACKAGES"
  (length (intersection
           (mapcar #'el-get-as-symbol (apply #'el-get-list-package-names-with-status statuses))
           (mapcar #'el-get-as-symbol packages))))

(defun el-get-extra-packages (&rest packages)
  "Return installed or required packages that are not in given package list"
  (let ((packages
	 ;; &rest could contain both symbols and lists
	 (loop for p in packages
	       when (listp p) append (mapcar 'el-get-as-symbol p)
	       else collect (el-get-as-symbol p))))
    (when packages
      (loop for (p . prop) in (el-get-read-status-file)
            for s = (plist-get prop 'status)
            for x = (el-get-package-symbol p)
            unless (member x packages)
            unless (equal s "removed")
            collect (list x s)))))

(defmacro el-get-with-status-sources (&rest body)
  "Evaluate BODY with `el-get-sources' bound to recipes from status file."
  `(let ((el-get-sources (el-get-package-status-recipes)))
     (progn ,@body)))
(put 'el-get-with-status-recipes 'lisp-indent-function
     (get 'progn 'lisp-indent-function))

(provide 'el-get-status)
