#compdef sup sup-add sup-config sup-dump sup-sync sup-tweak-labels sup-recover-sources
# vim: set et sw=2 sts=2 ts=2 ft=zsh :

# TODO: sources completion: maildir://some/dir, mbox://some/file, ...
#       for sup-add, sup-sync, sup-tweak-labels

(( ${+functions[_sup_cmd]} )) ||
_sup_cmd()
{
  _arguments -s : \
    "(--list-hooks -l)"{--list-hooks,-l}"[list all hooks and descriptions, and quit]" \
    "(--no-threads -n)"{--no-threads,-n}"[turn off threading]" \
    "(--no-initial-poll -o)"{--no-initial-poll,-o}"[Don't poll for new messages when starting]" \
    "(--search -s)"{--search,-s}"[search for this query upon startup]:Query: " \
    "(--compose -c)"{--compose,-c}"[compose message to this recipient upon startup]:Email: " \
    "--version[show version information]" \
    "(--help -h)"{--help,-h}"[show help]"
}

(( ${+functions[_sup_add_cmd]} )) ||
_sup_add_cmd()
{
  _arguments -s : \
    "(--archive -a)"{--archive,-a}"[automatically archive all new messages from this source]" \
    "(--unusual -u)"{--unusual,-u}"[do not automatically poll for new messages from this source]" \
    "(--labels -l)"{--labels,-l}"[set of labels to apply to all messages from this source]:Labels: " \
    "(--force-new -f)"{--force-new,-f}"[create a new account for this source, even if one already exists]" \
    "--version[show version information]" \
    "(--help -h)"{--help,-h}"[show help]"
}

(( ${+functions[_sup_config_cmd]} )) ||
_sup_config_cmd()
{
  _arguments -s : \
    "--version[show version information]" \
    "(--help -h)"{--help,-h}"[show help]"
}

(( ${+functions[_sup_dump_cmd]} )) ||
_sup_dump_cmd()
{
  _arguments -s : \
    "--version[show version information]" \
    "(--help -h)"{--help,-h}"[show help]"
}

(( ${+functions[_sup_recover_sources_cmd]} )) ||
_sup_recover_sources_cmd()
{
  _arguments -s : \
    "--archive[automatically archive all new messages from this source]" \
    "--scan-num[number of messages to scan per source]:" \
    "--unusual[do not automatically poll for new messages from this source]" \
    "(--help -h)"{--help,-h}"[show help]"
}

(( ${+functions[_sup_sync_cmd]} )) ||
_sup_sync_cmd()
{
  # XXX Add only when --restore is given: (--restored -r)
  #     Add only when --changed or--all are given: (--start-at -s)
  _arguments -s : \
    "--new[operate on new messages only]" \
    "(--changed -c)"{--changed,-c}"[scan over the entire source for messages that have been deleted, altered, or moved from another source]" \
    "(--restored -r)"{--restored,-r}"[operate only on those messages included in a dump file as specified by --restore which have changed state]" \
    "(--all -a)"{--all,-a}"[operate on all messages in the source, regardless of newness or changedness]" \
    "(--start-at -s)"{--start-at,-s}"[start at a particular offset]:Offset: " \
    "--asis[if the message is already in the index, preserve its state, otherwise, use default source state]" \
    "--restore[restore message state from a dump file created with sup-dump]:File:_file" \
    "--discard[discard any message state in the index and use the default source state]" \
    "(--archive -x)"{--archive,-x}"[mark messages as archived when using the default source state]" \
    "(--read -e)"{--read,-e}"[mark messages as read when using the default source state]" \
    "--extra-labels[apply these labels when using the default source state]:Labels: " \
    "(--verbose -v)"{--verbose,-v}"[print message ids as they're processed]" \
    "(--optimize -o)"{--optimize,-o}"[as the final operation, optimize the index]" \
    "--all-sources[scan over all sources]" \
    "(--dry-run -n)"{--dry-run,-n}"[don't actually modify the index]" \
    "--version[show version information]" \
    "(--help -h)"{--help,-h}"[show help]"
}

(( ${+functions[_sup_sync_back_cmd]} )) ||
_sup_sync_back_cmd()
{
  _arguments -s : \
    "(--drop-deleted -d)"{--drop-deleted,-d}"[drop deleted messages]" \
    "--move-deleted[move deleted messages to a local mbox file]:File:_file" \
    "(--drop-spam -s)"{--drop-spam,-s}"[drop spam messages]" \
    "--move-spam[move spam messages to a local mbox file]:File:_file" \
    "--with-dotlockfile[specific dotlockfile location (mbox files only)]:File:_file" \
    "--dont-use-dotlockfile[don't use dotlockfile to lock mbox files]" \
    "(--verbose -v)"{--verbose,-v}"[print message ids as they're processed]" \
    "(--dry-run -n)"{--dry-run,-n}"[don't actually modify the index]" \
    "--version[show version information]" \
    "(--help -h)"{--help,-h}"[show help]"
}

(( ${+functions[_sup_tweak_labels_cmd]} )) ||
_sup_tweak_labels_cmd()
{
  _arguments -s : \
    "(--add -a)"{--add,-a}"[which labels to add to every message from the specified sources]:Labels: " \
    "(--remove -r)"{--remove,-r}"[which labels to remove from every message from the specified sources]:Labels: " \
    "--all-sources[scan over all sources]" \
    "(--verbose -v)"{--verbose,-v}"[print message ids as they're processed]" \
    "(--dry-run -n)"{--dry-run,-n}"[don't actually modify the index]" \
    "--version[show version information]" \
    "(--help -h)"{--help,-h}"[show help]"
}

_call_function ret _${words[1]//-/_}_cmd
return ret

