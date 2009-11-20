function jcopy
{
	NO_ARGS=0 

	if [ $# -eq "$NO_ARGS" ]
	then
		echo "please provide a file to cat and copy to clipboard"
		read case
		jcopy $case;
	else
		cat "$1" | pbcopy
	fi
}
