function gr()
{
    root=$(git rev-parse --show-cdup 2>/dev/null | sed 's/ *$//g')
    if [ -n "$root" ]; then
        cd "$root"
    fi
}
