jkill()
{
	NO_ARGS=0
	if [ $# -eq "$NO_ARGS" ]
	then
		echo "please enter a single application name to search and kill"
		echo "ctrl+c to cancel"
		read case
		jkill $case;
	else
		ps -ef | grep -i $1 | awk '{print $2}' | xargs kill
	fi
}
