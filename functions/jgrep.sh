function jgrep()
{
	NO_ARGS=0 

	if [ $# -eq "$NO_ARGS" ]
	then
		echo "jgrep file-extension search-term"
		echo "jgrep php adsnip"
		read case
		jcopy $case;
	else
		grep -r --include=*.$1 "$2" ./
	fi
}

function jgrepi()
{
	NO_ARGS=0 

	if [ $# -eq "$NO_ARGS" ]
	then
		echo "jgrep file-extension search-term"
		echo "jgrep php adsnip"
		read case
		jcopy $case;
	else
		grep -ir --include=*.$1 "$2" ./
	fi
}
