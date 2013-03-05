;;; -*- Mode: Lisp -*-

;;; This software is in the public domain and is
;;; provided with absolutely no warranty.

(in-package #:qt-ide)
(named-readtables:in-readtable :qt)

(defvar *repl-history* nil)
(defvar *package-indicator-color* nil)
(defvar *repl-kernel* (lparallel:make-kernel 1 :name "qt-repl"))

(defun repl ()
  (let ((lparallel:*kernel* *repl-kernel*)
        (*package* *package*)
        (* *)
        (** **)
        (*** ***)
        (/ /)
        (// //)
        (/// ///)
        (+ +)
        (++ ++)
        (+++ +++)
        (- -))
    (exec-window (make-instance 'repl))))

(defun short-package-name (package)
  (let* ((name (package-name package))
         (shortest (length name)))
    (loop for nickname in (package-nicknames package)
          when (< (length nickname) shortest)
          do (setf name nickname))
    name))

(defclass repl (window)
  ((eval-channel :initform nil
                 :accessor eval-channel)
   (result-queue :initform nil
                 :accessor result-queue)
   (input :initform nil
          :accessor input)
   (current-package :initarg :current-package
                    :initform nil
                    :accessor current-package) 
   (package-indicator :initform nil
                      :accessor package-indicator)
   (scene :initform nil
          :accessor scene)
   (things-to-move :initarg :things-to-move
                   :initform nil
                   :accessor things-to-move) 
   (item-position :initform 0
                  :accessor item-position)
   (view :initform nil
         :accessor view)
   (output :initform nil
           :accessor output)
   (output-stream :initform nil
                  :accessor output-stream)
   (timer :initform nil
          :accessor timer))
  (:metaclass qt-class)
  (:qt-superclass "QDialog")
  (:slots
   ("evaluate()" evaluate)
   ("history(bool)" choose-history)
   ("insertOutput()" insert-output)
   ("insertResults()" insert-results)
   ("makeInputVisible(QRectF)" make-input-visible))
  (:signals ("insertResults()"))
  (:default-initargs :title "REPL"))
  
(defmethod initialize-instance :after ((window repl) &key)
  (let* ((scene (#_new QGraphicsScene window))
         (vbox (#_new QVBoxLayout window))
         (view (#_new QGraphicsView scene window))
         (input (make-instance 'repl-input))
         (package-indicator (#_addText scene "" *default-qfont*))
         (timer (#_new QTimer window)))
    (add-widgets vbox view)
    (#_setAlignment view (enum-or (#_Qt::AlignLeft) (#_Qt::AlignTop)))
    (#_setItemIndexMethod scene (#_QGraphicsScene::NoIndex))
    (setf (timer window) timer
          (eval-channel window) (lparallel:make-channel)
          (result-queue window) (lparallel.queue:make-queue)
          (current-package window)
          (progn (lparallel:submit-task (eval-channel window)
                                        (lambda () *package*))
                 (lparallel:receive-result (eval-channel window)))
          (input window) input
          (package-indicator window) package-indicator
          (scene window) scene
          (view window) view
          (output-stream window)
          (make-instance 'repl-output-stream
                         :repl-window window))
    (#_setDefaultTextColor package-indicator
                           (or *package-indicator-color*
                               (setf *package-indicator-color*
                                     (#_new QColor "#a020f0"))))
    (#_setDocumentMargin (#_document package-indicator) 1)
    (update-input window)
    (#_addItem scene input)
    (#_setFocus input)
    (connect input "returnPressed()"
             window "evaluate()")
    (connect input "history(bool)"
             window "history(bool)")
    (connect scene "sceneRectChanged(QRectF)"
             window "makeInputVisible(QRectF)")
    (connect window "insertResults()" window "insertResults()")
    (connect timer "timeout()" window "insertOutput()")))

(defun adjust-items-after-output (repl amount)
  (with-slots (package-indicator input
               item-position things-to-move) repl
    (loop for thing in things-to-move
          do
          (#_moveBy thing 0 amount))
    (#_moveBy input 0 amount)
    (#_moveBy package-indicator 0 amount)
    (incf item-position amount)))

(defun add-text-to-repl (repl item &key position)
  (with-slots (scene item-position) repl
    (let* ((document (#_document item))
           (height (#_height (#_size document))))
      (#_addItem scene item)
      (#_setY item (or position
                       item-position))
      (adjust-items-after-output repl height)))
  item)

;;;

(defclass text-item ()
  ()
  (:metaclass qt-class)
  (:qt-superclass "QGraphicsTextItem")
  (:override ("contextMenuEvent" context-menu-event)))

(defmethod initialize-instance :after ((widget text-item) &key (text "")
                                                               editable)
  (new-instance widget text)
  (#_setTextInteractionFlags widget (enum-or (#_Qt::TextSelectableByMouse)
                                             (#_Qt::TextSelectableByKeyboard)
                                             (if editable
                                                 (#_Qt::TextEditable)
                                                 0)))
  (unless editable
    (#_setUndoRedoEnabled (#_document widget) nil))
  (#_setDocumentMargin (#_document widget) 1)
  (#_setFont widget *default-qfont*))

(defmethod context-menu-event ((widget text-item) event)
  (let ((menu (context-menu widget)))
    (when menu
      (#_exec menu (#_screenPos event)))))

;;;

(defclass repl-input (text-item)
  ((history-index :initarg :history-index
                  :initform -1
                  :accessor history-index)
   (current-input :initarg :current-input
                  :initform nil
                  :accessor current-input))
  (:metaclass qt-class)
  (:qt-superclass "QGraphicsTextItem")
  (:override ("keyPressEvent" key-press-event)
             ("paint" graphics-item-paint))
  (:signals
   ("returnPressed()")
   ("history(bool)"))
  (:default-initargs :editable t))

(defmethod key-press-event ((widget repl-input) event)
  (let ((key (#_key event)))
    (cond ((or (= key (primitive-value (#_Qt::Key_Return)))
               (= key (primitive-value (#_Qt::Key_Enter))))
           (#_accept event)
           (emit-signal widget "returnPressed()"))
          ((= key (primitive-value (#_Qt::Key_Up)))
           (#_accept event)
           (emit-signal widget "history(bool)" t))
          ((= key (primitive-value (#_Qt::Key_Down)))
           (#_accept event)
           (emit-signal widget "history(bool)" nil))
          (t
           (setf (history-index widget) -1)
           (stop-overriding)))))

(defgeneric graphics-item-paint (item painter option widget))

(defmethod graphics-item-paint ((item repl-input) painter option widget)
  (#_setState option (enum-andc (#_state option)
                                (#_QStyle::State_Selected)
                                (#_QStyle::State_HasFocus)))
  (stop-overriding))

;;;

(defclass result-presentation (text-item)
  ((value :initarg :value
          :initform nil
          :accessor value))
  (:metaclass qt-class)
  (:slots ("inspect()" (lambda (x)
                         (inspector (value x))))))

(defmethod initialize-instance :after ((widget result-presentation)
                                       &key)
  (#_setDefaultTextColor widget (#_new QColor "#ff0000")))

(defmethod context-menu ((widget result-presentation))
  (let ((menu (#_new QMenu)))
    (add-qaction menu "Inspect" widget "inspect()")
    menu))

;;;

(defclass repl-output (text-item)
  ((cursor :initarg :cursor
           :initform nil
           :accessor cursor)
   (used :initarg :used
         :initform nil
         :accessor used)
   (place :initarg :place
          :initform nil
          :accessor place))
  (:metaclass qt-class))

(defmethod initialize-instance :after ((widget repl-output) &key)
  (setf (cursor widget)
        (#_new QTextCursor (#_document widget))))

;;;

(defun update-input (repl)
  (with-slots (input package-indicator) repl
    (#_setPlainText input "")
    (#_setPlainText package-indicator
                    (format nil "~a> "
                            (short-package-name (current-package repl))))
    (#_setX input (- (#_width (#_size (#_document package-indicator)))
                     2)) ;; margins
    (#_setVisible input t)
    (#_setVisible package-indicator t)
    (#_setFocus input)))

(defun make-input-visible (repl rect)
  (#_centerOn (view repl) (#_bottomLeft rect)))

(defun evaluate-string (repl string)
  (let* ((output-stream (output-stream repl))
         (*standard-output* output-stream)
         (*error-output* output-stream)
         ;;(*debug-io* (make-two-way-stream *debug-io* output-stream))
         (*query-io* (make-two-way-stream *query-io* output-stream)))
    (progn ;; with-graphic-debugger
      (multiple-value-list
       (eval (read-from-string string))))))

(defun adjust-history (new-input)
  (unless (equal new-input (car *repl-history*))
    (let ((stripped (string-trim #(#\Space #\Newline #\Tab #\Return)
                                 new-input)))
      (setf *repl-history*
            (cons stripped
                  (remove stripped *repl-history* :test #'equal))))))

(defun add-string-to-repl (text repl)
  (add-text-to-repl repl (make-instance 'text-item :text text)))

(defun add-result-to-repl (value repl)
  (add-text-to-repl repl (make-instance 'result-presentation
                                        :value value
                                        :text (prin1-to-string value))))

(defun concatenate-output-queue (queue)
  (with-output-to-string (str)
    (loop until (lparallel.queue:queue-empty-p queue)
          do (write-string (lparallel.queue:pop-queue queue) str))))

(defun insert-output (repl)
  (with-slots (output output-stream timer) repl
    (unless (lparallel.queue:queue-empty-p (output-queue output-stream))
      (let* ((output (output repl))
             (cursor (cursor output))
             (string (concatenate-output-queue (output-queue output-stream)))
             (height (#_height (#_size (#_document output)))))
        (#_movePosition cursor (#_QTextCursor::End))
        (#_insertText cursor string)
        (cond ((used output)
               (adjust-items-after-output repl
                                          (- (#_height (#_size (#_document output)))
                                             height)))
              (t
               (add-text-to-repl repl output :position (place output))
               (setf (used output) t)))))))

(defun insert-results (repl)
  (insert-output repl)
  (let ((results (lparallel.queue:pop-queue (result-queue repl))))
    (cond ((null results)
           (push (add-string-to-repl "; No values" repl)
                 (things-to-move repl)))
          (t
           (loop for result in results
                 do
                 (push (add-result-to-repl result repl)
                       (things-to-move repl)))))
    (update-input repl)))

(defun perform-evaluation (string repl)
  (lparallel.queue:push-queue (evaluate-string repl string)
                              (result-queue repl))
  (setf (current-package repl) *package*)
  (emit-signal repl "insertResults()"))

(defun evaluate (repl)
  (with-slots (input package-indicator item-position
               output-stream output
               eval-channel current-package
               things-to-move) repl
    (let ((string-to-eval (#_toPlainText input)))
      (#_setVisible input nil)
      (#_setVisible package-indicator nil)
      (setf things-to-move nil)
      (add-string-to-repl
       (format nil "~a> ~a"
               (short-package-name current-package) string-to-eval)
       repl)
      (when (or (null output)
                (used output))
        (setf output (make-instance 'repl-output)))
      (setf (place output) item-position)
      (adjust-history string-to-eval)
      (setf (history-index input) -1)
      (lparallel:submit-task eval-channel
                             #'perform-evaluation string-to-eval repl))))

(defun choose-history (window previous-p)
  (with-slots (input scene last-output-position view) window
    (let* ((text (#_toPlainText input))
           (current-index (history-index input))
           (next-index (min
                        (max (+ current-index
                                (if previous-p
                                    1
                                    -1))
                             -1)
                        (1- (length *repl-history*)))))
      (when (= current-index -1)
        (setf (current-input input) text))
      (setf (history-index input) next-index)
      (#_setPlainText input (if (= next-index -1)
                                (current-input input)
                                (nth next-index *repl-history*)))
      (let ((cursor (#_textCursor input)))
        (#_movePosition cursor (#_QTextCursor::End))
        (#_setTextCursor input cursor)))))
