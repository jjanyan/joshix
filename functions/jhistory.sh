function jhistory()
{
	NO_ARGS=0 
	if [ $# -eq "$NO_ARGS" ]
	then
		echo "jhistory search-term"
		echo "jhistory ssh"
		echo "above example would find all ssh commands in your history"
		read case
		jcopy $case;
	else
		history | grep -i $1
	fi
}
