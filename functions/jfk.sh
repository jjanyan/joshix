jfk () { # build menu to kill process
    IFS=$'\n'
    PS3='Kill which process? '
    select OPT in $(fp $1) "Cancel"; do
        if [ $OPT != "Cancel" ]; then
            kill $(echo $OPT|awk '{print $NF}')
        fi
        break
    done
    unset IFS
}
