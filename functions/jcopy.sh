function jcopy()
{
	NO_ARGS=0 

	if [ $# -eq "$NO_ARGS" ]
	then
		echo "please enter file to copy"
		read case
		jcopy $case;
	else
		cat "$1" | pbcopy
	fi
}
