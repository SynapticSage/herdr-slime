function! slime#targets#herdr#config() abort
  if !exists("b:slime_config")
    let b:slime_config = {"session": "", "pane_id": ""}
  end
  call extend(b:slime_config, {"session": "", "pane_id": ""}, "keep")
  if !empty(get(b:slime_config, "pane_direction", ""))
    call s:resolve_direction(b:slime_config)
  endif
  let b:slime_config["session"] = input("herdr session (empty = current): ", b:slime_config["session"])
  let pane_id = input("herdr pane id or direction: ", b:slime_config["pane_id"], "custom,slime#targets#herdr#pane_names")
  " completion entries look like 'w1:p2 label ...'
  if pane_id =~ '\s'
    let pane_id = split(pane_id)[0]
  endif
  if index(s:directions, pane_id) >= 0
    let b:slime_config["pane_direction"] = pane_id
    let pane_id = ""
  elseif !empty(pane_id)
    silent! call remove(b:slime_config, "pane_direction")
  endif
  let b:slime_config["pane_id"] = pane_id
  if empty(pane_id) && !empty(get(b:slime_config, "pane_direction", ""))
    call s:resolve_direction(b:slime_config)
  endif
endfunction

function! slime#targets#herdr#ValidEnv() abort
  if !executable("herdr")
    call s:error("herdr executable not found in $PATH")
    return 0
  endif
  return 1
endfunction

function! slime#targets#herdr#ValidConfig(config, silent) abort
  if type(a:config) != v:t_dict
    return 0
  endif
  if empty(get(a:config, "pane_id", "")) && empty(get(a:config, "pane_direction", ""))
    if !a:silent
      call s:error("herdr pane id is not set, run :SlimeConfig")
    endif
    return 0
  endif
  return 1
endfunction

function! slime#targets#herdr#send(config, text) abort
  " a default config may only name a direction; resolve it on first send
  if empty(get(a:config, "pane_id", "")) && !s:resolve_direction(a:config)
    return
  endif
  let [bracketed_paste, text_to_paste, has_crlf] = slime#common#bracketed_paste(a:text)

  if len(text_to_paste) == 0
    return
  end

  " herdr writes raw bytes to the pane; like tmux paste-buffer, send newlines as Enter (CR)
  let text_to_paste = substitute(text_to_paste, '\r\?\n', "\r", 'g')
  if bracketed_paste
    let text_to_paste = "\e[200~" . text_to_paste . "\e[201~"
  endif

  " reasonable hardcode, will become config if needed
  let chunk_size = 4000

  for i in range(0, (strchars(text_to_paste) - 1) / chunk_size)
    let chunk = strcharpart(text_to_paste, i * chunk_size, chunk_size)
    " herdr parses some argv words as its own flags (-h, --help, --session, ...);
    " send leading dashes on their own so no chunk can match one
    let dashes = matchstr(chunk, '^-\+')
    for piece in [dashes, strpart(chunk, len(dashes))]
      if !empty(piece) && !s:send_text(a:config, piece)
        return
      endif
    endfor
  endfor

  " trailing newline
  if has_crlf
    call s:herdr(a:config, "pane send-keys %s Enter", [a:config["pane_id"]])
  end
endfunction

" -------------------------------------------------

function! slime#targets#herdr#pane_names(A,L,P)
  let config = exists("b:slime_config") ? b:slime_config : {}
  let output = s:herdr(config, "pane list", [])
  if empty(output)
    return join(s:directions, "\n")
  endif
  try
    let panes = json_decode(output)["result"]["panes"]
  catch
    return join(s:directions, "\n")
  endtry
  let self_pane = s:caller_pane(config)
  let names = []
  for pane in panes
    let parts = [pane["pane_id"]]
    let name = get(pane, "label", get(pane, "display_agent", get(pane, "terminal_title_stripped", get(pane, "title", ""))))
    if !empty(name)
      call add(parts, name)
    endif
    if has_key(pane, "cwd")
      call add(parts, fnamemodify(pane["cwd"], ":~"))
    endif
    if pane["pane_id"] ==# self_pane
      call add(parts, "(this vim)")
    elseif pane["focused"]
      call add(parts, "(focused)")
    endif
    call add(names, join(parts))
  endfor
  return join(names + s:directions, "\n")
endfunction

let s:directions = ["left", "right", "up", "down"]

" text goes through stdin, not the vim command line, so newlines and escape bytes
" survive any 'shell'; $(cat; printf x) keeps trailing newlines intact
let s:send_text_script = 'pane=$1; shift; t=$(cat; printf x); exec "$@" pane send-text "$pane" "${t%x}"'

function! s:send_text(config, text)
  let [base, base_args] = s:base_cmd(a:config)
  call s:run("sh -c %s slime-herdr %s " . base, [s:send_text_script, a:config["pane_id"]] + base_args, a:text)
  return !v:shell_error
endfunction

function! s:resolve_direction(config)
  let args = ["--direction", a:config["pane_direction"]]
  let self_pane = s:caller_pane(a:config)
  if !empty(self_pane)
    let args += ["--pane", self_pane]
  endif
  let output = s:herdr(a:config, "pane neighbor" . repeat(" %s", len(args)), args)
  try
    let pane_id = json_decode(output)["result"]["neighbor"]["neighbor_pane_id"]
  catch
    call s:error("herdr: no pane " . a:config["pane_direction"] . " of the current pane")
    return 0
  endtry
  let a:config["pane_id"] = pane_id
  return 1
endfunction

" the pane vim itself runs in, only meaningful in vim's own session
function! s:caller_pane(config)
  return empty(get(a:config, "session", "")) ? $HERDR_PANE_ID : ""
endfunction

function! s:base_cmd(config)
  " empty session: inherit HERDR_SESSION / HERDR_SOCKET_PATH from the environment
  if empty(get(a:config, "session", ""))
    return ["herdr", []]
  endif
  return ["herdr --session %s", [a:config["session"]]]
endfunction

function! s:herdr(config, subcmd_template, args)
  let [base, base_args] = s:base_cmd(a:config)
  return s:run(base . " " . a:subcmd_template, base_args + a:args)
endfunction

function! s:run(cmd_template, args, ...)
  let output = call("slime#common#system", [a:cmd_template, a:args] + a:000)
  if v:shell_error
    call s:error("herdr: " . trim(output))
    return ""
  endif
  return output
endfunction

function! s:error(msg)
  echohl ErrorMsg | echomsg a:msg | echohl None
endfunction
