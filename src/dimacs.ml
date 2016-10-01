open Printf

module type Cnf = sig
  type t
  val iter : (int list -> unit) -> t -> unit
  val nvars : t -> int
  val nterms : t -> int
end

module IntList = struct

  type t = int list list

  let nvars terms =
    List.fold_left 
      (List.fold_left (fun mx v -> max mx (abs v))) 
      0 terms

  let nterms terms = List.length terms

  let iter = List.iter

end

module Make(Cnf : Cnf) = struct

  let write chan terms = 
    let nvars = Cnf.nvars terms in
    let nterms = Cnf.nterms terms in
    fprintf chan "p cnf %i %i\n" nvars nterms;
    let print_term t = List.iter (fprintf chan "%i ") t; fprintf chan "0\n" in
    Cnf.iter print_term terms

  let solver_name solver = 
    match solver with
    | `crypto -> "cryptominisat4_simple"
    | `mini -> "minisat"
    | `pico -> "picosat"

  let run_solver solver fin fout = 
    let solver_name = solver_name solver in
    match solver with 
    | `crypto -> 
      ignore @@ Unix.system(sprintf "%s --verb=0 %s > %s" solver_name fin fout)
    | `mini -> 
      ignore @@ Unix.system(sprintf "%s -verb=0 %s %s" solver_name fin fout)
    | `pico -> 
      ignore @@ Unix.system(sprintf "%s %s > %s" solver_name fin fout)

  let with_out_file name fn = 
    let f = open_out name in
    let r = fn f in
    close_out f;
    r

  (* read output file *)
  let read_sat_result fout = 
    let f = open_in fout in
    let result = 
      match input_line f with
      | "SATISFIABLE" | "SAT" | "s SATISFIABLE" -> `sat
      | "UNSATISFIABLE" | "UNSAT" | "s UNSATISFIABLE" -> `unsat
      | _ -> failwith "DIMACS bad output"
      | exception _ -> failwith "DIMACS bad output"
    in
    if result = `sat then 
      let split_char sep str =
        let rec indices acc i =
          try
            let i = succ(String.index_from str i sep) in
            indices (i::acc) i
          with Not_found -> (String.length str + 1) :: acc
        in
        let is = indices [0] 0 in
        let rec aux acc = function
          | last::start::tl ->
              let w = String.sub str start (last-start-1) in
              aux (w::acc) (start::tl)
          | _ -> acc
        in
        aux [] is 
      in
      let rec read_result_lines () = 
        match input_line f with
        | _ as line -> begin
          let tokens = List.filter ((<>) "") @@ split_char ' ' line in
          match tokens with
          | "v" :: tl -> List.map int_of_string tl :: read_result_lines ()
          | _ as l -> List.map int_of_string l :: read_result_lines ()
        end
        | exception _ ->
          []
      in
      let res = List.flatten @@ read_result_lines () in
      let () = close_in f in
      `sat res
    else 
      let () = close_in f in
      `unsat

  type 'a result = [ `unsat | `sat of 'a ]

  let run ?(solver=`pico) cnf = 
    let fin = Filename.temp_file "sat_cnf_in" "hardcaml" in
    let fout = Filename.temp_file "sat_res_out" "hardcaml" in
    (* generate cfg file *)
    with_out_file fin (fun f -> write f cnf);
    (* run solver *)
    run_solver solver fin fout;
    (* parse result file *)
    let result = read_sat_result fout in
    (* delete the temporary files *)
    (try Unix.unlink fin with _ -> ());
    (try Unix.unlink fout with _ -> ());
    result

end

(* generic [int list list] based cnf interface *)
include Make(IntList)

(* generate interface libraries *)
module GenLib(X : sig 
    val solver : Sattools.Solver.t
end) = struct
  include X
  type solver = int list list ref
  let create () = ref []
  let destroy _ = ()
  let add_clause t s = t := s :: !t
  let solve t = run ~solver:X.solver !t
end

(* picosat, minisat and cryptominisat interfaces via dimacs *)
module Dimacs_pico = GenLib(struct let solver = `pico end)
module Dimacs_mini = GenLib(struct let solver = `mini end)
module Dimacs_crypto = GenLib(struct let solver = `crypto end)

let add_solver name solver = 
  match Unix.system ("which " ^ solver_name solver ^ " > /dev/null") with
  | Unix.WEXITED 0 ->
    let module X = GenLib(struct let solver = solver end) in
    Sattools.Libs.add_solver name (module X : Sattools.Libs.Solver)
  | _ -> ()

let () = add_solver "dimacs-pico" `pico
let () = add_solver "dimacs-mini" `mini
let () = add_solver "dimacs-crypto" `crypto
