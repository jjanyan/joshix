function jwhich()
{
	NO_ARGS=0 

	if [ $# -eq "$NO_ARGS" ]
	then
		echo "jwhish executable"
		echo "jgrep vim"
		read case
		jcopy $case;
	else
        ls -lta $(which "$1")
	fi
}
