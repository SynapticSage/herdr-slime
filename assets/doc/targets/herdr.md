### herdr

[herdr](https://herdr.dev) is *not* the default, to use it you will have to add this line to your `.vimrc`:

```vim
let g:slime_target = "herdr"
```

When you invoke `vim-slime` for the first time, you will be prompted for more configuration.

herdr session

    The herdr session that holds the target pane. Leave it empty to use the
    session vim is running in (inherited through $HERDR_SESSION /
    $HERDR_SOCKET_PATH), otherwise see `herdr session list`.

herdr pane id or direction

    The id of the pane you wish to target, like `w1:p2`.
    Press <Tab> to complete from `herdr pane list`, or see the value of
    $HERDR_PANE_ID in the target pane.
    You can also enter `left`, `right`, `up` or `down` to target the pane
    next to vim (resolved with `herdr pane neighbor`).

You can configure the defaults for these options. If you generally run vim in
a split herdr tab with a REPL to the right it could look like this:

```vim
let g:slime_default_config = {"pane_direction": "right"}
```

### bracketed-paste

Some REPLs can interfere with your text pasting. The [bracketed-paste](https://cirw.in/blog/bracketed-paste) mode exists to allow raw pasting.

`herdr` supports bracketed-paste, use:

```vim
let g:slime_bracketed_paste = 1
" or
let b:slime_bracketed_paste = 1
```

(It is disabled by default because it can create issues with ipython; see [#265](https://github.com/jpalardy/vim-slime/pull/265)).
