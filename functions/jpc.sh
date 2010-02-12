function jpc()
{
	NO_ARGS=0 

	if [ $# -eq "$NO_ARGS" ]
	then
		echo "please specify a php file to check"
		read name
		jcheckout "$name";
	else
		php -l "$1"
	fi
}
