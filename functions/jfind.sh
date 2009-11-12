function jfind()
{
	NO_ARGS=0 

	if [ $# -eq "$NO_ARGS" ]
	then
		echo "please enter a term to search for"
		read case
		jfind $case;
	else
		find . -iname \*$1\*
	fi
}
