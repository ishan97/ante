# Ante shell integration for zsh: emits OSC 133 (semantic prompt) and OSC 7 (working directory).
#   133;A  before the prompt is drawn      133;B  end of prompt / start of input
#   133;C  command is starting             133;D;<exit>  command finished
#   7;file://host/path  working directory, percent-encoded
[[ -n "$ANTE_INTEGRATION_LOADED" ]] && return 0
[[ -o interactive ]] || return 0
typeset -g ANTE_INTEGRATION_LOADED=1

autoload -Uz add-zsh-hook

# Percent-encodes a path byte-wise so non-ASCII and spaces survive the trip.
_ante_urlencode() {
  local LC_ALL=C
  local s="$1" out="" c
  local -i i
  for (( i = 1; i <= ${#s}; i++ )); do
    c="${s[i]}"
    if [[ "$c" == [A-Za-z0-9/._~-] ]]; then
      out+="$c"
    else
      out+=$(printf '%%%02X' "'$c")
    fi
  done
  printf '%s' "$out"
}

_ante_report_cwd() {
  # Always "localhost": this shim only ever runs in a local shell, and the machine's own name
  # changes with the network. A remote shell's integration reports its hostname instead.
  printf '\e]7;file://localhost%s\a' "$(_ante_urlencode "$PWD")"
}

_ante_precmd() {
  local status_code=$?
  if (( ${+_ante_command_running} )); then
    printf '\e]133;D;%d\a' "$status_code"
    unset _ante_command_running
  fi
  _ante_report_cwd
  printf '\e]133;A\a'
}

_ante_preexec() {
  typeset -g _ante_command_running=1
  printf '\e]133;C\a'
}

add-zsh-hook precmd _ante_precmd
add-zsh-hook preexec _ante_preexec

# Append the input-start marker to the prompt. %{ %} tells zsh the marker has zero width.
PS1="${PS1}%{$(printf '\e]133;B\a')%}"
