(*
 * Copyright (C) Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

open Lwt
open Xs_packet

let xenstored_socket = "/var/run/xenstored/socket"

type watch_queue = {
  events: string Queue.t;
  c: unit Lwt_condition.t;
  m: Lwt_mutex.t;
}

type client = {
  fd: Lwt_unix.file_descr;
  rid_to_wakeup: (int32, t Lwt.u) Hashtbl.t;
  mutable incoming_pkt: Parser.parse;
  watchevents: (Token.t, watch_queue) Hashtbl.t;
}

let rec recv_one t =
  let open Parser in match Parser.state t.incoming_pkt with
  | Packet pkt ->
    t.incoming_pkt <- start ();
    return (Some pkt)
  | Need_more_data x ->
    let buf = String.make x '\000' in
    lwt n = Lwt_unix.read t.fd buf 0 x in
    let fragment = String.sub buf 0 n in
    t.incoming_pkt <- input t.incoming_pkt fragment;
    recv_one t
  | Unknown_operation x -> Printf.printf "Unknown_operation %ld\n%!" x; return None
  | Parser_failed -> Printf.printf "Parser failed\n%!"; return None

let rec dispatcher t =
  lwt pkt = recv_one t in
  match pkt with
    | None ->
      Printf.printf "Shutting down dispatcher thread\n%!";
      return ()
    | Some pkt ->
      begin match get_ty pkt with
	| Op.Watchevent  ->
	  lwt () = begin match Response.list pkt with
	    | Some [path; token] ->
	      let token = Token.of_string token in
	      (* We may get old watches: silently drop these *)
	      if Hashtbl.mem t.watchevents token then begin
		let wq = Hashtbl.find t.watchevents token in
		lwt () = Lwt_mutex.with_lock wq.m
		  (fun () ->
		    Queue.push path wq.events;
		    Lwt_condition.signal wq.c ();
		    return ()
		  ) in
		dispatcher t
              end else dispatcher t
	    | _ ->
	      Printf.printf "Failed to parse watch event.\n%!";
	      Printf.printf "Shutting down dispatcher thread\n%!";
	      return ()
          end in
	  dispatcher t
	| _ ->
	  let rid = get_rid pkt in
	  if not(Hashtbl.mem t.rid_to_wakeup rid) then begin
	    Printf.printf "Unknown rid:%ld in ty:%s\n%!" rid (Op.to_string (get_ty pkt));
	    Printf.printf "Shutting down dispatcher thread\n%!";
	    return ()
	  end else begin
	    Lwt.wakeup (Hashtbl.find t.rid_to_wakeup rid) pkt;
	    dispatcher t
	  end
      end

let make () =
  let sockaddr = Lwt_unix.ADDR_UNIX(xenstored_socket) in
  let fd = Lwt_unix.socket Lwt_unix.PF_UNIX Lwt_unix.SOCK_STREAM 0 in
  lwt () = Lwt_unix.connect fd sockaddr in
  let t = {
    fd = fd;
    rid_to_wakeup = Hashtbl.create 10;
    incoming_pkt = Parser.start ();
    watchevents = Hashtbl.create 10;
  } in
  let (_: unit Lwt.t) = dispatcher t in
  return t



