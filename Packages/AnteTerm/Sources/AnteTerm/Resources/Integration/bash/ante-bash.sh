# Ante shell integration for bash. Loaded with `bash --init-file <this file>`, which makes bash
# skip its own startup files; we replay what a login shell would read, then install hooks.
#   133;A  before the prompt        133;B  end of prompt / start of input
#   133;C  command starting         133;D;<exit>  command finished
#   7;file://host/path  working directory
if [[ -f /etc/profile ]]; then
  source /etc/profile
fi
for __ante_profile in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
  if [[ -f "$__ante_profile" ]]; then
    source "$__ante_profile"
    break
  fi
done
unset __ante_profile

[[ $- == *i* ]] || return 0
[[ -n "$ANTE_INTEGRATION_LOADED" ]] && return 0
ANTE_INTEGRATION_LOADED=1

__ante_urlencode() {
  local LC_ALL=C
  local s="$1" out="" c i
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    if [[ "$c" == [A-Za-z0-9/._~-] ]]; then
      out+="$c"
    else
      out+=$(printf '%%%02X' "'$c")
    fi
  done
  printf '%s' "$out"
}

# Runs first in PROMPT_COMMAND so $? is still the user's command status.
__ante_capture_status() {
  __ante_last_status=$?
}

# Runs last in PROMPT_COMMAND: reports the finished command, cwd, and the new prompt.
__ante_precmd() {
  if [[ -n "$__ante_command_running" ]]; then
    printf '\033]133;D;%d\007' "$__ante_last_status"
    unset __ante_command_running
  fi
  # Always "localhost": this shim only ever runs in a local shell, and the machine's own name
  # changes with the network. A remote shell's integration reports its hostname instead.
  printf '\033]7;file://localhost%s\007' "$(__ante_urlencode "$PWD")"
  printf '\033]133;A\007'
  __ante_at_prompt=1
}

# DEBUG fires before every simple command, including the ones in PROMPT_COMMAND. Only the first
# command after a prompt is the user's, which __ante_at_prompt tracks.
__ante_preexec() {
  [[ -n "$COMP_LINE" ]] && return 0
  [[ "$__ante_at_prompt" == 1 ]] || return 0
  __ante_at_prompt=0
  __ante_command_running=1
  printf '\033]133;C\007'
}

PROMPT_COMMAND="__ante_capture_status${PROMPT_COMMAND:+; $PROMPT_COMMAND}; __ante_precmd"
trap '__ante_preexec' DEBUG
PS1="${PS1}\[\033]133;B\007\]"
