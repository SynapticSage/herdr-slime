function! slime#targets#herdr#config() abort
  if !exists("b:slime_config")
    let b:slime_config = {"session": "", "pane_id": ""}
  end
  call extend(b:slime_config, {"session": "", "pane_id": ""}, "keep")
  if !empty(get(b:slime_config, "pane_direction", ""))
    call s:resolve_direction(b:slime_config)
  endif
  let b:slime_config["session"] = input("herdr session (empty = current): ", b:slime_config["session"])
  let panes = s:show_ids(b:slime_config, s:list_panes(b:slime_config), {})
  try
    let pane_id = input("herdr pane id or direction: ", b:slime_config["pane_id"], "custom,slime#targets#herdr#pane_names")
  finally
    call s:hide_ids(b:slime_config, panes)
  endtry
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
  let names = map(s:list_panes(config), "s:describe(config, v:val)")
  return join(names + s:directions, "\n")
endfunction

" label every pane's border with a key and its id, then pick the target by key
function! slime#targets#herdr#pick() abort
  if !slime#targets#herdr#ValidEnv()
    return
  endif
  if !exists("b:slime_config")
    let b:slime_config = {"session": "", "pane_id": ""}
  endif
  let config = b:slime_config
  let self_pane = s:caller_pane(config)
  let choices = {}
  let lines = []
  let panes = s:list_panes(config)
  for pane in panes
    if pane["pane_id"] !=# self_pane && len(choices) < len(s:pick_keys)
      let key = s:pick_keys[len(choices)]
      let choices[key] = pane["pane_id"]
      call add(lines, "[" . key . "] " . s:describe(config, pane))
    endif
  endfor
  if empty(choices)
    call s:error("herdr: no other pane to pick")
    return
  endif
  call s:show_ids(config, panes, choices)
  try
    redraw
    echo join(lines, "\n") . "\nslime target pane (<Esc> cancels): "
    let key = getchar()
    let key = type(key) == v:t_number ? nr2char(key) : key
  finally
    call s:hide_ids(config, panes)
  endtry
  redraw
  if !has_key(choices, key)
    echo ""
    return
  endif
  let config["pane_id"] = choices[key]
  silent! call remove(config, "pane_direction")
  echo "slime target: " . choices[key]
endfunction

" -------------------------------------------------

let s:directions = ["left", "right", "up", "down"]
let s:pick_keys = split("123456789abcdefghijklmnopqrstuvwxyz", '\zs')

" titles expire on their own, so a killed vim never leaves them behind
let s:id_source = "herdr-slime"
let s:id_ttl_ms = 30000

function! s:list_panes(config)
  let output = s:herdr(a:config, "pane list", [])
  try
    return json_decode(output)["result"]["panes"]
  catch
    return []
  endtry
endfunction

function! s:describe(config, pane)
  let parts = [a:pane["pane_id"]]
  let name = get(a:pane, "label", get(a:pane, "display_agent", get(a:pane, "terminal_title_stripped", "")))
  if !empty(name)
    call add(parts, name)
  endif
  if has_key(a:pane, "cwd")
    call add(parts, fnamemodify(a:pane["cwd"], ":~"))
  endif
  if a:pane["pane_id"] ==# s:caller_pane(a:config)
    call add(parts, "(this vim)")
  elseif a:pane["focused"]
    call add(parts, "(focused)")
  endif
  return join(parts)
endfunction

" herdr draws a pane's metadata title on its border, ahead of its label;
" choices maps pick keys to pane ids
function! s:show_ids(config, panes, choices)
  let keys = {}
  for [key, pane_id] in items(a:choices)
    let keys[pane_id] = key
  endfor
  for pane in a:panes
    let title = has_key(keys, pane["pane_id"]) ? "[" . keys[pane["pane_id"]] . "] " : ""
    let title .= pane["pane_id"]
    call s:herdr(a:config, "pane report-metadata %s --source %s --title %s --ttl-ms %s",
          \ [pane["pane_id"], s:id_source, title, s:id_ttl_ms])
  endfor
  return a:panes
endfunction

function! s:hide_ids(config, panes)
  for pane in a:panes
    call s:herdr(a:config, "pane report-metadata %s --source %s --clear-title", [pane["pane_id"], s:id_source])
  endfor
endfunction

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
