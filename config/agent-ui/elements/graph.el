;;; $DOOMDIR/config/agent-ui/elements/graph.el -*- lexical-binding: t; -*-
;; Agent UI's graph: nodes and edges. Loaded from config/agent-ui/elements.el.
;;
;; NODES (names, or {"id", "label", "status"}) and EDGES ([from, to], or
;; {"from", "to", "label"}); a node only an edge names is one too. Laid out
;; by itself (no Graphviz): in layers by the longest path to each node (a
;; cycle's edge back ignored for that), each layer's nodes ordered by their
;; parents' places. In the GUI, an SVG: boxes, curved arrows, left to right
;; (or down); shrunk to the pane's width. As text, each node's arrows, layer
;; by layer. STATUS ok, error, warning, active colours a node.
;;
;;   lexer   ─▶ parser
;;   parser  ─▶ checker, codegen
;;   checker ─▶ codegen

(require 'cl-lib)
(require 'subr-x)
(require 'svg)

(defconst agent-ui-graph--statuses
  '((none nil) (ok agent-ui-success) (error agent-ui-error) (warning agent-ui-warning) (active agent-ui-accent))
  "Each status: its face.")

(defun agent-ui-graph--check (props)
  (let* ((nodes (cl-loop for n in (plist-get props :nodes)
                         for i from 1
                         collect (cond
                                  ((and (stringp n) (not (string-blank-p n))) (list :id n :label n :status 'none))
                                  ((and (agent-ui--plist-p n) (stringp (plist-get n :id)))
                                   (cl-loop for (k _) on n by #'cddr
                                            unless (memq k '(:id :label :status))
                                            do (agent-ui--fail "graph: node %d has %s: a node has id, label, status"
                                                               i (agent-ui--show-value (substring (symbol-name k) 1))))
                                   (let ((status (let ((s (plist-get n :status))) (if (stringp s) (intern-soft s) (or s 'none)))))
                                     (unless (assq status agent-ui-graph--statuses)
                                       (agent-ui--fail "graph: node %d's status is ok, error, warning, active or none" i))
                                     (list :id (plist-get n :id) :label (or (plist-get n :label) (plist-get n :id)) :status status)))
                                  (t (agent-ui--fail "graph: node %d must be a name, or {\"id\": ..., \"label\": ...}" i)))))
         (edges (cl-loop for e in (plist-get props :edges)
                         for i from 1
                         collect (cond
                                  ((and (listp e) (not (agent-ui--plist-p e)) (= (length e) 2) (cl-every #'stringp e))
                                   (list :from (car e) :to (cadr e)))
                                  ((and (agent-ui--plist-p e) (stringp (plist-get e :from)) (stringp (plist-get e :to)))
                                   (list :from (plist-get e :from) :to (plist-get e :to) :label (plist-get e :label)))
                                  (t (agent-ui--fail "graph: edge %d must be [from, to], or {\"from\", \"to\", \"label\"}" i))))))
    ;; Nodes only edges name.
    (dolist (e edges)
      (dolist (id (list (plist-get e :from) (plist-get e :to)))
        (unless (cl-find id nodes :key (lambda (n) (plist-get n :id)) :test #'equal)
          (setq nodes (append nodes (list (list :id id :label id :status 'none)))))))
    (when (> (length nodes) agent-ui-max-rows)
      (agent-ui--fail "graph: at most %d nodes" agent-ui-max-rows))
    (plist-put (plist-put props :nodes nodes) :edges edges)))

(defun agent-ui-graph-layout (nodes edges)
  "NODES' layers: a list of lists of node ids, the first the nodes nothing
points to; by the longest path to each, a cycle's edge back left out;
each layer ordered by its nodes' parents' places."
  (let* ((ids (mapcar (lambda (n) (plist-get n :id)) nodes))
         (out (make-hash-table :test #'equal))
         (state (make-hash-table :test #'equal))
         (dag nil))
    (dolist (e edges) (push (plist-get e :to) (gethash (plist-get e :from) out)))
    ;; Edges back (to a node being visited) left out: what's left has no cycle.
    (cl-labels ((visit (id)
                  (puthash id 'visiting state)
                  (dolist (to (reverse (gethash id out)))
                    (pcase (gethash to state)
                      ('visiting)
                      ((or 'done (pred null))
                       (push (cons id to) dag)
                       (unless (gethash to state) (visit to)))))
                  (puthash id 'done state)))
      (dolist (id ids) (unless (gethash id state) (visit id))))
    (let ((layer (make-hash-table :test #'equal))
          (changed t))
      (dolist (id ids) (puthash id 0 layer))
      ;; Longest path: relax until nothing moves (no cycle left: it ends).
      (while changed
        (setq changed nil)
        (dolist (edge dag)
          (when (<= (gethash (cdr edge) layer) (gethash (car edge) layer))
            (puthash (cdr edge) (1+ (gethash (car edge) layer)) layer)
            (setq changed t))))
      (let* ((depth (1+ (apply #'max 0 (hash-table-values layer))))
             (layers (cl-loop for d below depth
                              collect (seq-filter (lambda (id) (= (gethash id layer) d)) ids)))
             (place (make-hash-table :test #'equal)))
        (cl-loop for l in layers
                 collect (let ((ordered
                                (if (null (hash-table-keys place)) l
                                  ;; By the mean place of the nodes pointing to it.
                                  (cl-stable-sort
                                   (copy-sequence l) #'<
                                   :key (lambda (id)
                                          (let ((ps (delq nil (mapcar (lambda (e) (and (equal (cdr e) id) (gethash (car e) place)))
                                                                      dag))))
                                            (if ps (/ (float (apply #'+ ps)) (length ps)) 1e9)))))))
                           (cl-loop for id in ordered for i from 0 do (puthash id i place))
                           ordered))))))

(defun agent-ui-graph--node (nodes id)
  (cl-find id nodes :key (lambda (n) (plist-get n :id)) :test #'equal))

(defun agent-ui-graph--text (props ctx)
  (let* ((nodes (plist-get props :nodes))
         (edges (plist-get props :edges))
         (width (plist-get ctx :width)))
    (if (null nodes)
        (propertize "no nodes" 'face 'agent-ui-muted)
      (let* ((order (apply #'append (agent-ui-graph-layout nodes edges)))
             (name-width (min (apply #'max (mapcar (lambda (n) (string-width (plist-get n :label))) nodes)) (/ width 3))))
        (mapconcat
         (lambda (id)
           (let* ((node (agent-ui-graph--node nodes id))
                  (face (cadr (assq (plist-get node :status) agent-ui-graph--statuses)))
                  (targets (mapcar (lambda (e)
                                     (let ((to (agent-ui-graph--node nodes (plist-get e :to))))
                                       (concat (propertize (plist-get to :label)
                                                           'face (cadr (assq (plist-get to :status) agent-ui-graph--statuses)))
                                               (if (plist-get e :label)
                                                   (propertize (format " (%s)" (plist-get e :label)) 'face 'agent-ui-muted)
                                                 ""))))
                                   (seq-filter (lambda (e) (equal (plist-get e :from) id)) edges)))
                  ;; Padded only before its arrows: no spaces at a line's end.
                  (name (if targets (agent-ui-pad (plist-get node :label) name-width) (plist-get node :label))))
             (agent-ui-truncate
              (concat (if face (propertize name 'face face) name)
                      (if targets (concat (propertize " ─▶ " 'face 'agent-ui-muted) (string-join targets ", ")) ""))
              width)))
         order "\n")))))

(defun agent-ui-graph--gui (props ctx)
  (let ((nodes (plist-get props :nodes))
        (edges (plist-get props :edges)))
    (if (null nodes)
        (agent-ui-graph--text props ctx)
      (let* ((cw (plist-get ctx :char-width)) (lh (plist-get ctx :line-height))
             ;; The check makes it a symbol (compared with "down", never true).
             (down (eq (plist-get props :direction) 'down))
             (layers (agent-ui-graph-layout nodes edges))
             (box-w (lambda (id) (* cw (+ 2 (string-width (plist-get (agent-ui-graph--node nodes id) :label))))))
             (box-h (* 2 lh))
             (gap-a (* 6 cw)) (gap-b (round (* 0.8 lh)))
             (where (make-hash-table :test #'equal))
             (depth (make-hash-table :test #'equal))
             (extents nil) (gaps nil)
             (along 0) (across-max 0))
        (cl-loop for layer in layers for d from 0 do (dolist (id layer) (puthash id d depth)))
        ;; Each layer a column (or a row, down); its nodes stacked across it.
        ;; Its extent along noted: the corridors between layers hold no box.
        (dolist (layer layers)
          (let ((size (if down box-h (apply #'max (mapcar box-w layer))))
                (across 0))
            (dolist (id layer)
              (let ((w (funcall box-w id)))
                (puthash id (if down (list across along w box-h) (list along across w box-h)) where)
                (setq across (+ across (if down w box-h) (if down gap-a gap-b)))))
            ;; The corridor after it as wide as its widest label from it (to
            ;; the next layer, or a loop; ~0.5 of a line a character) and 2
            ;; columns: 6 columns hid a longer label under the boxes.
            (let ((gap (if down (* 2 gap-b)
                         (max gap-a
                              (+ (* 2 cw)
                                 (apply #'max 0
                                        (mapcar (lambda (e)
                                                  (let ((d (gethash (plist-get e :from) depth)))
                                                    (if (and (plist-get e :label) (member (plist-get e :from) layer)
                                                             (memq (gethash (plist-get e :to) depth) (list d (1+ d))))
                                                        (* 0.5 lh (string-width (plist-get e :label)))
                                                      0)))
                                                edges)))))))
              (push (cons along (+ along size)) extents)
              (push gap gaps)
              (setq across-max (max across-max across)
                    along (+ along size gap)))))
        (setq extents (nreverse extents) gaps (nreverse gaps))
        (let* ((skip-p (lambda (e) (> (- (gethash (plist-get e :to) depth) (gethash (plist-get e :from) depth)) 1)))
               ;; Back (a cycle's edge): to its own layer or an earlier one.
               (back-p (lambda (e) (and (not (equal (plist-get e :from) (plist-get e :to)))
                                        (<= (gethash (plist-get e :to) depth) (gethash (plist-get e :from) depth)))))
               (long (seq-some (lambda (e) (or (funcall skip-p e) (funcall back-p e))) edges))
               ;; Lanes beside the stacks (above and below the rows; left and
               ;; right of the columns, down), for edges skipping a layer or
               ;; going back.
               ;; (A line more for labels on them.)
               (arc (if long
                        (+ (round (* 0.9 box-h))
                           (if (seq-some (lambda (e) (and (plist-get e :label)
                                                          (or (funcall skip-p e) (funcall back-p e))))
                                         edges)
                               lh 0))
                      0))
               ;; A corridor before the first layer, for edges going back to it.
               (lead (if (seq-some back-p edges) (if down (* 2 gap-b) gap-a) 0))
               (natural-across (+ across-max (* 2 arc)))
               (natural-w (if down natural-across (+ lead along)))
               (natural-h (if down (+ lead along) natural-across))
               (pane (* cw (plist-get ctx :width)))
               (scale (min 1.0 (/ (float pane) (max 1 natural-w))))
               (svg (svg-create (round (* scale natural-w)) (round (* scale natural-h))
                                :viewBox (format "0 0 %d %d" natural-w natural-h)))
               (fg (agent-ui-chart--color 'default)) (muted (agent-ui-chart--color 'agent-ui-muted))
               (fill (agent-ui-progress--blend (or (face-background 'default nil t) "black") fg 0.07))
               ;; Edges' labels, drawn last, over everything (under the boxes,
               ;; a label wider than its corridor was hidden).
               (labels nil))
          (svg--append svg (dom-node 'defs nil
                                     (dom-node 'marker '((id . "arrow") (viewBox . "0 0 10 10") (refX . "10") (refY . "5")
                                                         (markerWidth . "7") (markerHeight . "7") (orient . "auto"))
                                               (dom-node 'path `((d . "M0,0 L10,5 L0,10 z") (fill . ,muted))))))
          ;; The first lane's room, and the corridor before the first layer:
          ;; everything moved past them.
          (maphash (lambda (id box)
                     (puthash id (if down (list (+ (nth 0 box) arc) (+ (nth 1 box) lead) (nth 2 box) (nth 3 box))
                                   (list (+ (nth 0 box) lead) (+ (nth 1 box) arc) (nth 2 box) (nth 3 box)))
                              where))
                   where)
          (setq extents (mapcar (lambda (x) (cons (+ (car x) lead) (+ (cdr x) lead))) extents))
          (cl-labels ((box (id) (gethash id where))
                      ;; A box's start and end along, its middle across.
                      (a-start (id) (if down (nth 1 (box id)) (nth 0 (box id))))
                      (a-end (id) (+ (a-start id) (if down (nth 3 (box id)) (nth 2 (box id)))))
                      (c-mid (id) (if down (+ (nth 0 (box id)) (/ (nth 2 (box id)) 2.0))
                                    (+ (nth 1 (box id)) (/ (nth 3 (box id)) 2.0))))
                      ;; The middle of the corridor after layer D (past the
                      ;; last, its trailing gap's).
                      (after (d) (if (< d 0)
                                     (/ lead 2.0)
                                   (let ((this (nth d extents)) (next (nth (1+ d) extents)))
                                     (/ (+ (cdr this) (if next (car next) (+ (cdr this) (nth d gaps)))) 2.0))))
                      ;; A point at ALONG, ACROSS on the screen.
                      (pt (a c) (if down (format "%.1f,%.1f" c a) (format "%.1f,%.1f" a c))))
            (let ((routed -1))
             (dolist (e edges)
              (let* ((from (plist-get e :from)) (to (plist-get e :to))
                     (skip (or (funcall skip-p e) (funcall back-p e)))
                     ;; Each routed edge its own track, a few pixels from the
                     ;; others' (on one line, two read as one).
                     (track (if skip (mod (cl-incf routed) 4) 0))
                     ;; Where its label goes: (X Y ANCHOR), set below for
                     ;; a loop or a routed edge (at the chord's middle, it sat
                     ;; on a box the edge goes round).
                     (label-at nil))
                (pcase-let ((`(,x1 ,y1 ,w1 ,h1) (box from))
                            (`(,x2 ,y2 ,w2 ,h2) (box to)))
                  (let* ((sx (if down (+ x1 (/ w1 2.0)) (+ x1 w1))) (sy (if down (+ y1 h1) (+ y1 (/ h1 2.0))))
                         (tx (if down (+ x2 (/ w2 2.0)) x2)) (ty (if down y2 (+ y2 (/ h2 2.0))))
                         (back (if down (<= ty sy) (<= tx sx)))
                         (bend (if back 60 (* 0.5 (if down (- ty sy) (- tx sx)))))
                         (d (cond
                             ((equal from to)
                              ;; A loop out into the corridor after its box,
                              ;; back into it (it was a line under the box).
                              (let* ((c (c-mid from)) (end (a-end from))
                                     (size (if down (nth 2 (box from)) (nth 3 (box from))))
                                     (q (* 0.25 size)) (o (* 0.35 size))
                                     (reach (+ end (* 1.3 (- (after (gethash from depth)) end)))))
                                (setq label-at (if down
                                                   (list (+ c q o 3) (+ end (* 0.75 (- reach end))) "start")
                                                 (list (+ end (* 0.75 (- reach end)) 3) (+ c 4) "start")))
                                (format "M%s C%s %s %s" (pt end (- c q)) (pt reach (- c q o)) (pt reach (+ c q o)) (pt end (+ c q)))))
                             (skip
                              ;; Through the corridors and a lane, never a box:
                              ;; out into the corridor after its layer, to the
                              ;; lane on its side, along it, down the corridor
                              ;; before the target's, into it.
                              (let* ((c1 (c-mid from))
                                     ;; Into its target beside the middle (an
                                     ;; edge from the layer before comes there).
                                     (c2 (+ (c-mid to) (nth track '(-6 6 -10 10))))
                                     (lane (if (< (/ (+ c1 c2) 2) (/ natural-across 2.0))
                                               (* arc (+ 0.2 (* 0.18 track)))
                                             (- natural-across (* arc (+ 0.2 (* 0.18 track))))))
                                     (k1 (+ (after (gethash from depth)) (nth track '(-8 8 -3 3))))
                                     (k2 (+ (after (1- (gethash to depth))) (nth track '(-8 8 -3 3))))
                                     (first-lane (< lane (/ natural-across 2.0))))
                                ;; Its label on its lane's run, beside the line
                                ;; (toward the boxes on the first lane, away on
                                ;; the other), where no box is.
                                (setq label-at
                                      (if down
                                          (list (if first-lane (+ lane 3) (- lane 3)) (/ (+ k1 k2) 2.0)
                                                (if first-lane "start" "end"))
                                        (list (/ (+ k1 k2) 2.0) (if first-lane (+ lane 11) (- lane 3)) "middle")))
                                (format "M%s L%s L%s L%s L%s L%s"
                                        (pt (a-end from) c1) (pt k1 c1) (pt k1 lane)
                                        (pt k2 lane) (pt k2 c2) (pt (a-start to) c2))))
                             (down
                              (format "M%.1f,%.1f C%.1f,%.1f %.1f,%.1f %.1f,%.1f" sx sy sx (+ sy bend) tx (- ty bend) tx ty))
                             (t
                              (format "M%.1f,%.1f C%.1f,%.1f %.1f,%.1f %.1f,%.1f" sx sy (+ sx bend) sy (- tx bend) ty tx ty)))))
                    (svg--append svg (dom-node 'path `((d . ,d) (fill . "none") (stroke . ,muted) (stroke-width . "1.5")
                                                       (stroke-linejoin . "round") (marker-end . "url(#arrow)"))))
                    (when (plist-get e :label)
                      (push (append (or label-at (list (/ (+ sx tx) 2) (- (/ (+ sy ty) 2) 4) "middle"))
                                    (list (plist-get e :label)))
                            labels))))))))
          (dolist (node nodes)
            (pcase-let ((`(,x ,y ,w ,h) (gethash (plist-get node :id) where))
                        (face (cadr (assq (plist-get node :status) agent-ui-graph--statuses))))
              (svg-rectangle svg x y w h :rx 6 :fill fill
                             :stroke (if face (agent-ui-chart--color face) muted) :stroke-width (if face 2 1))
              (agent-ui-chart--svg-text svg ctx (plist-get node :label) (+ x (/ w 2.0)) (+ y (* 0.62 h))
                                        :fill (if face (agent-ui-chart--color face) fg) :text-anchor "middle")))
          (pcase-dolist (`(,x ,y ,anchor ,text) (nreverse labels))
            (agent-ui-chart--svg-text svg ctx text x y :fill muted :text-anchor anchor))
          (agent-ui-chart--image svg))))))

(agent-ui-define graph
  "A graph: NODES (names, or {\"id\", \"label\", \"status\"}) and EDGES
\([from, to], or {\"from\", \"to\", \"label\"}); a node only an edge names is
one too. Laid out in layers by itself: boxes and arrows in the GUI (left to
right, or DIRECTION \"down\"), each node's arrows as text. STATUS ok,
error, warning, active colours a node. For module dependencies, a state
machine, a call graph."
  :props ((nodes list "The nodes: names, or {\"id\", \"label\", \"status\"}")
          (edges list "The edges: [from, to], or {\"from\", \"to\", \"label\"}")
          (direction (choice right down) "The way it goes: right (default) or down" :default right))
  :example (:title "Modules"
            :nodes ("lexer" "parser" (:id "checker" :status "error") "codegen")
            :edges (("lexer" "parser") ("parser" "checker") ("parser" "codegen") ("checker" "codegen")))
  :check #'agent-ui-graph--check
  :text #'agent-ui-graph--text
  :gui #'agent-ui-graph--gui)
