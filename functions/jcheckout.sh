function jcheckout()
{
	NO_ARGS=0 

	if [ $# -eq "$NO_ARGS" ]
	then
		echo "please specify a branch to checkout"
		read case
		jcheckout $case;
	else
		git reset --hard
		git checkout origin/"$1"
	fi
}
