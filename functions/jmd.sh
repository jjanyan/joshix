jmd()
{
	NO_ARGS=0
	if [ $# -eq "$NO_ARGS" ]
	then
		echo "please enter a markdown file to view"
        echo "usage:\njmd foo.md"
		read case
		jkill $case;
	else
        cat $1 | markdown2 > /tmp/markdown2.html; jq /tmp/markdown2.html;
	fi
}
