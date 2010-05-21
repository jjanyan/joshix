function jnotify()
{
	NO_ARGS=0 

	if [ $# -eq "$NO_ARGS" ]
	then
		echo 'jnotify [-m "message"] $command'
		read case
		jcopy $case;
	else
		output=$($*)
		growlnotify  -m "$output"
	fi
}
