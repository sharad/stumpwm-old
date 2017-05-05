;; Copyright (C) 2003-2008 Shawn Betts
;;
;;  This file is part of stumpwm.
;;
;; stumpwm is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; stumpwm is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this software; see the file COPYING.  If not, see
;; <http://www.gnu.org/licenses/>.

;; Commentary:
;;
;; portability wrappers. Any code that must run different code for
;; different lisps should be wrapped up in a function and put here.
;;
;; Code:

(in-package #:stumpwm)

(export '(getenv))

(define-condition not-implemented (stumpwm-error)
  () (:documentation "A function has been called that is not implemented yet."))

(defun screen-display-string (screen &optional (assign t))
  (format nil
          (if assign "DISPLAY=~a:~d.~d" "~a:~d.~d")
          (screen-host screen)
          (xlib:display-display *display*)
          (screen-id screen)))

(defun run-prog (prog &rest opts &key args output (wait t) &allow-other-keys)
  "Common interface to shell. Does not return anything useful."
  (remf opts :args)
  (remf opts :output)
  (remf opts :wait)
  (let ((env (sb-ext:posix-environ)))
    (when (current-screen)
      (setf env (cons (screen-display-string (current-screen) t)
                      (remove-if (lambda (str)
                                   (string= "DISPLAY=" str
                                            :end2 (min 8 (length str))))
                                 env))))
    (apply #'sb-ext:run-program prog args :output (if output output t)
           :error t :wait wait :environment env opts)))

(defun run-prog-collect-output (prog &rest args)
  "run a command and read its output."
  (with-output-to-string (s)
    (run-prog prog :args args :output s :wait t)))

(defun getenv (var)
  "Return the value of the environment variable."
  (sb-posix:getenv (string var)))

(defun (setf getenv) (val var)
  "Set the value of the environment variable, @var{var} to @var{val}."
  (sb-posix:putenv (format nil "~A=~A" (string var) (string val))))

(defun pathname-is-executable-p (pathname)
  "Return T if the pathname describes an executable file."
  (let ((filename (coerce (sb-ext:native-namestring pathname) 'string)))
    (and (or (pathname-name pathname)
             (pathname-type pathname))
         (sb-unix:unix-access filename sb-unix:x_ok))))

(defun probe-path (path)
  "Return the truename of a supplied path, or nil if it does not exist."
  (handler-case
      (truename
       (let ((pathname (pathname path)))
         ;; If there is neither a type nor a name, we have a directory
         ;; pathname already. Otherwise make a valid one.
         (if (and (not (pathname-name pathname))
                  (not (pathname-type pathname)))
             pathname
             (make-pathname
              :directory (append (or (pathname-directory pathname)
                                     (list :relative))
                                 (list (file-namestring pathname)))
              :name nil :type nil :defaults pathname))))
    (file-error () nil)))

(defun print-backtrace (&optional (frames 100))
  "print a backtrace of FRAMES number of frames to standard-output"
  (sb-debug:print-backtrace :count frames :stream *standard-output*))

(defun bytes-to-string (data)
  "Convert a list of bytes into a string."
  #+sbcl (handler-bind
             ((sb-impl::octet-decoding-error #'(lambda (c)
                                                 (declare (ignore c))
                                                 (invoke-restart 'use-value "?"))))
          (sb-ext:octets-to-string
           (make-array (length data) :element-type '(unsigned-byte 8) :initial-contents data)))
  #+clisp
  (ext:convert-string-from-bytes
   (make-array (length data) :element-type '(unsigned-byte 8) :initial-contents data)
   custom:*terminal-encoding*)
  #+lispworks
  (ef:decode-external-string
   (make-array (length data) :element-type '(unsigned-byte 8) :initial-contents data)
   :ascii)
  #-(or sbcl clisp lispworks)
  (map 'string #'code-char data))

(defun string-to-bytes (string)
  "Convert a string to a vector of octets."
  #+sbcl
  (sb-ext:string-to-octets string)
  #+clisp
  (ext:convert-string-to-bytes string custom:*terminal-encoding*)
  #+lispworks
  (ef:encode-lisp-string string :ascii)
  #-(or sbcl clisp lispworks)
  (map 'list #'char-code string))

(defun utf8-to-string (octets)
  "Convert the list of octets to a string."
  (let ((octets (coerce octets '(vector (unsigned-byte 8)))))
    #+ccl (ccl:decode-string-from-octets octets :external-format :utf-8)
    #+clisp (ext:convert-string-from-bytes octets charset:utf-8)
    #+sbcl (handler-bind
               ((sb-impl::octet-decoding-error #'(lambda (c)
                                                   (declare (ignore c))
                                                   (invoke-restart 'use-value "?"))))
             (sb-ext:octets-to-string octets :external-format :utf-8))
    #+lispworks
    (ef:decode-external-string
     (make-array (length octets) :element-type '(unsigned-byte 8) :initial-contents octets)
     :utf-8)
    #-(or ccl clisp sbcl lispworks)
    (map 'string #'code-char octets)))

(defun string-to-utf8 (string)
  "Convert the string to a vector of octets."
  #+ccl (ccl:encode-string-to-octets string :external-format :utf-8)
  #+clisp (ext:convert-string-to-bytes string charset:utf-8)
  #+sbcl (sb-ext:string-to-octets
          string
          :external-format :utf-8)
  #+lispworks
  (ef:encode-lisp-string string :utf-8)
  #-(or ccl clisp sbcl lispworks)
  (map 'list #'char-code string))

(defun directory-no-deref (pathspec)
  "Call directory without dereferencing symlinks in the results"
  #+(or cmu scl) (directory pathspec :truenamep nil)
  #+clisp (mapcar #'car (directory pathspec :full t))
  #+lispworks (directory pathspec :link-transparency nil)
  #+openmcl (directory pathspec :follow-links nil)
  #+sbcl (directory pathspec :resolve-symlinks nil)
  #-(or clisp cmu lispworks openmcl sbcl scl) (directory pathspec))

;;; CLISP does not include features to distinguish different Unix
;;; flavours (at least until version 2.46). Until this is fixed, use a
;;; hack to determine them.

#+ (and clisp (not (or linux freebsd)))
(eval-when (eval load compile)
  (let ((osname (posix:uname-sysname (posix:uname))))
    (cond
      ((string= osname "Linux") (pushnew :linux *features*))
      ((string= osname "FreeBSD") (pushnew :freebsd *features*))
      (t (warn "Your operating system is not recognized.")))))


;;; On GNU/Linux some contribs use sysfs to figure out useful info for
;;; the user. SBCL upto at least 1.0.16 (but probably much later) has
;;; a problem handling files in sysfs caused by SBCL's slightly
;;; unusual handling of files in general and Linux' sysfs violating
;;; POSIX. When this situation is resolved, this function may be removed.
#+ linux
(export '(read-line-from-sysfs))

#+ linux
(defun read-line-from-sysfs (stream &optional (blocksize 80))
  "READ-LINE, but with a workaround for a known SBCL/Linux bug
regarding files in sysfs. Data is read in chunks of BLOCKSIZE bytes."
  #- sbcl
  (declare (ignore blocksize))
  #- sbcl
  (read-line stream)
  #+ sbcl
  (let ((buf (make-array blocksize
			 :element-type '(unsigned-byte 8)
			 :initial-element 0))
	(fd (sb-sys:fd-stream-fd stream))
	(string-filled 0)
	(string (make-string blocksize))
	bytes-read
	pos
	(stringlen blocksize))

    (loop
       ;; Read in the raw bytes
       (setf bytes-read
	     (sb-unix:unix-read fd (sb-sys:vector-sap buf) blocksize))

       ;; Why does SBCL return NIL when an error occurs?
       (when (or (null bytes-read)
                 (< bytes-read 0))
         (error "UNIX-READ failed."))

       ;; This is # bytes both read and in the correct line.
       (setf pos (or (position (char-code #\Newline) buf) bytes-read))

       ;; Resize the string if necessary.
       (when (> (+ pos string-filled) stringlen)
	 (setf stringlen (max (+ pos string-filled)
			      (* 2 stringlen)))
	 (let ((new (make-string stringlen)))
	   (replace new string)
	   (setq string new)))

       ;; Translate read bytes to string
       (setf (subseq string string-filled)
	     (sb-ext:octets-to-string (subseq buf 0 pos)))

       (incf string-filled pos)

       (if (< pos blocksize)
	   (return (subseq string 0 string-filled))))))

(defun execv (program &rest arguments)
  (declare (ignorable program arguments))
  ;; FIXME: seems like there should be a way to do this in sbcl the way it's done in clisp. -sabetts
  #+sbcl
  (sb-alien:with-alien ((prg sb-alien:c-string program)
                        (argv (array sb-alien:c-string 256)))
    (loop
       for i in arguments
       for j below 255
       do (setf (sb-alien:deref argv j) i))
    (setf (sb-alien:deref argv (length arguments)) nil)
    (sb-alien:alien-funcall (sb-alien:extern-alien "execv" (function sb-alien:int sb-alien:c-string (* sb-alien:c-string)))
                            prg (sb-alien:cast argv (* sb-alien:c-string))))
  ;; FIXME: Using unexported and undocumented functionality isn't nice
  #+clisp
  (funcall (ffi::find-foreign-function "execv"
                                       (ffi:parse-c-type '(ffi:c-function
                                                           (:arguments
                                                            (prg ffi:c-string)
                                                            (args (ffi:c-array-ptr ffi:c-string))
                                                            )
                                                           (:return-type ffi:int)))
                                       nil nil nil nil)
           program
           (coerce arguments 'array))
  #-(or sbcl clisp)
  (error "Unimplemented"))

(defun open-pipe (&key (element-type '(unsigned-byte 8)))
  "Create a pipe and return two streams. The first value is the input
stream, and the second value is the output stream."
  (multiple-value-bind (in-fd out-fd)
      (sb-posix:pipe)
    (let ((in-stream (sb-sys:make-fd-stream in-fd :input t :element-type element-type))
          (out-stream (sb-sys:make-fd-stream out-fd :output t :element-type element-type)))
      (values in-stream out-stream))))

;;; EOF
