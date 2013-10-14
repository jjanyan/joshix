function check_port()
{
	NO_ARGS=0 

	if [ $# -eq "$NO_ARGS" ]
	then
		echo "check_port :port"
		echo "check_port 80"
		read case
		check_port $case;
	else
        sudo lsof -i :80 | grep -i listen
	fi
}
