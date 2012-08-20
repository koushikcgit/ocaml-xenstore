
val map_foreign: int -> nativeint -> Cstruct.buf Lwt.t
val unmap_foreign: Cstruct.buf -> unit

val map_fd: Unix.file_descr -> int -> Cstruct.buf

val unsafe_read: Cstruct.buf -> string -> int -> int -> int
val unsafe_write: Cstruct.buf -> string -> int -> int -> int

type info = {
	domid: int;
	dying: bool;
	shutdown: bool;
}

val domain_infolist: unit -> info list Lwt.t

type xc_evtchn
val xc_evtchn_open: unit -> xc_evtchn

val xc_evtchn_close: destroy: xc_evtchn -> unit

val xc_evtchn_fd: xc_evtchn -> Unix.file_descr

val xc_evtchn_notify: xc_evtchn -> int -> unit

val xc_evtchn_bind_interdomain: xc_evtchn -> int -> int -> int

val xc_evtchn_bind_virq_dom_exc: xc_evtchn -> int

val xc_evtchn_unbind: xc_evtchn -> int -> unit

val xc_evtchn_pending: xc_evtchn -> int

val xc_evtchn_unmask: xc_evtchn -> int -> unit
