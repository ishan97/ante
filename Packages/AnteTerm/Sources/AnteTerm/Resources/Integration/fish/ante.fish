# Ante shell integration for fish. Loaded with `fish -C "source <this file>"` after the user's
# own config has run.
#   133;A  before the prompt        133;B  end of prompt / start of input
#   133;C  command starting         133;D;<exit>  command finished
#   7;file://host/path  working directory
if status is-interactive; and not set -q ANTE_INTEGRATION_LOADED
    set -g ANTE_INTEGRATION_LOADED 1

    function __ante_report_cwd
        set -l encoded (string escape --style=url -- $PWD | string replace -a '%2F' '/')
        # Always "localhost": a local shim, and the machine's name changes with the network.
        printf '\e]7;file://localhost%s\a' $encoded
    end

    function __ante_preexec --on-event fish_preexec
        set -g __ante_command_running 1
        printf '\e]133;C\a'
    end

    function __ante_postexec --on-event fish_postexec
        printf '\e]133;D;%d\a' $status
        set -e __ante_command_running
    end

    function __ante_prompt --on-event fish_prompt
        __ante_report_cwd
        printf '\e]133;A\a'
    end

    # Wrap the user's prompt so the input-start marker follows it.
    if functions -q fish_prompt
        functions -c fish_prompt __ante_user_fish_prompt
    end
    function fish_prompt
        if functions -q __ante_user_fish_prompt
            __ante_user_fish_prompt
        else
            printf '> '
        end
        printf '\e]133;B\a'
    end
end
