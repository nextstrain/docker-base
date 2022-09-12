reset="\[\e[0m\]"
bold="\[\e[1m\]"
magenta="\[\e[35m\]"
PS1="${bold}nextstrain:${magenta}\w${reset} ${bold}\$ ${reset}"
unset reset bold magenta
