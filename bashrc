# Note that this file is overridden by newer versions of `nextstrain shell` and
# so it provides only a fallback prompt for users of older CLI versions or
# direct image users (e.g. `docker run …`).
reset="\[\e[0m\]"
bold="\[\e[1m\]"
magenta="\[\e[35m\]"
PS1="${bold}nextstrain:${magenta}\w${reset} ${bold}\$ ${reset}"
unset reset bold magenta
