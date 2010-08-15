function notify
{
	source $joshix_path/options/notify.sh
	output=`$@ 2>&1`
	if (( $? )); 
	then 
		result='bad';
	else 
		result='good';
	fi
	command=$(echo -n $@ | perl -pe's/([^-_.~A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg');
	output=$(echo -n $output | perl -pe's/([^-_.~A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg');
	url='http://'$base_url'?app=bash&event='$command'&priority=1&pass='$password'&desc='$result':'$output;
	curl $url;
}
