function jfind()
{
	NO_ARGS=0 

	if [ $# -eq "$NO_ARGS" ]
	then
		echo "please enter a term to search for"
		read case
		jfind $case;
	else
		find . -path .git -prune -o -follow -iname \*$1\*
	fi
}
