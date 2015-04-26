# Sup Bash completion
#
# * Complete options for all Sup commands.
# * Disable completion for next option when current option takes an argument.
# * Complete sources, directories, and files, where applicable.

_sup_cmds() {
    local cur prev opts sources
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    sources="$(sed -n '/uri:/ {s/.*uri:\s*//p}' $HOME/.sup/sources.yaml)"

    case "${1##/*}" in
        sup-add)
            opts="--archive -a --unusual -u --sync-back --no-sync-back -s
                  --labels -l --force-new -f --force-account -o --version -v
                  --help -h mbox: maildir:"

            case $prev in
                --labels|-l|--force-account|-o)
                    COMPREPLY=()
                    return 0
                    ;;
            esac
            ;;
        sup-config|sup-dump)
            opts="--version -v --help -h"
            ;;
        sup-import-dump)
           opts="--verbose -v --ignore-missing -i --warn-missing -w
                 --abort-missing -a --atomic -t --dry-run -n --version --help
                 -h"
            ;;
        sup)
            opts="--list-hooks -l --no-threads -n --no-initial-poll -o --search
                  -s --compose -c --subject -j --version -v --help -h"

            case $prev in
                --search|-s|--compose|-c|--subject|-j)
                    COMPREPLY=()
                    return 0
                    ;;
            esac
            ;;
        sup-recover-sources)
            opts="--unusual --archive --scan-num --help -h $sources"

            case $prev in
                --scan-num)
                    COMPREPLY=()
                    return 0
                    ;;
            esac
            ;;
        sup-sync)
            opts="--asis --restore --discard --archive -x --read -r
                  --extra-labels --verbose -v --optimize -o --all-sources
                  --dry-run -n --version --help -h ${sources}"


            case $prev in
                --restore|--extra-labels)
                    COMPREPLY=()
                    return 0
                    ;;
            esac
            ;;
        sup-sync-back-maildir)
            maildir_sources="$(echo $sources | tr ' ' '\n' | grep maildir)"
            opts="--no-confirm -n --no-merge -m --list-sources -l
                  --unusual-sources-too -u --version -v --help -h
                  $maildir_sources"
            ;;
        sup-tweak-labels)
            opts="--add -a --remove -r --query -q --verbose -v --very-verbose
                  -e --all-sources --dry-run -n --no-sync-back -o --version
                  --help -h $sources"

            case $prev in
                --add|-a|--remove|-r|--query|-q)
                    COMPREPLY=()
                    return 0
                    ;;
            esac
            ;;
    esac

    COMPREPLY=( $(compgen -W "$opts" -- ${cur}) )
    return 0
}

complete -F _sup_cmds sup \
                      sup-add \
                      sup-config \
                      sup-dump \
                      sup-recover-sources \
                      sup-sync \
                      sup-sync-back-maildir \
                      sup-tweak-labels

complete -F _sup_cmds -o filenames -o plusdirs sup-import-dump
